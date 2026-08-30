#!/usr/bin/env python3
"""Static architecture boundary checks.

The checks are intentionally lightweight and only enforce boundaries that have
already been migrated. They do not import project modules or require database
dependencies, so they can run in CI and local smoke tests.
"""
from __future__ import annotations

import ast
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    message: str

    def format(self) -> str:
        rel = self.path.relative_to(ROOT)
        return f"{rel}:{self.line}: {self.message}"


@dataclass(frozen=True)
class PythonRule:
    root: str
    banned_prefixes: tuple[str, ...]
    reason: str


@dataclass(frozen=True)
class TsRule:
    root: str
    banned_patterns: tuple[re.Pattern[str], ...]
    reason: str


@dataclass(frozen=True)
class TsImport:
    spec: str
    line: int
    is_type_only: bool


@dataclass(frozen=True)
class SwiftRule:
    root: str
    banned_patterns: tuple[re.Pattern[str], ...]
    reason: str


PYTHON_RULES = (
    PythonRule(
        root="services/client_api",
        banned_prefixes=("pipeline",),
        reason="client API serves versioned read/state models and must not orchestrate ingestion or scoring jobs",
    ),
    PythonRule(
        root="pipeline/cli",
        banned_prefixes=(
            "pipeline.analyze",
            "pipeline.common",
            "pipeline.domain",
            "pipeline.ingest",
            "pipeline.platforms",
            "pipeline.daily",
            "pipeline.sync",
        ),
        reason="CLI may only parse args and call pipeline.jobs",
    ),
    PythonRule(
        root="pipeline/jobs",
        banned_prefixes=("pipeline.analyze", "pipeline.ingest", "pipeline.cli"),
        reason="jobs may orchestrate domain/platform modules, not legacy implementations",
    ),
    PythonRule(
        root="pipeline/platforms",
        banned_prefixes=("pipeline.analyze", "pipeline.cli", "pipeline.domain", "pipeline.ingest", "pipeline.jobs"),
        reason="platform adapters must not depend on domain/ingest/jobs/CLI layers",
    ),
    PythonRule(
        root="pipeline/domain",
        banned_prefixes=("pipeline.analyze", "pipeline.cli", "pipeline.ingest", "pipeline.jobs", "pipeline.platforms"),
        reason="domain logic must remain platform/job/CLI independent",
    ),
)

CLI_COMMAND_JOB_ALLOWLIST = {
    "pipeline/cli/commands/core.py": ("pipeline.jobs.core",),
    "pipeline/cli/commands/global_retail.py": ("pipeline.jobs.global_retail",),
    "pipeline/cli/commands/kol.py": ("pipeline.jobs.kol",),
    "pipeline/cli/commands/narratives.py": ("pipeline.jobs.narrative_rotation",),
    "pipeline/cli/commands/smart_voice.py": ("pipeline.jobs.smart_voice",),
    "pipeline/cli/commands/youtube.py": ("pipeline.jobs.youtube",),
}


TS_RULES = (
    TsRule(
        root="web/app",
        banned_patterns=(
            re.compile(r"^@/components/bsmart(?:/|$)"),
            re.compile(r"^@/lib/.*Queries$"),
        ),
        reason="routes should compose features/server queries, not legacy bSmart components or legacy query files",
    ),
    TsRule(
        root="web/features",
        banned_patterns=(
            re.compile(r"^@/app(?:/|$)"),
            re.compile(r"^@/components/bsmart(?:/|$)"),
            re.compile(r"^@/lib/.*Queries$"),
        ),
        reason="features must not depend on app routes or legacy bSmart/query modules",
    ),
    TsRule(
        root="web/shared",
        banned_patterns=(
            re.compile(r"^@/app(?:/|$)"),
            re.compile(r"^@/components/bsmart(?:/|$)"),
            re.compile(r"^@/features(?:/|$)"),
            re.compile(r"^@/server(?:/|$)"),
        ),
        reason="shared modules must stay independent of app/features/server layers",
    ),
    TsRule(
        root="web/server",
        banned_patterns=(
            re.compile(r"^@/app(?:/|$)"),
            re.compile(r"^@/components(?:/|$)"),
            re.compile(r"^@/features(?:/|$)"),
        ),
        reason="server queries must not import UI/application layers",
    ),
)


SWIFT_RULES = (
    SwiftRule(
        root="ios/BSmart/Features",
        banned_patterns=(
            re.compile(r"\bURLSession\b"),
            re.compile(r"\bUserDefaults\b"),
            re.compile(r"\bBundle\b"),
            re.compile(r"\b(?:SQLite|sqlite3)\b"),
            re.compile(r"^\s*import\s+(?:CoreData|WebKit)\s*$"),
        ),
        reason="iOS features may consume AppModel/Core APIs but not own networking, persistence, SQLite, or WebView",
    ),
    SwiftRule(
        root="ios/BSmart/Core/Models",
        banned_patterns=(re.compile(r"^\s*import\s+SwiftUI\s*$"),),
        reason="iOS contract models must remain UI-framework independent",
    ),
    SwiftRule(
        root="ios/bSmart",
        banned_patterns=(
            re.compile(r"\bWKWebView\b"),
            re.compile(r"\bdev\.db\b"),
        ),
        reason="the native app must not embed the website or read the repository database",
    ),
)


TS_IMPORT_RE = re.compile(
    r"""^\s*import\s+(?P<type>type\s+)?(?:(?P<body>[^"']*?)\s+from\s+)?["'](?P<spec>[^"']+)["']"""
)
LEGACY_TS_IMPORT_RE = re.compile(
    r"""(?:from\s+["'](?P<from>[^"']+)["'])|(?:import\s+["'](?P<side_effect>[^"']+)["'])"""
)


def iter_files(root: str, suffixes: tuple[str, ...]) -> list[Path]:
    base = ROOT / root
    if not base.exists():
        return []
    return sorted(
        path
        for path in base.rglob("*")
        if path.is_file()
        and path.suffix in suffixes
        and "__pycache__" not in path.parts
        and ".next" not in path.parts
    )


def module_name(path: Path) -> str:
    rel = path.relative_to(ROOT).with_suffix("")
    return ".".join(rel.parts)


def resolve_python_import(path: Path, node: ast.Import | ast.ImportFrom) -> list[tuple[str, int]]:
    if isinstance(node, ast.Import):
        return [(alias.name, node.lineno) for alias in node.names]

    module = node.module or ""
    if node.level == 0:
        return [(module, node.lineno)] if module else []

    current = module_name(path).split(".")
    package = current if path.name == "__init__.py" else current[:-1]
    keep = max(0, len(package) - (node.level - 1))
    prefix = package[:keep]
    absolute = ".".join(part for part in [*prefix, module] if part)
    return [(absolute, node.lineno)] if absolute else []


def check_python() -> list[Violation]:
    violations: list[Violation] = []
    for rule in PYTHON_RULES:
        for path in iter_files(rule.root, (".py",)):
            try:
                tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            except SyntaxError as exc:
                violations.append(Violation(path, exc.lineno or 1, f"cannot parse Python file: {exc.msg}"))
                continue
            for node in ast.walk(tree):
                if not isinstance(node, ast.Import | ast.ImportFrom):
                    continue
                for imported, line in resolve_python_import(path, node):
                    if any(imported == prefix or imported.startswith(prefix + ".") for prefix in rule.banned_prefixes):
                        violations.append(
                            Violation(path, line, f"forbidden import `{imported}`: {rule.reason}")
                        )
    violations.extend(check_cli_job_ownership())
    return violations


def check_cli_job_ownership() -> list[Violation]:
    violations: list[Violation] = []
    for rel, allowed_prefixes in CLI_COMMAND_JOB_ALLOWLIST.items():
        path = ROOT / rel
        if not path.exists():
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except SyntaxError as exc:
            violations.append(Violation(path, exc.lineno or 1, f"cannot parse Python file: {exc.msg}"))
            continue
        for node in ast.walk(tree):
            if not isinstance(node, ast.Import | ast.ImportFrom):
                continue
            for imported, line in resolve_python_import(path, node):
                if not (imported == "pipeline.jobs" or imported.startswith("pipeline.jobs.")):
                    continue
                if any(imported == prefix or imported.startswith(prefix + ".") for prefix in allowed_prefixes):
                    continue
                allowed = ", ".join(allowed_prefixes)
                violations.append(
                    Violation(
                        path,
                        line,
                        f"forbidden job import `{imported}`: CLI command modules may only call their owning job layer ({allowed})",
                    )
                )
    return violations


def ts_imports(path: Path) -> list[TsImport]:
    out: list[TsImport] = []
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = TS_IMPORT_RE.search(line)
        if match:
            spec = match.group("spec")
            out.append(TsImport(spec=spec, line=line_no, is_type_only=bool(match.group("type"))))
            continue
        match = LEGACY_TS_IMPORT_RE.search(line)
        if not match:
            continue
        spec = match.group("from") or match.group("side_effect")
        if spec:
            out.append(TsImport(spec=spec, line=line_no, is_type_only=False))
    return out


def check_typescript() -> list[Violation]:
    violations: list[Violation] = []
    for rule in TS_RULES:
        for path in iter_files(rule.root, (".ts", ".tsx")):
            for imported in ts_imports(path):
                if any(pattern.search(imported.spec) for pattern in rule.banned_patterns):
                    violations.append(Violation(path, imported.line, f"forbidden import `{imported.spec}`: {rule.reason}"))
                if (
                    rule.root == "web/features"
                    and imported.spec.startswith("@/server/")
                    and not imported.is_type_only
                ):
                    violations.append(
                        Violation(
                            path,
                            imported.line,
                            f"forbidden runtime import `{imported.spec}`: features may only import server query types with `import type`",
                        )
                    )
    return violations


def check_swift() -> list[Violation]:
    violations: list[Violation] = []
    required = (
        ROOT / "ios/project.yml",
        ROOT / "contracts/openapi/bsmart-v1.yaml",
        ROOT / "design/tokens/bsmart.tokens.json",
    )
    for path in required:
        if not path.exists():
            violations.append(Violation(path, 1, "required iOS-first architecture file is missing"))

    for rule in SWIFT_RULES:
        for path in iter_files(rule.root, (".swift",)):
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                for pattern in rule.banned_patterns:
                    if pattern.search(line):
                        violations.append(Violation(path, line_number, rule.reason))
    return violations


def main() -> int:
    violations = [*check_python(), *check_typescript(), *check_swift()]
    if violations:
        print("Architecture boundary check failed:\n")
        for violation in violations:
            print(f"  {violation.format()}")
        print(f"\n{len(violations)} violation(s).")
        return 1
    print("Architecture boundary check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

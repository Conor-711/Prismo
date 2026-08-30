#!/usr/bin/env python3
"""Prevent legacy Smart Account product terms from returning to UI and docs."""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN_ROOTS = (
    ROOT / "web/app",
    ROOT / "web/components",
    ROOT / "web/features",
    ROOT / "web/lib/dictionaries",
    ROOT / "web/shared",
    ROOT / "docs",
    ROOT / "pipeline",
    ROOT / "ios",
    ROOT / "contracts",
)
SCAN_FILES = (
    ROOT / "ARCHITECTURE.md",
    ROOT / "README.md",
    ROOT / "CLAUDE.md",
    ROOT / "SCORE_ALGORITHM.md",
)
SUFFIXES = {".json", ".md", ".py", ".sh", ".swift", ".ts", ".tsx", ".yaml", ".yml"}
SKIP_PARTS = {".next", ".venv", "__pycache__", "node_modules", "out"}

# Underscores are treated as identifier characters so legacy keys such as
# SV_Global remain legal compatibility details while a user-facing standalone
# abbreviation is rejected.
BANNED_TERMS = (
    (re.compile(r"Smart Voice", re.IGNORECASE), "use `Smart Account` for the product"),
    (re.compile(r"SE/(?:Score|SV)", re.IGNORECASE), "use `Score` for the metric"),
    (
        re.compile(r"(?<![A-Za-z0-9_-])HL-SV(?![A-Za-z0-9_-])", re.IGNORECASE),
        "use `Onchain Score` for the wallet metric",
    ),
    (re.compile(r"(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])"), "use `Score` for the metric"),
)

# Preserve quoted source material where SV has an unrelated, explicit meaning.
ALLOWED_SOURCE_TERMS = (re.compile(r"\bSV venture capital\b", re.IGNORECASE),)


@dataclass(frozen=True)
class Violation:
    path: Path
    line: int
    message: str

    def format(self) -> str:
        return f"{self.path.relative_to(ROOT)}:{self.line}: {self.message}"


def iter_files() -> list[Path]:
    files = [path for path in SCAN_FILES if path.exists()]
    for base in SCAN_ROOTS:
        if not base.exists():
            continue
        files.extend(
            path
            for path in base.rglob("*")
            if path.is_file()
            and path.suffix in SUFFIXES
            and not any(part in SKIP_PARTS for part in path.parts)
        )
    return sorted(set(files))


def check_terms() -> list[Violation]:
    violations: list[Violation] = []
    for path in iter_files():
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            scannable_line = line
            for allowed_pattern in ALLOWED_SOURCE_TERMS:
                scannable_line = allowed_pattern.sub("", scannable_line)
            for pattern, message in BANNED_TERMS:
                if pattern.search(scannable_line):
                    violations.append(Violation(path, line_number, message))
    return violations


def check_canonical_surface() -> list[Violation]:
    violations: list[Violation] = []
    required = (
        ROOT / "docs/contracts/smart_account.md",
        ROOT / "docs/architecture/05-smart-account.md",
        ROOT / "web/features/smart-account/index.ts",
        ROOT / "web/app/[lang]/(app)/smart-account/page.tsx",
    )
    for path in required:
        if not path.exists():
            violations.append(Violation(path, 1, "canonical Smart Account surface is missing"))

    nav_path = ROOT / "web/components/nav.tsx"
    nav = nav_path.read_text(encoding="utf-8") if nav_path.exists() else ""
    if 'href: "/smart-account"' not in nav or 'key: "smartAccount"' not in nav:
        violations.append(Violation(nav_path, 1, "navigation must use the canonical Smart Account route and key"))
    if 'key: "smartVoice"' in nav:
        violations.append(Violation(nav_path, 1, "legacy navigation key must not be used"))
    return violations


def main() -> int:
    violations = [*check_terms(), *check_canonical_surface()]
    if violations:
        print("Product terminology check failed:")
        for violation in violations:
            print(f"- {violation.format()}")
        return 1
    print("Product terminology check passed: Smart Account / Score are canonical.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

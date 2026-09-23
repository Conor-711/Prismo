"""User-supplied daily X package -> resumable processing -> publishable read models."""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from ...platforms.x.daily_package import stage_package


def write_json(path: Path, value) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def run(*, package: str, database: str, output: str, apply: bool = False,
        workers: int = 2, max_calls: int = 1000, publish: bool = False,
        skip_translation: bool = False, reading_package_only: bool = False) -> dict:
    if publish and not apply:
        raise ValueError("--publish requires --apply")
    target = os.environ.get("BSMART_CONTENT_PUBLISH_TARGET", "legacy")
    if publish and target not in {"legacy", "supabase"}:
        raise ValueError("BSMART_CONTENT_PUBLISH_TARGET must be legacy or supabase")
    if not 1 <= workers <= 16 or max_calls < 1:
        raise ValueError("workers must be 1..16 and max-calls must be positive")
    database_path = Path(database).expanduser().resolve()
    if not database_path.is_file():
        raise FileNotFoundError("Existing local source database required")
    root = Path(output).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    with (database_path.parent / ".x-daily.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("Another daily X workflow is running") from exc
        with tempfile.TemporaryDirectory(prefix="x-stage-", dir=root) as staging:
            info = stage_package(Path(package).expanduser().resolve(), Path(staging))
            run_dir = root / info["packageHash"]
            run_dir.mkdir(exist_ok=True)
            info["database"] = str(database_path)
            if not apply:
                plan = {key: value for key, value in info.items() if key != "postIds"}
                plan.update(status="inspected", output=str(run_dir), maxCalls=max_calls,
                            skipTranslation=skip_translation,
                            readingPackageOnly=reading_package_only,
                            stages=["import", "candidates", "extract", "prices", "settle", "score", "reading", "export", "media", "publish"])
                write_json(run_dir / "inspection.json", plan)
                print(json.dumps(plan, ensure_ascii=False, indent=2))
                return plan
            state_path = run_dir / "run.json"
            if state_path.exists():
                state = json.loads(state_path.read_text())
                if state["database"] != str(database_path):
                    raise ValueError("This package journal belongs to another source database")
                if state.get("skipTranslation", False) != skip_translation:
                    raise ValueError("Translation mode changed; use the original mode or a separate --output directory")
                if state.get("readingPackageOnly", False) != reading_package_only:
                    raise ValueError("Reading scope changed; use the original scope or a separate --output directory")
            else:
                state = {**info, "asOf": datetime.now(timezone.utc).isoformat(), "steps": {},
                         "status": "running", "skipTranslation": skip_translation,
                         "readingPackageOnly": reading_package_only}
            # Config is resolved before importing modules with process-global DB engines.
            write_json(state_path, state)
            environment = {**os.environ, "DATABASE_URL": f"sqlite:///{database_path}", "PRICE_DB": str(database_path)}
            subprocess.run([sys.executable, "-m", "pipeline.jobs.x_daily.worker", str(state_path),
                            staging, str(workers), str(max_calls)],
                           cwd=Path(__file__).resolve().parents[3], env=environment, check=True,
                           pass_fds=(lock.fileno(),))
            state = json.loads(state_path.read_text())
            if publish:
                python = Path(__file__).resolve().parents[3] / "services/client_api/.venv/bin/python"
                if not python.is_file():
                    raise RuntimeError("Install the Client API runtime before publishing")
                module = "services.client_api.content_release" if target == "supabase" else "services.client_api.publish_daily_x"
                subprocess.run([str(python), "-m", module,
                                "--input-dir", str(run_dir / "release"), "--apply"],
                               cwd=Path(__file__).resolve().parents[3], check=True)
                state["status"] = "published"
                state["publicationTarget"] = target
                write_json(state_path, state)
            print(json.dumps({"status": state["status"], "output": str(run_dir), "steps": state["steps"]}, ensure_ascii=False, indent=2))
            return state


def _process(state: dict, state_path: Path, staging: Path, run_dir: Path, workers: int, max_calls: int) -> None:
    from ...common.db import engine
    from ...domain.smart_voice import daily_x, v0_impl as score
    from ...domain.opinions import kol_refine, kol_translate
    from ...platforms.x.archive import import_archives
    from ...platforms.x.opinion_media import attach_media_to_release, enrich_posts
    from ...platforms.market_data.daily_prices import refresh
    from ..smart_voice.client_read_model import export_smart_account_client_read_model

    versions = {"workflow": 1, "scoring": score.SV_SCORING_VERSION, "ranking": score.SV_RANKING_VERSION}
    if state.get("processingVersions", versions) != versions and state["steps"]:
        raise RuntimeError("Processing versions changed; inspect and start a separate run directory")
    state["processingVersions"] = versions
    if Path(engine.url.database or "").resolve() != Path(state["database"]):
        raise RuntimeError("Loaded pipeline DB differs from --database; run in a fresh CLI process")
    rankings_frozen = os.environ.get("BSMART_RANKINGS_FROZEN", "true").lower() not in {"0", "false", "no"}
    con = daily_x.connect(state["database"])
    as_of = datetime.fromisoformat(state["asOf"])
    post_ids = set(state["postIds"])

    def step(name, action):
        if name in state["steps"]:
            return
        state.update(status="running", activeStep=name)
        write_json(state_path, state)
        print(f"[x-daily] {name}", flush=True)
        try:
            state["steps"][name] = {"result": action(), "completedAt": datetime.now(timezone.utc).isoformat()}
            write_json(state_path, state)
        except BaseException as exc:
            state.update(status="failed", failedStep=name, errorType=type(exc).__name__)
            write_json(state_path, state)
            raise

    try:
        step("import", lambda: import_archives(engine, [staging]))
        step("candidates", lambda: score.build_candidates(con, [staging], 0, 12.0, None, initialize_schema=False))
        step("extract", lambda: daily_x.extract(con, post_ids, workers, max_calls))
        step("prices", lambda: refresh(con, daily_x.price_scope(con)))
        step("settle", lambda: score.settle_calls(con, {"x"}, initialize_schema=False))
        step("score", (lambda: {"status": "frozen"}) if rankings_frozen else
             (lambda: score.score_investors(con, sources={"x"}, initialize_schema=False)))

        def prepare_readings():
            rows = daily_x.reading_rows(con, daily_x.collections(con, as_of))
            if state.get("readingPackageOnly", False):
                rows = [row for row in rows if row["item_id"] in post_ids]
            if len(rows) > max_calls:
                raise RuntimeError(f"{len(rows)} reading rows exceed --max-calls {max_calls}")
            kol_refine.refine(sources=["x"], rows=rows, workers=workers,
                              initialize_schema=False, complete_text=True)
            if not state.get("skipTranslation", False):
                kol_translate.translate(sources=["x"], rows=rows, workers=workers,
                                        initialize_schema=False, complete_text=True)
            quality = daily_x.validate_readings(con, rows, require_translation=not state.get("skipTranslation", False))
            quality["readingScope"] = "package" if state.get("readingPackageOnly", False) else "display-window"
            return quality

        step("reading", prepare_readings)

        def export():
            release = run_dir / "release"
            export_smart_account_client_read_model(db_path=state["database"], output_dir=str(release),
                                                  as_of=as_of, update_limit=0)
            collections = {}
            for name in ("smart-accounts", "smart-account-updates", "smart-account-evidence"):
                path = release / f"{name}.json"
                documents = [item for item in json.loads(path.read_text()) if item.get("platform") == "X"]
                if name == "smart-accounts" and not documents:
                    raise RuntimeError("No formal X profiles; refusing empty publication")
                write_json(path, documents)
                collections[name] = {"count": len(documents), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            write_json(release / "daily-x-manifest.json", {
                "version": 1, "status": "ready", "packageHash": state["packageHash"],
                "asOf": state["asOf"], "sourceFrom": state["sourceFrom"], "sourceThrough": state["sourceThrough"],
                "scoringVersion": score.SV_SCORING_VERSION, "rankingVersion": score.SV_RANKING_VERSION,
                "collections": collections, "quality": state["steps"]["reading"]["result"],
            })
            return {key: value["count"] for key, value in collections.items()}

        step("export", export)

        def attach_media():
            release = run_dir / "release"
            selected_ids = {row.get("sourcePostId") for name in ("smart-account-updates", "smart-account-evidence")
                            for row in json.loads((release / f"{name}.json").read_text())}
            posts = []
            for path in sorted(staging.glob("tweets_*.jsonl")):
                with path.open() as stream:
                    for line in stream:
                        if line.strip():
                            post = json.loads(line)
                            if str(post.get("tweet_id")) in selected_ids:
                                posts.append(post)
            try:
                enriched = enrich_posts(con, posts) if posts else {"posts": 0, "withImages": 0, "images": 0, "failed": 0}
                return {**enriched, "attached": attach_media_to_release(con, release)}
            except Exception as exc:
                # Media is supplementary; a CDN or Storage failure must not block text publication.
                return {"status": "unavailable", "errorType": type(exc).__name__}

        step("media", attach_media)
        if state["status"] != "published":
            state["status"] = "ready"
        state.pop("activeStep", None)
        state.pop("errorType", None)
        state.pop("failedStep", None)
        write_json(state_path, state)
    finally:
        con.close()

"""Export the unaudited research report for the iOS research preview."""

import json
import math
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REPORT_DIR = ROOT / "data/reports/investor_ability"
SUBJECTS_PATH = ROOT / "ios/BSmart/Resources/subject-activity.json"
OUTPUT = ROOT / "ios/BSmart/Resources/ability-research-snapshot.json"
DB_PATH = ROOT / "data/dev.db"


def finite(value):
    return value if isinstance(value, (float, int)) and math.isfinite(value) else None


def platform_avatars():
    if not DB_PATH.is_file():
        return {}, {}
    with sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True) as db:
        x_by_id = {
            author_id.lower(): avatar_url
            for author_id, avatar_url in db.execute(
                "SELECT author_id, avatar_url FROM author_profile WHERE source = 'x' AND avatar_url != ''"
            )
        }
        by_handle = {
            (source, handle.lower()): url
            for source, handle, url in db.execute(
                "SELECT source, handle, url FROM author_avatar WHERE url IS NOT NULL AND url != ''"
            )
        }
    return x_by_id, by_handle


def main():
    summary = json.loads((REPORT_DIR / "summary.json").read_text())
    research = json.loads((REPORT_DIR / "subjects.json").read_text())
    app_subjects = json.loads(SUBJECTS_PATH.read_text())["subjects"]
    x_avatars, handle_avatars = platform_avatars()
    by_name = defaultdict(list)
    by_id = {subject["id"]: subject for subject in app_subjects}
    for subject in app_subjects:
        by_name[(subject["kind"], subject["name"].casefold())].append(subject)

    rows = []
    for subject in research:
        score = finite(subject.get("research_score"))
        win_rate = finite(subject.get("win_rate"))
        replay_return = finite(subject.get("follow_return"))
        proxy_return = finite(subject.get("directional_follow_return_proxy"))
        follow_return = replay_return if replay_return is not None else proxy_return
        kind = subject["actor_kind"]
        actor_id = subject["actor_id"]
        matched = by_id.get(actor_id)
        if matched is None:
            names = by_name[(kind, subject["name"].casefold())]
            if len(names) == 1:
                matched = names[0]
        if matched is not None:
            actor_id = matched["id"]
        avatar_url = matched.get("avatarURL") if matched else None
        if not avatar_url and kind == "platform":
            source = (subject.get("source") or "").lower()
            source_id = subject["actor_id"].split(":")[-1].lower()
            handle = subject["name"].lstrip("@").lower()
            avatar_url = (x_avatars.get(source_id) if source == "x" else None) or \
                handle_avatars.get((source, source_id)) or handle_avatars.get((source, handle))
        days = max(0, subject.get("independent_decision_days") or 0)
        rows.append({
            "actorKind": kind,
            "actorId": actor_id,
            "displayName": matched["name"] if matched else subject["name"],
            "platform": subject.get("source") if kind == "platform" else None,
            "avatarURL": avatar_url,
            "status": "scored" if score is not None else
            "unaudited_backtest" if win_rate is not None or follow_return is not None else
            "no_observable_trade",
            "score": score,
            "winRate": win_rate,
            "winRateMethod": subject.get("win_rate_method"),
            "winRateObservations": subject.get("win_rate_observations") or subject.get("settled_decisions"),
            "winRateWins": subject.get("win_rate_wins"),
            "winRateLosses": subject.get("win_rate_losses"),
            "followReturn": follow_return,
            "followReturnMethod": "long_only_30d_portfolio" if replay_return is not None else
            "directional_30d_proxy" if proxy_return is not None else None,
            "observedCalendarDays": max(summary["observed_calendar_days"], days),
            "independentDecisionDays": days,
            "pricedCoverage": finite(subject.get("price_coverage")) or 0,
            "rank": None,
        })

    counts = Counter((row["actorKind"], row["actorId"]) for row in rows)
    duplicates = [key for key, count in counts.items() if count != 1]
    if duplicates:
        raise ValueError(f"Research identity mapping is ambiguous: {duplicates}")
    rows.sort(key=lambda row: (row["score"] is None, -(row["score"] or 0), row["actorKind"], row["actorId"]))
    previous_score = None
    previous_rank = 0
    for index, row in enumerate(rows, 1):
        if row["score"] is not None:
            row["rank"] = previous_rank if row["score"] == previous_score else index
            previous_score, previous_rank = row["score"], row["rank"]
    as_of = datetime.fromisoformat(summary["window_end"]).replace(tzinfo=timezone.utc).isoformat().replace("+00:00", "Z")
    snapshot = {
        "status": "research",
        "version": "follow-ability-research-v1",
        "revision": 2,
        "asOf": as_of,
        "scoreUnit": "research_candidate_pp",
        "items": rows,
    }
    OUTPUT.write_text(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Exported {len(rows)} research actors to {OUTPUT}")


if __name__ == "__main__":
    main()

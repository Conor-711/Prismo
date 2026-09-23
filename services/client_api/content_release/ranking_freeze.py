"""Keep published author rankings stable while opinion content continues to refresh."""

from copy import deepcopy


RANKING_FIELDS = (
    "score", "scoreChange", "rank", "platformRank", "platformPercentile",
    "confidence", "effectiveSamples", "settledCalls", "activeDays",
    "coveredTickers", "marketSelectionScore", "industrySelectionScore", "rationale",
)


def score_dates(updates):
    dates = {}
    for row in updates:
        value = row.get("authorScoreAsOf")
        author_id = row.get("authorId")
        if value and author_id:
            dates[author_id] = max(value, dates.get(author_id, value))
    return dates


def snapshot(current_profiles, baseline_profiles, *, current_updates=(), baseline_updates=()):
    baseline = {row["id"]: row for row in baseline_profiles}
    current_dates = score_dates(current_updates)
    baseline_dates = score_dates(baseline_updates)
    result = {}
    restored = 0
    for row in current_profiles:
        old = baseline.get(row["id"])
        source = old if old and old["platform"] == row["platform"] else row
        restored += source is old
        fields = {key: source[key] for key in RANKING_FIELDS if key in source}
        fields["_scoreAsOf"] = (baseline_dates if source is old else current_dates).get(row["id"])
        result[row["id"]] = fields
    return result, restored


def apply(collections, frozen):
    result = dict(collections)
    current_dates = score_dates(collections["smart-account-updates"])
    profiles = []
    for row in collections["smart-accounts"]:
        updated = deepcopy(row)
        fields = frozen.get(row["id"])
        if fields is None:
            fields = {key: row[key] for key in RANKING_FIELDS if key in row}
            fields["_scoreAsOf"] = current_dates.get(row["id"])
            frozen[row["id"]] = fields
        for key in RANKING_FIELDS:
            if key in fields:
                updated[key] = fields[key]
            else:
                updated.pop(key, None)
        profiles.append(updated)
    result["smart-accounts"] = profiles

    by_id = {row["id"]: row for row in profiles}
    updates = {}
    for name in ("smart-account-updates", "smart-account-evidence"):
        rows = []
        for row in collections[name]:
            updated = deepcopy(row)
            author = by_id.get(row["authorId"])
            if author:
                updated["score"] = author["score"]
                if author.get("platformPercentile") is not None:
                    updated["platformPercentile"] = author["platformPercentile"]
                updated["authorScoreAsOf"] = frozen[row["authorId"]].get("_scoreAsOf")
            rows.append(updated)
            updates[updated["id"]] = updated
        result[name] = rows

    signals = []
    for row in collections["portfolio-signals"]:
        updated = deepcopy(row)
        for evidence in updated.get("evidence", []):
            source = updates.get(evidence.get("referenceId")) if evidence.get("source") == "smart_account" else None
            if source is None:
                continue
            percentile = source["platformPercentile"]
            evidence["title"] = f"Smart Account Score {float(source['score']):.1f}"
            evidence["metric"] = f"Top {max(1, round(percentile * 100))}% on {source['platform']}"
            if updated.get("kind") == "account_leads":
                updated["priority"] = "critical" if percentile <= .10 or source.get("lifecycle") in {"reversed", "invalidated"} else "important"
        signals.append(updated)
    result["portfolio-signals"] = signals
    return result

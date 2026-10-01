import csv
from datetime import date
import json
from pathlib import Path

import pytest

from pipeline.jobs.congress_capture.subject_feed_publish import validate_snapshot
from pipeline.domain.investor_ability.directional_win_rate import DirectionalWinRate
from pipeline.jobs.subject_open_returns import directional
from pipeline.jobs.subject_open_returns.publish import merge_research, research_rows


ROOT = Path(__file__).resolve().parents[2]


def test_ios_fallback_contains_published_research():
    bundle = json.loads((ROOT / "ios/BSmart/Resources/subject-activity.json").read_text())
    validate_snapshot(bundle)
    assert len(bundle["subjects"]) >= 217
    assert all(subject.get("research") is not None for subject in bundle["subjects"])
    hern = next(subject for subject in bundle["subjects"] if subject["id"] == "politician:H001082")
    assert hern["research"]["directionalWinRate"] is not None
    assert hern["research"]["meanOpenReturn"] is not None


def test_directional_win_rate_uses_only_wins_and_losses(monkeypatch):
    metric = DirectionalWinRate(as_of="2026-09-30", wins=4, losses=3, flat=1,
                                observations=8, rate=0.5, mean_directional_return=None, excluded={})
    monkeypatch.setattr(directional, "latest_directional_win_rate", lambda *args, **kwargs: metric)
    result = directional.calculate({"politician:ONE": []}, {"SPY": object()},
                                   date(2026, 9, 30))["politician:ONE"]
    assert result["directional_win_rate_pct"] == pytest.approx(4 / 7 * 100)
    assert (result["directional_wins"], result["directional_losses"],
            result["directional_observations"]) == (4, 3, 8)


def test_research_merge_does_not_change_events_or_formal_score():
    subject = {"id": "politician:A000001", "kind": "politician", "name": "Example",
               "avatarURL": None, "metrics": None}
    live = {"schemaVersion": 1, "snapshotAt": "2026-09-30T12:00:00Z",
            "subjects": [subject], "events": []}
    research = {"method": "three_year_open_positions_v1", "asOf": "2026-09-30",
                "sourceSince": "2023-09-30", "latestMarketDate": "2026-09-29",
                "candidatePositions": 3, "pricedPositions": 2,
                "directionalWins": 4, "directionalLosses": 3, "directionalObservations": 7,
                "directionalWinRate": 4 / 7, "openPositionPositiveRate": 0.5,
                "meanOpenReturn": 0.12}
    merged, changed = merge_research(live, {subject["id"]: research})
    assert changed == 1
    assert merged["subjects"][0]["metrics"] is None
    assert merged["events"] == live["events"]
    assert merged["snapshotAt"] == live["snapshotAt"]
    assert merge_research(merged, {subject["id"]: research})[1] == 0
    with pytest.raises(ValueError, match="absent from production"):
        merge_research(live, {"politician:OTHER": research})


def test_research_rejects_invalid_counts():
    data = {"schemaVersion": 1, "subjects": [{"id": "politician:ONE", "kind": "politician",
            "name": "Example", "avatarURL": None, "metrics": None,
            "research": {"method": "three_year_open_positions_v1", "asOf": "2026-09-30",
                         "sourceSince": "2023-09-30", "latestMarketDate": "2026-09-29",
                         "candidatePositions": 1, "pricedPositions": 2,
                         "directionalWins": 1, "directionalLosses": 0,
                         "directionalObservations": 1, "directionalWinRate": 1.0,
                         "meanOpenReturn": 0.2, "openPositionPositiveRate": 1.0}}], "events": []}
    with pytest.raises(ValueError, match="Invalid subject research"):
        validate_snapshot(data)


def test_report_loader_requires_reviewed_roster_and_scores_null(tmp_path):
    (tmp_path / "manifest.json").write_text(json.dumps({"as_of": "2026-09-30",
        "source_since": "2023-09-30", "latest_market_date": "2026-09-29",
        "published_score": None}))
    with (tmp_path / "subjects.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["subject_id", "candidate_positions",
            "priced_positions", "directional_wins", "directional_losses",
            "directional_observations", "directional_win_rate_pct",
            "open_position_positive_rate_pct", "mean_open_return_pct"])
        writer.writeheader()
        writer.writerow({"subject_id": "politician:ONE", "candidate_positions": 1,
            "priced_positions": 1, "directional_wins": 1, "directional_losses": 0,
            "directional_observations": 1, "directional_win_rate_pct": 100,
            "open_position_positive_rate_pct": 100, "mean_open_return_pct": 20})
    with pytest.raises(ValueError, match="below the reviewed"):
        research_rows(tmp_path)
    with pytest.raises(ValueError, match="exactly match verified"):
        research_rows(tmp_path, subject_ids={"politician:ONE"})
    path = tmp_path / "subjects.csv"
    path.write_text(path.read_text().replace("politician:ONE", "celebrity:leopold-aschenbrenner"))
    rows = research_rows(tmp_path, subject_ids={"celebrity:leopold-aschenbrenner"})
    assert rows["celebrity:leopold-aschenbrenner"]["meanOpenReturn"] == .2
    with pytest.raises(ValueError, match="exactly match verified"):
        research_rows(tmp_path, subject_ids={"celebrity:peter-thiel"})

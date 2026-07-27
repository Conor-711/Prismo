from __future__ import annotations

import pytest

from pipeline.domain.smart_voice.v0_impl import aggregate_stats


def settlement(
    candidate_id: str,
    *,
    exit_day: str,
    contribution: float,
    horizon: str = "20D",
) -> dict[str, object]:
    return {
        "candidate_id": candidate_id,
        "status": "settled",
        "actual_hit": 1 if contribution > 0 else 0,
        "expected_hit": 0.5,
        "contribution": contribution,
        "score_weight": 1.0,
        "ticker": "MU",
        "horizon": horizon,
        "created_at": f"{exit_day}T00:00:00",
        "exit_day": exit_day,
    }


def test_recent_evidence_outweighs_old_opposite_evidence() -> None:
    rows = [
        settlement("recent", exit_day="2026-06-30", contribution=0.5),
        settlement("old", exit_day="2025-01-01", contribution=-0.5),
    ]

    lifetime = aggregate_stats(rows, k=0)
    decayed = aggregate_stats(rows, k=0, as_of_day="2026-07-01")

    assert lifetime is not None
    assert lifetime["raw_z"] == pytest.approx(0.0)
    assert decayed is not None
    assert decayed["raw_z"] > 0.5
    assert decayed["n_eff"] < decayed["lifetime_n_eff"]


def test_stale_evidence_loses_significance_and_effective_sample() -> None:
    recent = aggregate_stats(
        [settlement("recent", exit_day="2026-06-30", contribution=0.5)],
        k=30,
        as_of_day="2026-07-01",
    )
    stale = aggregate_stats(
        [settlement("stale", exit_day="2025-06-30", contribution=0.5)],
        k=30,
        as_of_day="2026-07-01",
    )

    assert recent is not None and stale is not None
    assert stale["raw_z"] < recent["raw_z"]
    assert stale["n_eff"] < recent["n_eff"]


def test_long_horizon_call_retains_evidence_longer() -> None:
    short = aggregate_stats(
        [
            settlement(
                "short",
                exit_day="2025-07-01",
                contribution=0.5,
                horizon="1D",
            )
        ],
        k=0,
        as_of_day="2026-07-01",
    )
    long = aggregate_stats(
        [
            settlement(
                "long",
                exit_day="2025-07-01",
                contribution=0.5,
                horizon="180D",
            )
        ],
        k=0,
        as_of_day="2026-07-01",
    )

    assert short is not None and long is not None
    assert long["raw_z"] > short["raw_z"]
    assert long["n_eff"] > short["n_eff"]


def test_as_of_day_excludes_same_day_and_future_settlements() -> None:
    rows = [
        settlement("known", exit_day="2026-06-30", contribution=0.5),
        settlement("same-day", exit_day="2026-07-01", contribution=-0.5),
        settlement("future", exit_day="2026-07-02", contribution=-0.5),
    ]

    result = aggregate_stats(rows, k=0, as_of_day="2026-07-01")

    assert result is not None
    assert result["settled_calls"] == 1
    assert result["raw_z"] > 0

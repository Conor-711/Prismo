from __future__ import annotations

import pytest

from pipeline.domain.smart_voice.integral_scoring import (
    industry_benchmark,
    integrate_directional_path,
    primary_horizon,
)
from pipeline.domain.smart_voice.v0_impl import blend_dual_ability_scores


def test_integral_rewards_early_persistent_outperformance() -> None:
    early = integrate_directional_path([0.08, 0.10, 0.10, 0.10], 0.10)
    late = integrate_directional_path([0.00, 0.00, 0.00, 0.10], 0.10)

    assert early is not None and late is not None
    assert early.terminal_excess == pytest.approx(late.terminal_excess)
    assert early.cumulative_auc > late.cumulative_auc
    assert early.score_core > late.score_core


def test_integral_windows_are_prefix_sums() -> None:
    first = integrate_directional_path([0.02, 0.04, 0.03], 0.10)
    whole = integrate_directional_path(
        [0.02, 0.04, 0.03, -0.01, 0.02, 0.05],
        0.10,
    )

    assert first is not None and whole is not None
    later_area = (
        (0.03 + -0.01) / 2
        + (-0.01 + 0.02) / 2
        + (0.02 + 0.05) / 2
    )
    assert whole.cumulative_auc == pytest.approx(
        first.cumulative_auc + later_area
    )


def test_primary_horizon_uses_explicit_bucket_then_style_default() -> None:
    horizons = {"1D", "5D", "20D", "60D", "90D", "180D"}

    assert primary_horizon("90D", 1, "technical", horizons) == "90D"
    assert primary_horizon("", 0, "technical", horizons) == "5D"
    assert primary_horizon("", 0, "fundamental", horizons) == "90D"


def test_industry_benchmark_never_silently_falls_back_to_spy() -> None:
    available = {"SPY", "SOXX", "XLK", "XLF"}

    assert industry_benchmark("MU", "", "semis", available) == (
        "SOXX",
        "narrative",
    )
    assert industry_benchmark("UNKNOWN", "Technology", "", available) == (
        "XLK",
        "sector",
    )
    assert industry_benchmark("UNKNOWN", "", "", available) == (
        None,
        "unmapped",
    )


def test_industry_ability_gains_weight_with_evidence() -> None:
    market = {"raw_z": 1.0, "n_eff": 30.0, "settled_calls": 40}
    sparse_industry = {"raw_z": -1.0, "n_eff": 2.0, "settled_calls": 3}
    mature_industry = {"raw_z": -1.0, "n_eff": 30.0, "settled_calls": 35}

    sparse = blend_dual_ability_scores(market, sparse_industry, 120, 80)
    mature = blend_dual_ability_scores(market, mature_industry, 120, 80)

    assert sparse["industryBlendWeight"] < mature["industryBlendWeight"]
    assert mature["industryBlendWeight"] < 0.5
    assert sparse["compositePlatformSv"] > mature["compositePlatformSv"]

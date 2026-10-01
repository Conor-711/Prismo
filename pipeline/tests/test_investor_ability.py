from dataclasses import replace

import pytest

from pipeline.domain.investor_ability import FollowPerformance, score_follow_performance
from pipeline.domain.investor_ability.scoring import research_score_value


def sample(**changes: object) -> FollowPerformance:
    base = FollowPerformance(
        actor_id="x:author", actor_kind="platform", as_of="2026-09-29",
        observed_calendar_days=730, independent_decision_days=40,
        settled_decisions=40, executable_decisions=42, priced_decisions=40,
        annualized_net_return=0.20, annualized_matched_benchmark_return=0.10,
        annualized_volatility=0.30, max_drawdown=-0.10, source_verified=True,
        point_in_time_verified=True, execution_costs_included=True,
        benchmark_aligned=True,
    )
    return replace(base, **changes)


def test_score_has_natural_zero_and_does_not_depend_on_cohort() -> None:
    neutral = sample(annualized_net_return=0, annualized_matched_benchmark_return=0,
                     annualized_volatility=0, max_drawdown=0)
    assert score_follow_performance(neutral).value == 0
    assert score_follow_performance(sample()).value == score_follow_performance(
        sample(actor_id="politician:7", actor_kind="politician")
    ).value
    assert score_follow_performance(sample()).value == pytest.approx(
        100 * ((40 / 60) * (40 / 42) * 0.20 - 0.0175)
    )


def test_net_return_raises_score_while_underperformance_and_risk_lower_it() -> None:
    baseline = score_follow_performance(sample()).value
    assert baseline is not None
    assert score_follow_performance(sample(annualized_net_return=0.30)).value > baseline
    assert score_follow_performance(sample(annualized_net_return=0.15)).value < baseline
    assert score_follow_performance(sample(annualized_matched_benchmark_return=0.25)).value < baseline
    assert score_follow_performance(sample(max_drawdown=-0.30)).value < baseline
    assert score_follow_performance(sample(annualized_volatility=0.60)).value < baseline


def test_outperforming_a_falling_benchmark_does_not_reward_a_loss() -> None:
    result = score_follow_performance(sample(
        annualized_net_return=-0.05, annualized_matched_benchmark_return=-0.40,
        annualized_volatility=0, max_drawdown=0,
    ))
    assert result.value is not None and result.value < 0


def test_score_has_no_ceiling_or_lower_clamp() -> None:
    high = score_follow_performance(sample(
        annualized_net_return=5.0, annualized_matched_benchmark_return=1.0,
    ))
    low = score_follow_performance(sample(
        annualized_net_return=-0.90, annualized_matched_benchmark_return=0.10,
    ))
    assert high.value is not None and high.value > 100
    assert low.value is not None and low.value < 0


def test_research_formula_does_not_override_audit_gate() -> None:
    unverified = sample(source_verified=False)
    assert research_score_value(unverified) == score_follow_performance(sample()).value
    assert score_follow_performance(unverified).value is None


def test_small_sample_and_missing_prices_do_not_receive_a_number() -> None:
    assert score_follow_performance(sample(independent_decision_days=4)).value is None
    assert score_follow_performance(sample(observed_calendar_days=100)).status == "insufficient_history"
    assert score_follow_performance(sample(observed_calendar_days=364)).value is None
    assert score_follow_performance(sample(observed_calendar_days=365)).value is not None
    assert score_follow_performance(sample(settled_decisions=7)).status == "insufficient_history"
    assert score_follow_performance(sample(priced_decisions=30, settled_decisions=30)).status == "incomplete_prices"
    assert score_follow_performance(sample(source_verified=False)).status == "unverified_source"
    assert score_follow_performance(sample(point_in_time_verified=False)).status == "unaudited_backtest"
    assert score_follow_performance(sample(execution_costs_included=False)).value is None
    assert score_follow_performance(sample(benchmark_aligned=False)).value is None


@pytest.mark.parametrize("kind", ["politician", "celebrity", "institution"])
def test_disclosure_subjects_have_no_volume_or_history_threshold(kind: str) -> None:
    sparse = sample(
        actor_kind=kind,
        observed_calendar_days=90,
        independent_decision_days=1,
        settled_decisions=1,
        executable_decisions=10,
        priced_decisions=1,
    )
    result = score_follow_performance(sparse)
    assert result.status == "scored"
    assert result.value == research_score_value(sparse)
    assert result.priced_coverage == 0.1


def test_no_closed_trade_is_undefined_not_zero_score() -> None:
    empty = sample(
        actor_kind="politician",
        independent_decision_days=0,
        settled_decisions=0,
        executable_decisions=0,
        priced_decisions=0,
    )
    result = score_follow_performance(empty)
    assert result.status == "no_observable_trade"
    assert result.value is None


def test_spam_does_not_increase_evidence_weight_without_independent_days() -> None:
    original = score_follow_performance(sample())
    more_same_day_posts = score_follow_performance(sample(executable_decisions=84, priced_decisions=80,
                                                          settled_decisions=80))
    assert original.evidence_weight == more_same_day_posts.evidence_weight
    assert original.value == more_same_day_posts.value


@pytest.mark.parametrize("change", [
    {"annualized_net_return": float("nan")},
    {"annualized_volatility": -0.01},
    {"max_drawdown": 0.2},
    {"priced_decisions": 43},
    {"settled_decisions": 41},
    {"actor_kind": "unknown"},
    {"as_of": "not-a-date"},
    {"independent_decision_days": 731},
    {"execution_costs_included": "false"},
])
def test_invalid_inputs_fail_closed(change: dict[str, object]) -> None:
    with pytest.raises(ValueError):
        score_follow_performance(sample(**change))

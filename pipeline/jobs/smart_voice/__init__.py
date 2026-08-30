"""Smart Account job exports without importing unrelated platform runtimes."""
from __future__ import annotations

from importlib import import_module
from typing import Any


_EXPORT_MODULES = {
    "backfill_price_history": "workflows",
    "build_sv_indicator_backtest": "workflows",
    "build_sv_segment_backtest": "workflows",
    "build_x_sv_portfolio_backtest": "workflows",
    "build_x_rank_event_research": "workflows",
    "export_sv_indicator_backtest_reports": "workflows",
    "build_ticker_sv_signals": "workflows",
    "build_overall_signals": "workflows",
    "match_x_topics": "workflows",
    "rollup_kol_newcomers": "workflows",
    "rollup_kol_sentiment": "workflows",
    "rollup_kol_volume": "workflows",
    "rollup_retail_newcomers": "workflows",
    "rollup_retail_sentiment": "workflows",
    "rollup_retail_volume": "workflows",
    "run_sv_v0": "workflows",
    "score_x_sentiment": "workflows",
    "run_hyperliquid_smart_money": "hyperliquid",
    "run_hyperliquid_live": "hyperliquid_live",
    "run_hyperdash_live": "hyperdash_live",
    "export_smart_account_client_read_model": "client_read_model",
}

__all__ = list(_EXPORT_MODULES)


def __getattr__(name: str) -> Any:
    module_name = _EXPORT_MODULES.get(name)
    if module_name is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    value = getattr(import_module(f".{module_name}", __name__), name)
    globals()[name] = value
    return value

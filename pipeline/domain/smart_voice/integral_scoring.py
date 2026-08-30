"""Pure helpers for the dual-benchmark integral Smart Account scorer."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable


INTEGRAL_SCORING_VERSION = "v2.0-dual-benchmark-auc"
INTEGRAL_WEIGHT = 0.70
TERMINAL_WEIGHT = 0.30


SECTOR_BENCHMARKS = {
    "communication services": "XLC",
    "consumer discretionary": "XLY",
    "consumer staples": "XLP",
    "energy": "XLE",
    "financials": "XLF",
    "health care": "XLV",
    "healthcare": "XLV",
    "industrials": "XLI",
    "materials": "XLB",
    "real estate": "XLRE",
    "technology": "XLK",
    "utilities": "XLU",
}

NARRATIVE_BENCHMARKS = {
    "ai_infra": "XLK",
    "consumer": "XLY",
    "crypto": "BLOK",
    "ev": "XLY",
    "fintech": "XLF",
    "media": "XLC",
    "semis": "SOXX",
    "software": "IGV",
}

# New or cross-sector names often lack a populated sector in ticker_meta. These
# explicit assignments keep the production mapping auditable rather than
# silently treating SPY as an industry benchmark.
TICKER_BENCHMARK_OVERRIDES = {
    "AAOI": "SOXX",
    "AEHR": "SOXX",
    "AMPG": "SOXX",
    "APLD": "XLK",
    "APP": "IGV",
    "ASTS": "XLI",
    "BE": "XLU",
    "BITF": "BLOK",
    "BMNR": "BLOK",
    "CIFR": "BLOK",
    "CLSK": "BLOK",
    "CRCL": "XLF",
    "CRDO": "SOXX",
    "CRWV": "XLK",
    "DGXX": "BLOK",
    "EOSE": "XLU",
    "GLXY": "BLOK",
    "HIMS": "XLV",
    "HUT": "BLOK",
    "IREN": "BLOK",
    "IONQ": "XLK",
    "IOVA": "XBI",
    "LITE": "SOXX",
    "MARA": "BLOK",
    "MSTR": "BLOK",
    "NBIS": "XLK",
    "ONDS": "XLI",
    "OPEN": "XLRE",
    "OSCR": "XLV",
    "OUST": "XLI",
    "RDDT": "XLC",
    "RDW": "XLI",
    "RGTI": "XLK",
    "RIOT": "BLOK",
    "RKLB": "XLI",
    "SBET": "BLOK",
    "SLNH": "BLOK",
    "SNDK": "SOXX",
    "TEM": "XLV",
    "TMDX": "XLV",
    "USO": "XLE",
    "WULF": "BLOK",
    "ZETA": "IGV",
}

DEFAULT_HORIZON_BY_STYLE = {
    "event_driven": "20D",
    "flow_momentum": "5D",
    "fundamental": "90D",
    "macro": "60D",
    "mixed": "20D",
    "technical": "5D",
    "unknown": "20D",
}


@dataclass(frozen=True)
class IntegralPathResult:
    steps: int
    cumulative_auc: float
    mean_auc: float
    integral_component: float
    terminal_excess: float
    terminal_component: float
    score_core: float
    positive_day_share: float
    positive_area: float
    negative_area: float
    adverse_area_share: float
    max_favorable_excess: float
    peak_step: int
    retracement: float


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def primary_horizon(
    horizon_bucket: object,
    horizon_explicit: object,
    analysis_type: object,
    valid_horizons: Iterable[str],
) -> str:
    """Return the single horizon that contributes to the author's evidence."""
    valid = {str(value).upper() for value in valid_horizons}
    bucket = str(horizon_bucket or "").upper()
    if bucket in valid:
        return bucket
    style = str(analysis_type or "unknown").lower()
    fallback = DEFAULT_HORIZON_BY_STYLE.get(style, DEFAULT_HORIZON_BY_STYLE["unknown"])
    if fallback in valid:
        return fallback
    return sorted(valid)[0]


def industry_benchmark(
    ticker: object,
    sector: object,
    narrative: object,
    available_tickers: Iterable[str],
) -> tuple[str | None, str]:
    """Resolve an auditable industry ETF without falling back to SPY."""
    symbol = str(ticker or "").upper()
    available = {str(value).upper() for value in available_tickers}
    if not symbol or symbol in {
        "ARKK", "BLOK", "GLD", "IBIT", "IGV", "IWM", "QQQ", "SLV",
        "SMH", "SOXL", "SOXX", "SPY", "TLT", "TQQQ", "XBI", "XLB",
        "XLC", "XLE", "XLF", "XLI", "XLK", "XLP", "XLRE", "XLU",
        "XLV", "XLY",
    }:
        return None, "asset_is_benchmark_or_etf"
    override = TICKER_BENCHMARK_OVERRIDES.get(symbol)
    if override and override in available:
        return override, "ticker_override"
    narrative_key = str(narrative or "").lower()
    narrative_etf = NARRATIVE_BENCHMARKS.get(narrative_key)
    if narrative_etf and narrative_etf in available:
        return narrative_etf, "narrative"
    sector_key = " ".join(str(sector or "").strip().lower().split())
    sector_etf = SECTOR_BENCHMARKS.get(sector_key)
    if sector_etf and sector_etf in available:
        return sector_etf, "sector"
    return None, "unmapped"


def integrate_directional_path(
    directional_excess_path: Iterable[float],
    normalizer: float,
) -> IntegralPathResult | None:
    """Integrate the cumulative directional excess-return path.

    The input contains cumulative excess returns observed at each tradable
    session close after entry. The implicit value at the entry open is zero.
    """
    values = [float(value) for value in directional_excess_path]
    if not values:
        return None
    previous = 0.0
    cumulative_auc = 0.0
    positive_area = 0.0
    negative_area = 0.0
    for value in values:
        area = (previous + value) / 2.0
        cumulative_auc += area
        if area >= 0:
            positive_area += area
        else:
            negative_area += abs(area)
        previous = value
    steps = len(values)
    mean_auc = cumulative_auc / steps
    scale = max(1e-9, float(normalizer))
    integral_component = clamp(mean_auc / scale, -1.0, 1.0)
    terminal_excess = values[-1]
    terminal_component = clamp(terminal_excess / scale, -1.0, 1.0)
    score_core = (
        INTEGRAL_WEIGHT * integral_component
        + TERMINAL_WEIGHT * terminal_component
    )
    max_favorable = max(values)
    peak_step = values.index(max_favorable) + 1
    total_area = positive_area + negative_area
    return IntegralPathResult(
        steps=steps,
        cumulative_auc=cumulative_auc,
        mean_auc=mean_auc,
        integral_component=integral_component,
        terminal_excess=terminal_excess,
        terminal_component=terminal_component,
        score_core=score_core,
        positive_day_share=sum(value > 0 for value in values) / steps,
        positive_area=positive_area,
        negative_area=negative_area,
        adverse_area_share=negative_area / total_area if total_area > 0 else 0.0,
        max_favorable_excess=max_favorable,
        peak_step=peak_step,
        retracement=max(0.0, max_favorable - terminal_excess),
    )

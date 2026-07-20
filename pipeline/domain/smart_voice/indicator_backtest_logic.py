"""Shared formulas for Smart Voice indicator construction and audit exports."""
from __future__ import annotations

import math
from typing import Any, Mapping

CONFIDENCE_WEIGHT = {"high": 1.0, "medium": 0.82, "low": 0.62, "observing": 0.48}

def call_signal_weight(call: Mapping[str, Any]) -> float:
    """Match the discovery-page platform-SV call weighting formula."""
    platform_sv = max(40.0, min(180.0, float(call["platform_sv"] or 100.0)))
    sv_weight = max(0.35, platform_sv / 100.0)
    call_weight = max(0.2, min(1.2, float(call["call_weight"] or 0.6)))
    confidence = CONFIDENCE_WEIGHT.get(str(call["confidence"]), 0.48)
    sample = min(1.18, max(0.72, math.log10(max(10.0, float(call["n_eff"] or 10.0))) / 2.0))
    return sv_weight * call_weight * confidence * sample

"""Point-in-time sub-SV scores for vertical signal backtests."""
from __future__ import annotations

import collections
import math
import sqlite3
from dataclasses import dataclass, field
from typing import Iterable

from .v0_impl import HORIZONS, TICKER_NARRATIVE, infer_analysis_type

SEGMENT_TYPES = ("horizon", "narrative", "investor_type")
SEGMENT_SHRINKAGE = {"horizon": 25.0, "narrative": 20.0, "investor_type": 20.0}


@dataclass
class _Accumulator:
    contribution: float = 0.0
    variance: float = 0.0
    weight_sum: float = 0.0
    weight_sq_sum: float = 0.0
    candidate_ids: set[str] = field(default_factory=set)

    def add(self, row: sqlite3.Row) -> None:
        weight = max(0.0, float(row["score_weight"] or 0.0))
        if weight <= 0:
            return
        expected = min(1.0, max(0.0, float(row["expected_hit"] or 0.5)))
        self.contribution += float(row["contribution"] or 0.0)
        self.variance += weight * weight * expected * (1.0 - expected)
        self.weight_sum += weight
        self.weight_sq_sum += weight * weight
        self.candidate_ids.add(str(row["candidate_id"]))

    def snapshot(self, shrinkage: float) -> tuple[float, float, int]:
        z = self.contribution / math.sqrt(self.variance) if self.variance > 1e-9 else 0.0
        n_eff = self.weight_sum * self.weight_sum / self.weight_sq_sum if self.weight_sq_sum else 0.0
        raw_z = z * n_eff / (n_eff + shrinkage)
        return raw_z, n_eff, len(self.candidate_ids)


def _row_segments(row: sqlite3.Row, segment_types: set[str]) -> list[tuple[str, str]]:
    output: list[tuple[str, str]] = []
    if "horizon" in segment_types:
        horizon = str(row["horizon"] or "")
        if horizon in HORIZONS:
            output.append(("horizon", horizon))
    if "narrative" in segment_types:
        narrative = TICKER_NARRATIVE.get(str(row["ticker"] or "").upper())
        if narrative:
            output.append(("narrative", narrative))
    if "investor_type" in segment_types:
        investor_type = infer_analysis_type(
            str(row["text"] or ""),
            str(row["investor_style"] or "unknown"),
        )
        if investor_type != "unknown":
            output.append(("investor_type", investor_type))
    return output


def rebuild_segment_scores_asof(
    con: sqlite3.Connection,
    *,
    asof_days: Iterable[str],
    sources: tuple[str, ...],
    segment_types: tuple[str, ...],
    min_n_eff: float,
    min_settled_calls: int,
) -> int:
    """Rebuild historical sub-SV ranks using only evidence settled before each day."""
    wanted_segments = set(segment_types) & set(SEGMENT_TYPES)
    if not wanted_segments or not sources:
        con.execute("DELETE FROM sv_segment_score_asof")
        con.commit()
        return 0
    source_slots = ",".join("?" for _ in sources)
    evidence = con.execute(
        f"""SELECT s.candidate_id,s.horizon,upper(s.ticker) AS ticker,s.investor_id,
                   s.exit_day,s.score_weight,s.expected_hit,s.contribution,
                   c.source,c.investor_style,cc.text
              FROM sv_call_settlement s
              JOIN sv_call c ON c.candidate_id=s.candidate_id
              JOIN sv_call_candidate cc ON cc.candidate_id=s.candidate_id
             WHERE s.status='settled'
               AND s.exit_day IS NOT NULL
               AND c.is_actionable_call=1
               AND c.direction IN ('bull','bear')
               AND c.source IN ({source_slots})
             ORDER BY s.exit_day,s.candidate_id,s.horizon""",
        sources,
    ).fetchall()
    days = sorted({str(day) for day in asof_days if day})
    con.execute("DELETE FROM sv_segment_score_asof")
    accumulators: dict[tuple[str, str, str, str], _Accumulator] = {}
    cursor = 0
    written = 0
    for day in days:
        while cursor < len(evidence) and str(evidence[cursor]["exit_day"]) < day:
            row = evidence[cursor]
            investor_id = str(row["investor_id"] or "")
            source = str(row["source"] or "")
            if investor_id and source:
                for segment_type, segment_key in _row_segments(row, wanted_segments):
                    key = (source, segment_type, segment_key, investor_id)
                    accumulators.setdefault(key, _Accumulator()).add(row)
            cursor += 1

        qualified: dict[tuple[str, str, str], list[tuple[str, float, float, int]]] = collections.defaultdict(list)
        for (source, segment_type, segment_key, investor_id), accumulator in accumulators.items():
            raw_z, n_eff, settled_calls = accumulator.snapshot(SEGMENT_SHRINKAGE[segment_type])
            if n_eff < min_n_eff or settled_calls < min_settled_calls:
                continue
            qualified[(source, segment_type, segment_key)].append(
                (investor_id, raw_z, n_eff, settled_calls)
            )

        output: list[tuple[object, ...]] = []
        for (source, segment_type, segment_key), rows in qualified.items():
            rows.sort(key=lambda item: (-item[1], -item[2], -item[3], item[0]))
            population = len(rows)
            for index, (investor_id, raw_z, n_eff, settled_calls) in enumerate(rows, start=1):
                percentile = (index - 1) / max(1, population - 1) * 100.0
                segment_sv = max(40.0, min(180.0, 100.0 + 10.0 * raw_z))
                output.append(
                    (
                        day,
                        segment_type,
                        segment_key,
                        investor_id,
                        source,
                        segment_sv,
                        raw_z,
                        index,
                        population,
                        percentile,
                        n_eff,
                        settled_calls,
                        1,
                    )
                )
        con.executemany(
            """INSERT INTO sv_segment_score_asof
               (asof_day,segment_type,segment_key,investor_id,source,segment_sv,raw_z,
                rank_no,population,percentile,n_eff,settled_calls,qualified)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            output,
        )
        written += len(output)
        if written and written % 100_000 < len(output):
            con.commit()
    con.commit()
    return written

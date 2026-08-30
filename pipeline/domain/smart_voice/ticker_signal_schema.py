"""SQLite schema for ticker-level Smart Account signals and backtests."""
from __future__ import annotations

import sqlite3


def _ensure_column(con: sqlite3.Connection, table: str, definition: str) -> None:
    column = definition.split()[0]
    columns = {str(row[1]) for row in con.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        con.execute(f"ALTER TABLE {table} ADD COLUMN {definition}")


def ensure_ticker_signal_tables(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS sv_investor_score_asof (
          asof_day TEXT NOT NULL,
          investor_id TEXT NOT NULL,
          source TEXT NOT NULL,
          sv REAL NOT NULL,
          raw_z REAL NOT NULL,
          rank_no INTEGER NOT NULL,
          percentile REAL NOT NULL,
          confidence TEXT NOT NULL,
          n_eff REAL NOT NULL,
          settled_calls INTEGER NOT NULL,
          PRIMARY KEY (asof_day, investor_id)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_asof_investor ON sv_investor_score_asof(investor_id, asof_day);
        CREATE INDEX IF NOT EXISTS idx_sv_asof_percentile ON sv_investor_score_asof(asof_day, percentile);

        CREATE TABLE IF NOT EXISTS sv_ticker_signal_daily (
          ticker TEXT NOT NULL,
          day TEXT NOT NULL,
          horizon TEXT NOT NULL,
          cohort TEXT NOT NULL,
          percentile_cut INTEGER NOT NULL,
          n_authors INTEGER NOT NULL,
          n_bull INTEGER NOT NULL,
          n_bear INTEGER NOT NULL,
          bull_share REAL NOT NULL,
          bear_share REAL NOT NULL,
          weighted_net REAL NOT NULL,
          consensus_strength REAL NOT NULL,
          effective_voices REAL NOT NULL,
          dominant_direction TEXT NOT NULL,
          cluster_flag INTEGER NOT NULL,
          avg_sv REAL NOT NULL,
          target_count INTEGER NOT NULL,
          target_median REAL,
          explicit_horizon_count INTEGER NOT NULL,
          source_count INTEGER NOT NULL,
          call_types_json TEXT NOT NULL,
          sources_json TEXT NOT NULL,
          candidate_ids_json TEXT NOT NULL,
          investor_ids_json TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (ticker, day, horizon, cohort)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_ticker_signal_daily_lookup
          ON sv_ticker_signal_daily(ticker, horizon, cohort, day);

        CREATE TABLE IF NOT EXISTS sv_ticker_signal_event (
          event_id TEXT PRIMARY KEY,
          ticker TEXT NOT NULL,
          cohort TEXT NOT NULL,
          percentile_cut INTEGER NOT NULL,
          horizon TEXT NOT NULL,
          direction TEXT NOT NULL,
          start_day TEXT NOT NULL,
          end_day TEXT NOT NULL,
          signal_day TEXT NOT NULL,
          n_authors INTEGER NOT NULL,
          n_bull INTEGER NOT NULL,
          n_bear INTEGER NOT NULL,
          consensus_strength REAL NOT NULL,
          effective_voices REAL NOT NULL,
          weighted_net REAL NOT NULL,
          avg_sv REAL NOT NULL,
          source_count INTEGER NOT NULL,
          target_median REAL,
          candidate_ids_json TEXT NOT NULL,
          investor_ids_json TEXT NOT NULL,
          entry_day TEXT,
          entry_price REAL,
          created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sv_ticker_signal_event_lookup
          ON sv_ticker_signal_event(ticker, horizon, cohort, signal_day);

        CREATE TABLE IF NOT EXISTS sv_ticker_signal_outcome (
          event_id TEXT NOT NULL,
          outcome_horizon TEXT NOT NULL,
          exit_day TEXT,
          exit_price REAL,
          return_pct REAL,
          benchmark_return_pct REAL,
          excess_return_pct REAL,
          directional_return_pct REAL,
          directional_excess_pct REAL,
          actual_hit INTEGER,
          max_favorable_excess REAL,
          max_adverse_excess REAL,
          time_to_peak_days INTEGER,
          status TEXT NOT NULL,
          PRIMARY KEY (event_id, outcome_horizon)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_ticker_signal_outcome_status
          ON sv_ticker_signal_outcome(outcome_horizon, status);

        CREATE TABLE IF NOT EXISTS sv_ticker_signal_stat (
          ticker TEXT NOT NULL,
          cohort TEXT NOT NULL,
          signal_horizon TEXT NOT NULL,
          outcome_horizon TEXT NOT NULL,
          direction TEXT NOT NULL,
          n_events INTEGER NOT NULL,
          hit_rate REAL,
          avg_directional_return_pct REAL,
          median_directional_return_pct REAL,
          avg_directional_excess_pct REAL,
          median_directional_excess_pct REAL,
          avg_max_favorable_excess REAL,
          avg_max_adverse_excess REAL,
          avg_time_to_peak_days REAL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (ticker, cohort, signal_horizon, outcome_horizon, direction)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_ticker_signal_stat_lookup
          ON sv_ticker_signal_stat(ticker, signal_horizon, cohort);
        """
    )
    _ensure_column(con, "sv_investor_score_asof", "platform_sv REAL NOT NULL DEFAULT 100")
    _ensure_column(con, "sv_investor_score_asof", "platform_rank_no INTEGER")
    _ensure_column(con, "sv_investor_score_asof", "platform_population INTEGER NOT NULL DEFAULT 0")
    _ensure_column(con, "sv_investor_score_asof", "platform_percentile REAL")
    _ensure_column(con, "sv_investor_score_asof", "platform_qualified INTEGER NOT NULL DEFAULT 0")

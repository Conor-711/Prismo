"""SQLite schema for leakage-free vertical segment-Score backtests."""
from __future__ import annotations

import sqlite3


def ensure_segment_backtest_tables(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS sv_segment_score_asof (
          asof_day TEXT NOT NULL,
          segment_type TEXT NOT NULL,
          segment_key TEXT NOT NULL,
          investor_id TEXT NOT NULL,
          source TEXT NOT NULL,
          segment_sv REAL NOT NULL,
          raw_z REAL NOT NULL,
          rank_no INTEGER NOT NULL,
          population INTEGER NOT NULL,
          percentile REAL NOT NULL,
          n_eff REAL NOT NULL,
          settled_calls INTEGER NOT NULL,
          qualified INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY(asof_day, segment_type, segment_key, investor_id, source)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_segment_asof_lookup
          ON sv_segment_score_asof(asof_day, source, segment_type, segment_key, rank_no);
        CREATE INDEX IF NOT EXISTS idx_sv_segment_asof_investor
          ON sv_segment_score_asof(investor_id, source, asof_day);

        CREATE TABLE IF NOT EXISTS sv_segment_signal_daily (
          ticker TEXT NOT NULL,
          day TEXT NOT NULL,
          source_scope TEXT NOT NULL,
          segment_type TEXT NOT NULL,
          segment_key TEXT NOT NULL,
          window_days INTEGER NOT NULL,
          rank_band TEXT NOT NULL,
          direction TEXT NOT NULL,
          signal_value REAL NOT NULL,
          weighted_net REAL NOT NULL,
          bull_authors INTEGER NOT NULL,
          bear_authors INTEGER NOT NULL,
          total_authors INTEGER NOT NULL,
          consensus REAL NOT NULL,
          effective_voices REAL NOT NULL,
          authors_json TEXT NOT NULL DEFAULT '[]',
          updated_at TEXT NOT NULL,
          PRIMARY KEY(ticker, day, source_scope, segment_type, segment_key, window_days, rank_band)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_segment_signal_day
          ON sv_segment_signal_daily(source_scope, segment_type, segment_key, day);

        CREATE TABLE IF NOT EXISTS sv_segment_event (
          event_id TEXT PRIMARY KEY,
          ticker TEXT NOT NULL,
          source_scope TEXT NOT NULL,
          segment_type TEXT NOT NULL,
          segment_key TEXT NOT NULL,
          window_days INTEGER NOT NULL,
          rank_band TEXT NOT NULL,
          direction TEXT NOT NULL,
          start_day TEXT NOT NULL,
          end_day TEXT NOT NULL,
          signal_day TEXT NOT NULL,
          signal_value REAL NOT NULL,
          weighted_net REAL NOT NULL,
          bull_authors INTEGER NOT NULL,
          bear_authors INTEGER NOT NULL,
          total_authors INTEGER NOT NULL,
          consensus REAL NOT NULL,
          effective_voices REAL NOT NULL,
          authors_json TEXT NOT NULL DEFAULT '[]',
          entry_day TEXT,
          entry_price REAL,
          created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sv_segment_event_group
          ON sv_segment_event(source_scope, segment_type, segment_key, window_days, rank_band, signal_day);

        CREATE TABLE IF NOT EXISTS sv_segment_outcome (
          event_id TEXT NOT NULL,
          outcome_horizon TEXT NOT NULL,
          exit_day TEXT,
          exit_price REAL,
          directional_return_pct REAL,
          directional_excess_pct REAL,
          raw_hit INTEGER,
          excess_hit INTEGER,
          max_favorable_excess REAL,
          max_adverse_excess REAL,
          status TEXT NOT NULL,
          PRIMARY KEY(event_id, outcome_horizon)
        );

        CREATE TABLE IF NOT EXISTS sv_segment_stat (
          source_scope TEXT NOT NULL,
          segment_type TEXT NOT NULL,
          segment_key TEXT NOT NULL,
          window_days INTEGER NOT NULL,
          rank_band TEXT NOT NULL,
          outcome_horizon TEXT NOT NULL,
          direction TEXT NOT NULL,
          n_events INTEGER NOT NULL,
          raw_hit_rate REAL,
          excess_hit_rate REAL,
          excess_hit_ci_low REAL,
          excess_hit_ci_high REAL,
          avg_directional_return_pct REAL,
          median_directional_return_pct REAL,
          avg_win_pct REAL,
          avg_loss_pct REAL,
          payoff_ratio REAL,
          profit_factor REAL,
          avg_directional_excess_pct REAL,
          median_directional_excess_pct REAL,
          excess_payoff_ratio REAL,
          excess_profit_factor REAL,
          avg_max_favorable_excess REAL,
          avg_max_adverse_excess REAL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY(source_scope, segment_type, segment_key, window_days, rank_band, outcome_horizon, direction)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_segment_stat_lookup
          ON sv_segment_stat(source_scope, segment_type, segment_key, outcome_horizon);
        """
    )
    con.commit()


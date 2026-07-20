"""SQLite schema for point-in-time Smart Voice indicator backtests."""
from __future__ import annotations

import sqlite3


def ensure_indicator_backtest_tables(con: sqlite3.Connection) -> None:
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS sv_indicator_signal_daily (
          ticker TEXT NOT NULL,
          day TEXT NOT NULL,
          source_scope TEXT NOT NULL,
          window_days INTEGER NOT NULL,
          indicator TEXT NOT NULL,
          direction TEXT NOT NULL,
          signal_value REAL NOT NULL,
          top_net REAL NOT NULL,
          bottom_net REAL NOT NULL,
          top_author_net INTEGER NOT NULL,
          previous_top_author_net INTEGER NOT NULL,
          author_net_delta INTEGER NOT NULL,
          author_net_shift_pct REAL NOT NULL,
          top_authors INTEGER NOT NULL,
          previous_top_authors INTEGER NOT NULL,
          bottom_authors INTEGER NOT NULL,
          top_calls INTEGER NOT NULL,
          bottom_calls INTEGER NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (ticker, day, source_scope, window_days, indicator)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_indicator_daily_lookup
          ON sv_indicator_signal_daily(source_scope, indicator, window_days, day);

        CREATE TABLE IF NOT EXISTS sv_indicator_event (
          event_id TEXT PRIMARY KEY,
          ticker TEXT NOT NULL,
          source_scope TEXT NOT NULL,
          window_days INTEGER NOT NULL,
          indicator TEXT NOT NULL,
          direction TEXT NOT NULL,
          start_day TEXT NOT NULL,
          end_day TEXT NOT NULL,
          signal_day TEXT NOT NULL,
          signal_value REAL NOT NULL,
          top_net REAL NOT NULL,
          bottom_net REAL NOT NULL,
          top_author_net INTEGER NOT NULL,
          previous_top_author_net INTEGER NOT NULL,
          author_net_delta INTEGER NOT NULL,
          author_net_shift_pct REAL NOT NULL,
          top_authors INTEGER NOT NULL,
          previous_top_authors INTEGER NOT NULL,
          bottom_authors INTEGER NOT NULL,
          entry_day TEXT,
          entry_price REAL,
          created_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_sv_indicator_event_lookup
          ON sv_indicator_event(source_scope, indicator, window_days, signal_day);

        CREATE TABLE IF NOT EXISTS sv_indicator_outcome (
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
          PRIMARY KEY (event_id, outcome_horizon)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_indicator_outcome_status
          ON sv_indicator_outcome(outcome_horizon, status);

        CREATE TABLE IF NOT EXISTS sv_indicator_stat (
          source_scope TEXT NOT NULL,
          indicator TEXT NOT NULL,
          window_days INTEGER NOT NULL,
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
          PRIMARY KEY (source_scope, indicator, window_days, outcome_horizon, direction)
        );
        CREATE INDEX IF NOT EXISTS idx_sv_indicator_stat_lookup
          ON sv_indicator_stat(source_scope, indicator, window_days, outcome_horizon);
        """
    )

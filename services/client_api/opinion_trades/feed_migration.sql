-- Operator review only, after opinion_trades/migration.sql. Not executed by app/task.
ALTER TABLE opinion_public_trader ADD COLUMN feed_visible BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE opinion_verified_fill ADD COLUMN notional_usd VARCHAR(64);
ALTER TABLE opinion_verified_fill ADD COLUMN market_coin VARCHAR(64);
CREATE TABLE opinion_feed_context (
    opinion_id VARCHAR(36) PRIMARY KEY,
    ticker VARCHAR(32) NOT NULL,
    payload JSON NOT NULL,
    registered_at TIMESTAMPTZ NOT NULL,
    visible BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX ix_opinion_feed_order ON opinion_verified_fill (venue, account_id, order_id, traded_at);

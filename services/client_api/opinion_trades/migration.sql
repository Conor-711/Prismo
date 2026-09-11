-- Operator review only. Do not run at application startup.
CREATE TABLE opinion_public_trader (
    account_id VARCHAR(36) PRIMARY KEY,
    public_id VARCHAR(36) NOT NULL UNIQUE,
    nickname VARCHAR(28) NOT NULL,
    avatar_url VARCHAR(2048),
    visible BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE TABLE opinion_verified_fill (
    venue VARCHAR(32) NOT NULL,
    fill_id VARCHAR(128) NOT NULL,
    opinion_id VARCHAR(36) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    order_id VARCHAR(128) NOT NULL,
    ticker VARCHAR(32) NOT NULL,
    side VARCHAR(5) NOT NULL CHECK (side IN ('long', 'short')),
    traded_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (venue, fill_id)
);
CREATE INDEX ix_opinion_verified_fill_opinion_id ON opinion_verified_fill (opinion_id);
CREATE INDEX ix_opinion_verified_fill_account_id ON opinion_verified_fill (account_id);

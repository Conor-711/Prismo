-- Operator-reviewed migration. Never run automatically at API or app startup.
-- PostgreSQL; use an isolated account-state database, not the content database.
BEGIN;
CREATE TABLE trading_account (
    id VARCHAR(36) PRIMARY KEY,
    provider VARCHAR(16) NOT NULL CHECK (provider IN ('apple', 'google')),
    subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (provider, subject)
);
CREATE TABLE trading_auth_challenge (
    id VARCHAR(36) PRIMARY KEY,
    installation_id VARCHAR(36) NOT NULL,
    provider VARCHAR(16) NOT NULL,
    nonce_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ON trading_auth_challenge (installation_id);
CREATE INDEX ON trading_auth_challenge (expires_at);
CREATE TABLE trading_account_session (
    token_hash VARCHAR(64) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES trading_account(id),
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ON trading_account_session (account_id);
CREATE INDEX ON trading_account_session (expires_at);
COMMIT;

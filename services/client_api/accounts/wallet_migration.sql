-- Review/apply separately after accounts/migration.sql. Never executed at startup.
BEGIN;
CREATE TABLE trading_wallet (
    account_id varchar(36) PRIMARY KEY REFERENCES trading_account(id),
    address varchar(42) NOT NULL UNIQUE CHECK (address ~ '^0x[0-9a-f]{40}$'),
    created_at timestamptz NOT NULL
);
CREATE TABLE trading_wallet_challenge (
    id varchar(36) PRIMARY KEY,
    account_id varchar(36) NOT NULL REFERENCES trading_account(id),
    session_hash varchar(64) NOT NULL,
    address varchar(42) NOT NULL CHECK (address ~ '^0x[0-9a-f]{40}$'),
    nonce varchar(64) NOT NULL,
    issued_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL
);
CREATE INDEX ix_trading_wallet_challenge_account_id ON trading_wallet_challenge(account_id);
CREATE INDEX ix_trading_wallet_challenge_session_hash ON trading_wallet_challenge(session_hash);
CREATE INDEX ix_trading_wallet_challenge_expires_at ON trading_wallet_challenge(expires_at);
COMMIT;

-- Operator-reviewed PostgreSQL migration, after accounts/migration.sql.
-- Never applied at startup or to the content database. No tokens are backfilled.
BEGIN;
CREATE TABLE trading_apple_exchange (
    id varchar(36) PRIMARY KEY,
    token_hash varchar(64) NOT NULL,
    subject varchar(255) NOT NULL,
    client_id varchar(255) NOT NULL,
    expires_at timestamptz NOT NULL
);
CREATE INDEX ix_trading_apple_exchange_expires_at ON trading_apple_exchange(expires_at);
CREATE TABLE trading_apple_grant (
    account_id varchar(36) PRIMARY KEY REFERENCES trading_account(id),
    client_id varchar(255) NOT NULL,
    key_id varchar(32) NOT NULL,
    ciphertext bytea NOT NULL CHECK (octet_length(ciphertext) BETWEEN 60 AND 8220),
    updated_at timestamptz NOT NULL
);
COMMIT;

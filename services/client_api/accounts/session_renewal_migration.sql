-- Operator-reviewed PostgreSQL migration, after account and Apple grant migrations.
-- Never apply to the content database or automatically at startup.
BEGIN;
CREATE TABLE trading_session_family (
    id varchar(36) PRIMARY KEY,
    account_id varchar(36) NOT NULL REFERENCES trading_account(id),
    installation_id varchar(36) NOT NULL,
    expires_at timestamptz NOT NULL,
    rotated_at timestamptz NOT NULL,
    revoked_at timestamptz
);
CREATE INDEX ON trading_session_family (account_id);
CREATE INDEX ON trading_session_family (installation_id);
CREATE INDEX ON trading_session_family (expires_at);
CREATE TABLE trading_session_refresh (
    token_hash varchar(64) PRIMARY KEY,
    family_id varchar(36) NOT NULL REFERENCES trading_session_family(id),
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz
);
CREATE INDEX ON trading_session_refresh (family_id);
CREATE INDEX ON trading_session_refresh (expires_at);
ALTER TABLE trading_account_session ADD COLUMN family_id varchar(36) REFERENCES trading_session_family(id);
CREATE INDEX ON trading_account_session (family_id);
-- Unfinished pre-upgrade exchanges are invalidated, never backfilled with guessed installations.
DELETE FROM trading_apple_exchange;
ALTER TABLE trading_apple_exchange ADD COLUMN installation_id varchar(36) NOT NULL;
COMMIT;

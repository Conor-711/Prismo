-- Operator-reviewed PostgreSQL migration after session_renewal_migration.sql.
-- Pause auth ingress and review backup/rollback first. Never apply to content DB.
BEGIN;
CREATE TABLE trading_provider_subject (
    id varchar(64) PRIMARY KEY,
    provider varchar(16) NOT NULL,
    state varchar(16) NOT NULL,
    state_changed_at timestamptz,
    revoked_before timestamptz
);
CREATE TABLE trading_security_event (
    id varchar(64) PRIMARY KEY,
    fingerprint varchar(64) NOT NULL,
    provider varchar(16) NOT NULL,
    kind varchar(200) NOT NULL,
    received_at timestamptz NOT NULL,
    verification_hash varchar(64)
);
CREATE INDEX ON trading_security_event (received_at);
CREATE INDEX ON trading_security_event (verification_hash);
ALTER TABLE trading_session_family ADD COLUMN authenticated_at timestamptz;
ALTER TABLE trading_apple_grant ADD COLUMN authenticated_at timestamptz;
-- Pending exchanges cannot be backfilled with an invented provider issuance time.
DELETE FROM trading_apple_exchange;
ALTER TABLE trading_apple_exchange ADD COLUMN identity_issued_at timestamptz;
COMMIT;

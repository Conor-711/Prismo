-- Operator-reviewed migration after security_event_migration.sql; never run at startup.
-- Pause auth traffic and back up the Client API state database first, not data/dev.db.
ALTER TABLE trading_provider_subject ADD COLUMN deletion_pending BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE trading_account_deletion (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) UNIQUE,
    installation_id VARCHAR(36) NOT NULL,
    ticket_hash VARCHAR(64) NOT NULL,
    status VARCHAR(16) NOT NULL,
    requested_at TIMESTAMP WITH TIME ZONE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    next_attempt_at TIMESTAMP WITH TIME ZONE NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    lease_id VARCHAR(36),
    lease_until TIMESTAMP WITH TIME ZONE,
    grant_client_id VARCHAR(255),
    grant_key_id VARCHAR(32),
    grant_ciphertext BYTEA
);
CREATE INDEX ix_trading_account_deletion_completed_at ON trading_account_deletion (completed_at);
CREATE INDEX ix_trading_account_deletion_next_attempt_at ON trading_account_deletion (next_attempt_at);

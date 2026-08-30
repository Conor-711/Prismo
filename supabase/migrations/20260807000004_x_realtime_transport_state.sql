CREATE TABLE IF NOT EXISTS x_realtime_transport_state (
  transport VARCHAR(24) PRIMARY KEY,
  connected BOOLEAN NOT NULL DEFAULT FALSE,
  connected_at TIMESTAMP NULL,
  last_heartbeat_at TIMESTAMP NULL,
  last_error TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

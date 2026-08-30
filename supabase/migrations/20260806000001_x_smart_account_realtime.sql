CREATE TABLE IF NOT EXISTS x_realtime_subscription (
  author_id VARCHAR(80) PRIMARY KEY,
  handle VARCHAR(64) NOT NULL DEFAULT '',
  display_name VARCHAR(160) NOT NULL DEFAULT '',
  author_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  platform_percentile DOUBLE PRECISION NOT NULL DEFAULT 1,
  author_score_as_of TIMESTAMP NULL,
  pool_version VARCHAR(80) NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  activated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_x_realtime_subscription_handle ON x_realtime_subscription(handle);
CREATE INDEX IF NOT EXISTS idx_x_realtime_subscription_pool ON x_realtime_subscription(pool_version);
CREATE INDEX IF NOT EXISTS idx_x_realtime_subscription_active ON x_realtime_subscription(active);

CREATE TABLE IF NOT EXISTS x_realtime_rule (
  rule_key VARCHAR(120) PRIMARY KEY,
  provider_rule_id VARCHAR(160) UNIQUE,
  tag VARCHAR(255) NOT NULL UNIQUE,
  value VARCHAR(255) NOT NULL,
  handles TEXT,
  pool_version VARCHAR(80) NOT NULL,
  state VARCHAR(24) NOT NULL DEFAULT 'pending',
  interval_seconds DOUBLE PRECISION NOT NULL DEFAULT 60,
  activated_at TIMESTAMP NULL,
  retire_after TIMESTAMP NULL,
  last_reconciled_at TIMESTAMP NULL,
  last_success_at TIMESTAMP NULL,
  last_error TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_x_realtime_rule_state ON x_realtime_rule(state);
CREATE INDEX IF NOT EXISTS idx_x_realtime_rule_pool ON x_realtime_rule(pool_version);
CREATE INDEX IF NOT EXISTS idx_x_realtime_rule_retire ON x_realtime_rule(retire_after);

CREATE TABLE IF NOT EXISTS x_realtime_post (
  post_id VARCHAR(40) PRIMARY KEY,
  author_id VARCHAR(80) NOT NULL,
  author_handle VARCHAR(64) NOT NULL DEFAULT '',
  author_name VARCHAR(160) NOT NULL DEFAULT '',
  author_avatar_url TEXT,
  author_followers_count INTEGER,
  author_verified BOOLEAN,
  source_url TEXT NOT NULL DEFAULT '',
  original_text TEXT NOT NULL DEFAULT '',
  language VARCHAR(16) NOT NULL DEFAULT '',
  post_type VARCHAR(16) NOT NULL DEFAULT 'original',
  is_reply BOOLEAN NOT NULL DEFAULT FALSE,
  is_quote BOOLEAN NOT NULL DEFAULT FALSE,
  is_retweet BOOLEAN NOT NULL DEFAULT FALSE,
  parent_post_id VARCHAR(40),
  conversation_id VARCHAR(40),
  like_count INTEGER NOT NULL DEFAULT 0,
  reply_count INTEGER NOT NULL DEFAULT 0,
  retweet_count INTEGER NOT NULL DEFAULT 0,
  quote_count INTEGER NOT NULL DEFAULT 0,
  view_count INTEGER NOT NULL DEFAULT 0,
  bookmark_count INTEGER NOT NULL DEFAULT 0,
  raw_payload TEXT,
  delivery_source VARCHAR(24) NOT NULL DEFAULT 'webhook',
  delivery_tag VARCHAR(255) NOT NULL DEFAULT '',
  status VARCHAR(24) NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMP,
  last_error TEXT NOT NULL DEFAULT '',
  processing_version VARCHAR(80) NOT NULL DEFAULT '',
  published_at TIMESTAMP NOT NULL,
  ingested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  processed_at TIMESTAMP,
  deleted_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_x_realtime_post_author ON x_realtime_post(author_id);
CREATE INDEX IF NOT EXISTS idx_x_realtime_post_status ON x_realtime_post(status);
CREATE INDEX IF NOT EXISTS idx_x_realtime_post_published ON x_realtime_post(published_at);
CREATE INDEX IF NOT EXISTS idx_x_realtime_post_queue ON x_realtime_post(status, next_attempt_at, published_at);

CREATE TABLE IF NOT EXISTS x_realtime_call (
  call_id VARCHAR(40) PRIMARY KEY,
  idempotency_key VARCHAR(180) NOT NULL UNIQUE,
  post_id VARCHAR(40) NOT NULL REFERENCES x_realtime_post(post_id),
  ticker VARCHAR(16) NOT NULL,
  direction VARCHAR(12) NOT NULL,
  horizon VARCHAR(16) NOT NULL DEFAULT 'unknown',
  target_price DOUBLE PRECISION,
  lifecycle VARCHAR(32) NOT NULL DEFAULT 'open_call',
  invalidation TEXT NOT NULL DEFAULT '',
  evidence_span TEXT NOT NULL DEFAULT '',
  original_text TEXT NOT NULL,
  translated_text_zh TEXT NOT NULL,
  translated_text_en TEXT NOT NULL,
  thesis_zh TEXT NOT NULL DEFAULT '',
  thesis_en TEXT NOT NULL DEFAULT '',
  author_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  author_percentile DOUBLE PRECISION NOT NULL DEFAULT 1,
  author_score_as_of TIMESTAMP,
  extraction_model VARCHAR(120) NOT NULL DEFAULT '',
  translation_model VARCHAR(120) NOT NULL DEFAULT '',
  call_scoring_version VARCHAR(80) NOT NULL,
  call_policy_version VARCHAR(80) NOT NULL,
  ready_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_x_realtime_call_post ON x_realtime_call(post_id);
CREATE INDEX IF NOT EXISTS idx_x_realtime_call_ticker ON x_realtime_call(ticker);
CREATE INDEX IF NOT EXISTS idx_x_realtime_call_ready ON x_realtime_call(ready_at);

CREATE TABLE IF NOT EXISTS x_realtime_event_candidate (
  idempotency_key VARCHAR(180) PRIMARY KEY,
  call_id VARCHAR(40) NOT NULL REFERENCES x_realtime_call(call_id),
  ticker VARCHAR(16) NOT NULL,
  event_type VARCHAR(48) NOT NULL DEFAULT 'smart_account_update',
  status VARCHAR(24) NOT NULL DEFAULT 'ready',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  consumed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_x_realtime_event_status ON x_realtime_event_candidate(status);
CREATE INDEX IF NOT EXISTS idx_x_realtime_event_ticker ON x_realtime_event_candidate(ticker);

CREATE TABLE IF NOT EXISTS x_realtime_run (
  run_id VARCHAR(40) PRIMARY KEY,
  job VARCHAR(40) NOT NULL,
  status VARCHAR(24) NOT NULL,
  received_count INTEGER NOT NULL DEFAULT 0,
  inserted_count INTEGER NOT NULL DEFAULT 0,
  ready_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0,
  estimated_cost_usd DOUBLE PRECISION NOT NULL DEFAULT 0,
  details TEXT,
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_x_realtime_run_job ON x_realtime_run(job);
CREATE INDEX IF NOT EXISTS idx_x_realtime_run_status ON x_realtime_run(status);
CREATE INDEX IF NOT EXISTS idx_x_realtime_run_started ON x_realtime_run(started_at);

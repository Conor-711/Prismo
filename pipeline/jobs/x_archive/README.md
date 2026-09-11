# Local X archive import

`DATABASE_URL='sqlite:///./data/dev.db' python -m pipeline.manage x-import-archive --tweet-dir /path/to/roster --report data/runtime/x-import.json`

Accepts repeated archive directories and `--dry-run`. Requires the existing schema; performs no DDL. Reads all JSONL rows, skips retweets and empty text, matches normalized cashtags to tickers with at least 80 local closing prices, and inserts missing `(ticker, tweet_id)` records. Existing raw evidence and other platforms remain intact. Committed batches can be resumed by rerunning the same command.

Follow with `sv-v0 --stage candidates --source x --candidate-limit 0 --tweet-dir /path/to/roster`. To process only the newly supplied period, use `sv-v0 --stage extract --source x --extract-mode rank --extract-limit 0 --created-since YYYY-MM-DD`. Date filtering applies to extraction; settlement and scoring retain historical evidence.

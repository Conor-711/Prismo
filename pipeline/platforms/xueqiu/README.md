# Xueqiu Platform Adapter

## Responsibilities

- `direct.py`: same-origin Playwright fetch for ticker search pages and author timelines.
- `pipeline.py`: ticker-based raw/job/checkpoint pipeline and `gr_post` synchronization.
- `author_timeline.py`: versioned author-pool timeline jobs with authenticated pagination.
- `adapter.py`: stable platform API used by job workflows.

## Data

- `xueqiu_raw_post`: shared source-of-truth post payloads.
- `xueqiu_post_ticker`: extracted post-to-ticker mappings.
- `xueqiu_author_snapshot`: follower/activity/verification snapshots.
- `xueqiu_author_pool`: versioned discovery pool; this is not an Score ranking.
- `xueqiu_author_crawl_job`: one resumable author timeline job per pool version and window.

## Authentication

Ticker search page 1 is available from a warmed browser session, but author timeline pagination
requires a logged-in Xueqiu session. Run `make xueqiu-author-auth` and complete login yourself in
the opened Chrome window. The command stores Playwright storage state in
`.xueqiu_storage_state.json`, which is ignored by Git. The pipeline never asks for or stores a
password.

## Workflow

```bash
make xueqiu-author-plan
make xueqiu-author-auth
MAX_JOBS=4 make xueqiu-author-run
make xueqiu-author-drain
make xueqiu-author-status
make xueqiu-sv-full
```

`xueqiu-author-run` executes one controlled batch. `xueqiu-author-drain` repeatedly runs the
selected 300-author pool in small batches, waits between batches, applies adaptive backoff when
a batch hits throttling, another pipeline holds SQLite's writer lock, or browser navigation is
temporarily reset, resumes partial cursors, and retries failed jobs up to the configured attempt limit. Interrupted `running` jobs older than
ten minutes return to `pending` without resetting their cursor. Stop it cleanly with `Ctrl-C`;
persisted jobs continue from their last cursor on the next run.

`xueqiu-sv-full` is the end-to-end unattended workflow. It verifies that every selected creator
job is complete before starting Xueqiu candidate recall, author-balanced LLM extraction, price
settlement, platform scoring, and export. An incomplete or blocked pool exits before Score scoring.

The first pool version uses a discovery gate of at least 500 followers (or verified) and at least
300 lifetime statuses, removes obvious publisher accounts, selects the Top 300 creators, and keeps
the remaining creators as warm reserves. Followers and lifetime statuses are recall signals only and must
not enter the Smart Account accuracy score.

## Operational Limits

- Do not run author backfill without a local SQLite `DATABASE_URL`.
- Use small batches, a roughly two-second randomized page interval, and resume from `cursor_page`;
  Xueqiu throttles aggressive pagination.
- Persist raw posts before ticker extraction or Score analysis.
- A guest smoke run may validate page 1, but it cannot complete a one-year backfill.

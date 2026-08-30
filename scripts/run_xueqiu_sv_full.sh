#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

POOL_VERSION="${POOL_VERSION:-xueqiu-sv-pool-20260710-v2}"
PYTHON="${PIPELINE_PYTHON:-pipeline/.venv/bin/python}"
DB_PATH="${XUEQIU_DB_PATH:-data/dev.db}"
PID_FILE="${XUEQIU_SV_PID_FILE:-/tmp/bsmart-xueqiu-sv-full.pid}"
export DATABASE_URL="sqlite:///./${DB_PATH}"

if [[ ! "$POOL_VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "[xueqiu-sv-full] invalid pool version: $POOL_VERSION"
  exit 1
fi

if [[ -f "$PID_FILE" ]]; then
  existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "[xueqiu-sv-full] already running pid=$existing_pid"
    exit 1
  fi
fi
echo "$$" > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

if [[ "${INITIAL_DELAY:-0}" -gt 0 ]]; then
  echo "[xueqiu-sv-full] initial cooldown ${INITIAL_DELAY}s"
  sleep "$INITIAL_DELAY"
fi

"$PYTHON" -m pipeline.manage gr-xueqiu-author-drain \
  --pool-version "$POOL_VERSION" \
  --batch-size "${BATCH_SIZE:-3}" \
  --cooldown "${COOLDOWN:-300}" \
  --failure-cooldown "${FAILURE_COOLDOWN:-1800}" \
  --max-failure-cooldown "${MAX_FAILURE_COOLDOWN:-3600}" \
  --max-cycles 0 \
  --sleep "${PAGE_SLEEP:-2.0}" \
  --max-attempts "${MAX_ATTEMPTS:-5}" \
  --headless \
  --expand-tickers \
  --days 365

IFS='|' read -r done_count total_count < <(
  sqlite3 "$DB_PATH" "
    SELECT
      SUM(CASE WHEN EXISTS (
        SELECT 1 FROM xueqiu_author_crawl_job j
         WHERE j.pool_version=p.pool_version
           AND j.user_id=p.user_id
           AND j.status='done'
      ) THEN 1 ELSE 0 END),
      COUNT(*)
      FROM xueqiu_author_pool p
     WHERE p.pool_version='${POOL_VERSION}'
       AND p.selected=1
       AND p.author_type='creator';
  "
)

if [[ "${done_count:-0}" -ne "${total_count:-0}" ]] || [[ "${total_count:-0}" -eq 0 ]]; then
  echo "[xueqiu-sv-full] author pool incomplete: ${done_count:-0}/${total_count:-0}; SV stages skipped."
  exit 2
fi

echo "[xueqiu-sv-full] author pool complete: ${done_count}/${total_count}; starting SV."
"$PYTHON" -m pipeline.manage sv-v0 \
  --stage candidates --source xueqiu --candidate-limit 0 \
  --xueqiu-pool-version "$POOL_VERSION" --xueqiu-since-days 365
"$PYTHON" -m pipeline.manage sv-v0 \
  --stage extract --source xueqiu --extract-limit 0 \
  --extract-mode author-balanced --per-author-min 20 --per-author-max 80 \
  --workers "${SV_WORKERS:-4}"
"$PYTHON" -m pipeline.manage sv-v0 --stage settle --source xueqiu
"$PYTHON" -m pipeline.manage sv-v0 --stage score --source xueqiu
"$PYTHON" -m pipeline.manage sv-v0 --stage export --source xueqiu
echo "[xueqiu-sv-full] complete."

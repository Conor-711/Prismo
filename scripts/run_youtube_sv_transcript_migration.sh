#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON_BIN="${PYTHON_BIN:-$ROOT/pipeline/.venv/bin/python}"
TRANSCRIPT_BATCH_SIZE="${TRANSCRIPT_BATCH_SIZE:-250}"
MAX_TRANSCRIPT_BATCHES="${MAX_TRANSCRIPT_BATCHES:-1}"
TRANSCRIPT_WORKERS="${TRANSCRIPT_WORKERS:-4}"
TRANSCRIPT_DAILY_MINUTES="${TRANSCRIPT_DAILY_MINUTES:-0}"
TRANSCRIPT_REQUEST_INTERVAL="${TRANSCRIPT_REQUEST_INTERVAL:-3}"
TRANSCRIPT_MODEL="${TRANSCRIPT_MODEL:-${GEMINI_MODEL:-gemini-3-flash-preview}}"
EXTRACT_WORKERS="${EXTRACT_WORKERS:-8}"
MIN_READY_AUTHORS="${MIN_READY_AUTHORS:-300}"
DB_PATH="${PRICE_DB:-$ROOT/data/dev.db}"
LOCK_DIR="${YOUTUBE_SV_LOCK_DIR:-${TMPDIR:-/tmp}/prismo-youtube-sv-migration.lock}"

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$LOCK_DIR/pid"
    return
  fi
  lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "[youtube-sv-migration] another migration is running pid=$lock_pid" >&2
    exit 4
  fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
  echo "$$" > "$LOCK_DIR/pid"
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

acquire_lock
trap release_lock EXIT

export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
export PRICE_DB="$DB_PATH"
# Paid Gemini mode is the migration default. A positive value restores a
# run-specific cost ceiling without changing other YouTube jobs.
export YT_DAILY_VIDEO_MINUTES="$TRANSCRIPT_DAILY_MINUTES"
export GEMINI_MIN_REQUEST_INTERVAL="$TRANSCRIPT_REQUEST_INTERVAL"
export GEMINI_MODEL="$TRANSCRIPT_MODEL"

if [[ "$TRANSCRIPT_DAILY_MINUTES" == "0" ]]; then
  echo "[youtube-sv-migration] Gemini paid mode: daily video-minute guard disabled"
else
  echo "[youtube-sv-migration] Gemini daily video-minute guard=${TRANSCRIPT_DAILY_MINUTES}"
fi
echo "[youtube-sv-migration] Gemini request interval=${TRANSCRIPT_REQUEST_INTERVAL}s"
echo "[youtube-sv-migration] Gemini model=${TRANSCRIPT_MODEL}"

ready_author_count() {
  sqlite3 "$DB_PATH" <<'SQL'
SELECT COUNT(*) FROM (
  SELECT investor_id
    FROM sv_call
   WHERE source='youtube'
     AND scoring_version='v1.8-transcript-lifecycle'
     AND transcript_version='youtube-transcript-v2'
     AND is_actionable_call=1
   GROUP BY investor_id
  HAVING COUNT(*)>=5
);
SQL
}

fulltext_count() {
  sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM yt_fulltext;"
}

ready_authors="$(ready_author_count)"
for ((batch=1; batch<=MAX_TRANSCRIPT_BATCHES; batch++)); do
  if (( ready_authors >= MIN_READY_AUTHORS )); then
    break
  fi

  before_fulltexts="$(fulltext_count)"
  echo "[youtube-sv-migration] batch=${batch}/${MAX_TRANSCRIPT_BATCHES} ready=${ready_authors}/${MIN_READY_AUTHORS}"

  "$PYTHON_BIN" -m pipeline.manage sv-v0 \
    --source youtube \
    --stage transcripts \
    --extract-limit "$TRANSCRIPT_BATCH_SIZE" \
    --per-author-min 20 \
    --per-author-max 40 \
    --workers "$TRANSCRIPT_WORKERS"

  "$PYTHON_BIN" -m pipeline.manage sv-v0 \
    --source youtube \
    --stage extract \
    --extract-limit 0 \
    --extract-mode author-balanced \
    --per-author-min 20 \
    --per-author-max 40 \
    --workers "$EXTRACT_WORKERS"

  ready_authors="$(ready_author_count)"
  after_fulltexts="$(fulltext_count)"
  echo "[youtube-sv-migration] batch=${batch} fulltexts_added=$((after_fulltexts-before_fulltexts)) ready=${ready_authors}/${MIN_READY_AUTHORS}"
  if (( after_fulltexts == before_fulltexts )); then
    echo "[youtube-sv-migration] stopping: the batch produced no new full transcripts" >&2
    break
  fi
done

echo "[youtube-sv-migration] authors_with_5_transcript_calls=$ready_authors target=$MIN_READY_AUTHORS"

if [[ "${PUBLISH:-0}" != "1" ]]; then
  echo "[youtube-sv-migration] extraction complete; set PUBLISH=1 only after quality audit."
  exit 0
fi

if (( ready_authors < MIN_READY_AUTHORS )); then
  echo "[youtube-sv-migration] refusing publish: qualified evidence pool is too small." >&2
  exit 2
fi

make backup-db
"$PYTHON_BIN" -m pipeline.manage sv-v0 --source all --stage settle
"$PYTHON_BIN" -m pipeline.manage sv-v0 --source all --stage score

formal_qualified="$(sqlite3 "$DB_PATH" <<'SQL'
SELECT COUNT(*)
  FROM sv_investor_score
 WHERE source='youtube'
   AND n_eff>=4
   AND settled_calls>=5;
SQL
)"
echo "[youtube-sv-migration] formally_qualified_authors=$formal_qualified target=$MIN_READY_AUTHORS"
if (( formal_qualified < MIN_READY_AUTHORS )); then
  echo "[youtube-sv-migration] refusing export: formal qualified pool is too small." >&2
  exit 3
fi

"$PYTHON_BIN" -m pipeline.manage sv-v0 --source all --stage export
make snapshot-db

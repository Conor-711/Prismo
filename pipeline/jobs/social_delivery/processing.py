"""Reuse Score and complete-text analysis, bounded to observed source IDs."""
from ...domain.smart_voice import v0_impl as score


def candidate_rows(con, source, ids):
    rows = []
    ordered = sorted(ids)
    for offset in range(0, len(ordered), 400):
        batch = ordered[offset:offset + 400]
        rows.extend(con.execute('SELECT * FROM sv_call_candidate WHERE source=? AND tweet_id IN (' +
            ','.join('?' for _ in batch) + ')', [source, *batch]).fetchall())
    return rows


def process_candidates(con, source, ids, database, max_calls):
    if not ids:
        return {'candidates': 0}
    if source == 'youtube':
        score.build_youtube_candidates(con, 0, 12.0, None, 2000, 7, initialize_schema=False)
    else:
        score.build_reddit_candidates(con, 0, 12.0, None, 1000, 7, 1, initialize_schema=False)
    rows = candidate_rows(con, source, ids)
    if source == 'youtube':
        # The client feed itself is scoped to formally ranked Top 25% authors.
        # Keep metadata from all selected channels, but spend transcript/model
        # budget only on authors whose new views can enter that feed.
        from ...domain.smart_voice.client_read_model import _profile_rows
        eligible = {row['investor_id'] for row in _profile_rows(con, 0)
                    if row['source'] == 'youtube' and row['platform_percentile'] <= .25}
        rows = [row for row in rows if str(row['author_id']).lower() in eligible]
    pending = [r for r in rows if not con.execute('SELECT 1 FROM sv_call WHERE candidate_id=?', (r['candidate_id'],)).fetchone()]
    if len(pending) > max_calls:
        raise RuntimeError('analysis_budget_exceeded')
    if source == 'youtube' and pending:
        from ...common.config import settings
        from ...domain.opinions.youtube import generate_fulltext
        videos = score.materialize_youtube_transcript_videos(con, pending)
        generate_fulltext(only=None, per_ticker=0, workers=2, force=False, low_res=True, frames=False,
            limit=30, max_native_min=179, fail_after=3, max_rate_waits=3, video_ids=videos,
            db_path=database, max_total_minutes=settings.yt_daily_video_minutes,
            prefer_transcript=True, initialize_schema=False)
        if any(not con.execute('SELECT 1 FROM yt_fulltext WHERE video_id=?', (r['tweet_id'],)).fetchone() for r in pending):
            raise RuntimeError('transcripts_incomplete')
    if pending:
        score.extract_calls(con, 0, 2, False, 'rank', 0, 0, sources={source},
            candidate_ids={r['candidate_id'] for r in pending}, initialize_schema=False)
    if any(not con.execute('SELECT 1 FROM sv_call WHERE candidate_id=?', (r['candidate_id'],)).fetchone() for r in rows):
        raise RuntimeError('analysis_incomplete')
    # Older YouTube transcript calls predate the bilingual summary fields.
    # Re-extract only those candidate IDs once, then enforce the same gate.
    def missing_summaries():
        return {row['candidate_id'] for row in rows if (call := con.execute(
            'SELECT * FROM sv_call WHERE candidate_id=?', (row['candidate_id'],)).fetchone())
            and call['is_actionable_call'] and (not call['summary_zh'] or not call['summary_en'])}
    missing = missing_summaries()
    reprocessed = 0
    if source == 'youtube' and missing:
        reprocessed = len(missing)
        score.extract_calls(con, 0, 2, True, 'rank', 0, 0, sources={source},
                            candidate_ids=missing, initialize_schema=False)
        missing = missing_summaries()
    if missing:
        raise RuntimeError('bilingual_thesis_missing')
    return {'candidates': len(rows), 'processed': len(pending) + reprocessed}

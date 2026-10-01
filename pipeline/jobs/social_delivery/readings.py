"""Prepare full translations only for Reddit views entering the client feed."""
from ...domain.opinions import kol_refine, kol_translate
from ...domain.opinions.translation_completeness import validate_translation
from ...domain.smart_voice.client_read_model import _update_rows
from ...platforms.reddit.profile_assets import refresh_avatars


def prepare_readings(con, ids, as_of, max_calls):
    # Reuse feed eligibility without rebuilding prices/evidence for every platform.
    views = [view for view in _update_rows(con, as_of=as_of, days=30, limit=0)
             if view['source'] == 'reddit' and view['source_post_id'] in ids]
    rows = {(view['source_post_id'], view['ticker']): {
        'source': 'reddit', 'item_id': view['source_post_id'], 'ticker': view['ticker'],
        'txt': view['original_text'] or '', 'created': view['created_at']}
        for view in views}
    rows = list(rows.values())
    if len(rows) > max_calls:
        raise RuntimeError('reading_budget_exceeded')
    kol_refine.refine(sources=['reddit'], rows=rows, workers=2,
                      initialize_schema=False, complete_text=True)
    kol_translate.translate(sources=['reddit'], rows=rows, workers=2,
                            initialize_schema=False, complete_text=True)
    for row in rows:
        saved = con.execute('SELECT trans_zh,trans_en FROM kol_refined '
                            'WHERE source=? AND item_id=? AND ticker=?',
                            ('reddit', row['item_id'], row['ticker'])).fetchone()
        if not row['txt'].strip() or not saved or not validate_translation(
                row['txt'], {'zh': saved[0] or '', 'en': saved[1] or ''}):
            raise RuntimeError('reddit_translation_incomplete')
    avatars = refresh_avatars(con, {view['investor_id'] for view in views})
    return {'readyViews': len(rows), 'translationMode': 'required', 'avatars': avatars}

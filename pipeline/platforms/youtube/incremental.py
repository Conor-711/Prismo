"""Low-quota channel uploads polling; no video files, search or schema mutations."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import requests
from .uploads import _request_json, _hydrate_videos, _store_page


def channel_window(channel, playlist, since, until, key, *, session=None, max_pages=10):
    session = session or requests.Session()
    token, ids = '', set()
    for _ in range(max_pages):
        try:
            payload = _request_json(session, 'playlistItems', {'part': 'contentDetails', 'playlistId': playlist,
                'maxResults': 50, 'pageToken': token, 'key': key}, attempts=3)
        except RuntimeError as error:
            if str(error).startswith('http:404:'):
                return None  # Officially unavailable playlist; retain previous content.
            raise
        reached = False
        for item in payload.get('items', []):
            details = item.get('contentDetails') or {}
            if not details.get('videoPublishedAt'):
                continue
            created = datetime.fromisoformat(details['videoPublishedAt'].replace('Z', '+00:00'))
            if created < since:
                reached = True
            if since <= created <= until:
                ids.add(details['videoId'])
        token = payload.get('nextPageToken') or ''
        if reached or not token:
            return ids
    raise RuntimeError('youtube_window_truncated')


def collect(since, until, channels, key):
    if not key:
        raise RuntimeError('youtube_key_missing')
    session = requests.Session()
    playlists = {}
    for offset in range(0, len(channels), 50):
        payload = _request_json(session, 'channels', {'part': 'contentDetails',
            'id': ','.join(channels[offset:offset + 50]), 'key': key}, attempts=3)
        for item in payload.get('items', []):
            playlists[item['id']] = item['contentDetails']['relatedPlaylists']['uploads']
    unavailable = sorted(set(channels) - set(playlists))
    if len(playlists) < len(channels) * .9:
        raise RuntimeError('youtube_channel_coverage_drop')
    ids = set()
    with ThreadPoolExecutor(max_workers=4) as executor:
        for channel, result in executor.map(lambda c: (c, channel_window(c, playlists[c], since, until, key)), sorted(playlists)):
            if result is None:
                unavailable.append(channel)
            else:
                ids.update(result)
    if len(unavailable) > len(channels) * .1:
        raise RuntimeError('youtube_channel_coverage_drop')
    videos = []
    ordered = sorted(ids)
    for offset in range(0, len(ordered), 50):
        videos.extend(_hydrate_videos(session, ordered[offset:offset + 50], key))
    if {v['video_id'] for v in videos} != ids:
        raise RuntimeError('youtube_video_unavailable')
    return {'provider': 'youtube-data-api', 'complete': True, 'items': videos,
            'requestedChannels': len(channels), 'availableChannels': len(channels) - len(unavailable), 'unavailableChannels': unavailable,
            'checkedAt': until.isoformat(), 'sourceThrough': max((v['published_utc'] for v in videos), default=None)}


def store(con, items, pool_version):
    for item in items:
        _store_page(con, pool_version=pool_version, channel_id=item['channel_id'], videos=[item],
                    fetched_at=datetime.now(timezone.utc).isoformat())
    con.commit()

"""Identity-checked public Reddit avatars; preserve last-good assets on failure."""
from datetime import datetime, timedelta, timezone
from html import unescape
from html.parser import HTMLParser
import json
import re
import urllib.request

from ...common.reddit_profile_avatars import username, verified_records, avatar_url
from ..author_assets.avatars import reddit_token


def verified_avatar(handle, url):
    return verified_records({'profiles': {handle: {
        'profileURL': f'https://www.reddit.com/user/{handle}/', 'avatarURL': url}}}).get(handle)


class ProfileImages(HTMLParser):
    def __init__(self, handle):
        super().__init__()
        self.handle, self.url = handle, None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'img' and attrs.get('alt', '').lower() in {
                f'u/{self.handle} avatar', f'{self.handle} u/{self.handle} avatar'}:
            self.url = verified_avatar(self.handle, unescape(attrs.get('src', ''))) or self.url


def fetch_avatar(handle, token=None, ua='bSmart profile assets/1.0'):
    url = (f'https://oauth.reddit.com/user/{handle}/about' if token else
           f'https://www.reddit.com/user/{handle}/')
    headers = {'User-Agent': ua}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=15) as response:
        if token:
            data = json.load(response).get('data', {})
            if username(data.get('name', '')) != handle:
                return None
            return verified_avatar(handle, data.get('snoovatar_img') or data.get('icon_img') or '')
        parser = ProfileImages(handle)
        parser.feed(response.read(2_000_000).decode('utf-8', 'replace'))
        return parser.url


def refresh_avatars(con, identities, *, fetch=fetch_avatar, clock=lambda: datetime.now(timezone.utc)):
    now = clock()
    result = {'resolved': 0, 'cached': 0, 'unavailable': 0}
    try:
        token, ua = reddit_token()
    except Exception:
        token, ua = None, 'bSmart profile assets/1.0'
    for handle in sorted({username(identity) for identity in identities}):
        if not re.fullmatch(r'[a-z0-9_-]{3,20}', handle):
            result['unavailable'] += 1
            continue
        saved = con.execute("SELECT url,fetched_at FROM author_avatar WHERE source='reddit' "
                            'AND lower(handle)=?', (handle,)).fetchone()
        if saved and saved[0]:
            result['cached'] += 1
            continue
        url = avatar_url(handle)
        if not url and saved and saved[1]:
            try:
                checked = datetime.fromisoformat(saved[1]).replace(tzinfo=timezone.utc)
                if now - checked < timedelta(hours=24):
                    result['unavailable'] += 1
                    continue
            except ValueError:
                pass
        if not url:
            try:
                url = fetch(handle, token, ua)
            except Exception:
                url = None
        url = verified_avatar(handle, url or '')
        con.execute("INSERT INTO author_avatar(source,handle,url,fetched_at) VALUES('reddit',?,?,?) "
                    'ON CONFLICT(source,handle) DO UPDATE SET url=excluded.url,fetched_at=excluded.fetched_at',
                    (handle, url or '', now.isoformat()))
        result['resolved' if url else 'unavailable'] += 1
    con.commit()
    return result

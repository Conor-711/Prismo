"""Project reviewed public movements into immutable attribution sources, not fills."""
from datetime import UTC, datetime
import json
from pathlib import Path
import re
from urllib.parse import urlparse
from uuid import UUID


def money_sources(root: Path | dict):
    if isinstance(root, dict):
        accounts = root.get('smart-money', [])
        movements = root.get('smart-money-movements', [])
    else:
        path = root / 'smart-money-movements.json'
        if not path.exists():
            return
        accounts = json.loads((root / 'smart-money.json').read_text())
        movements = json.loads(path.read_text())
    by_id = {}
    for account in accounts:
        for key in (account['id'], account.get('address', account['id'])):
            by_id[key.lower()] = account
    for movement in movements:
        try:
            account = by_id[movement['accountId'].lower()]
            address = account.get('address', account['id']).lower()
            url = urlparse(movement.get('evidenceURL') or '')
            # Public account link must match the reviewed source's account exactly.
            if (not re.fullmatch(r'0x[0-9a-f]{40}', address)
                    or account.get('source') not in ('hyperdash', 'hyperliquid')
                    or url.scheme != 'https' or url.username or url.password
                    or url.hostname not in ('hyperdash.com', 'app.hyperliquid.xyz')
                    or address not in [part.lower() for part in url.path.split('/')]):
                continue
            observed = datetime.fromisoformat(movement['observedAt'].replace('Z', '+00:00'))
            if observed.tzinfo is None or observed > datetime.now(UTC):
                continue
            yield {
                'id': str(UUID(movement['id'])), 'authorId': account['id'], 'sourceKind': 'money',
                'platform': 'hyperliquid', 'ticker': movement['ticker'], 'marketCoin': movement['market'],
                'publishedAt': observed.isoformat(), 'evidenceURL': movement['evidenceURL'],
            }
        except (KeyError, ValueError, TypeError):
            continue

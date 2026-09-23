"""One bounded local snapshot, accepted only against the server's immutable manifest."""
import json
from pathlib import Path
from .contract import SCHEMAS, digest

PATH = Path(__file__).resolve().parents[3] / 'data/runtime/content-cache/current.json'


def load(revision, manifest):
    try:
        stored=json.loads(PATH.read_text())
        if stored['revision'] != revision or set(stored['collections']) != set(SCHEMAS):
            return None
        for name, items in stored['collections'].items():
            entry=manifest['collections'][name]
            if len(items)!=entry['count'] or digest(items)!=entry['sha256']:
                return None
        return stored['collections']
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return None


def save(revision, collections):
    # Cache failure must not turn a committed publication into an unreported failure.
    try:
        PATH.parent.mkdir(parents=True,exist_ok=True)
        temporary=PATH.with_suffix('.tmp')
        temporary.write_text(json.dumps({'revision':revision,'collections':collections},ensure_ascii=False))
        temporary.replace(PATH)
    except OSError:
        pass

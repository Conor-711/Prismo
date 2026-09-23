import json
import sys

import pytest

from services.client_api.content_release import __main__ as cli


def test_environment_wins_including_explicit_empty(monkeypatch):
    monkeypatch.setenv("BSMART_CONTENT_DATABASE_URL", "postgresql://configured")
    assert cli.publication_database_url() == "postgresql://configured"
    monkeypatch.setenv("BSMART_CONTENT_DATABASE_URL", "")
    assert cli.publication_database_url() == ""


def test_local_content_config_preserves_literal_values(tmp_path, monkeypatch):
    monkeypatch.delenv("BSMART_CONTENT_DATABASE_URL", raising=False)
    monkeypatch.setattr(cli, "REPO_ROOT", tmp_path)
    local = tmp_path / "services/client_api/.env.content.local"
    local.parent.mkdir(parents=True)
    local.write_text('BSMART_CONTENT_DATABASE_URL="postgresql://literal${PASSWORD}@host/db"\n')
    (tmp_path / ".env").write_text('BSMART_CONTENT_DATABASE_URL="postgresql://fallback"\n')
    assert cli.publication_database_url() == "postgresql://literal${PASSWORD}@host/db"


def test_only_explicit_content_key_is_loaded(tmp_path, monkeypatch):
    monkeypatch.delenv("BSMART_CONTENT_DATABASE_URL", raising=False)
    monkeypatch.setattr(cli, "REPO_ROOT", tmp_path)
    root = tmp_path / ".env"
    root.write_text('DATABASE_URL="postgresql://wrong-project"\n')
    assert cli.publication_database_url() == ""
    root.write_text('BSMART_CONTENT_DATABASE_URL="postgresql://content"\n')
    assert cli.publication_database_url() == "postgresql://content"


@pytest.mark.parametrize('catalog_error', [False, True])
def test_applied_content_syncs_trade_catalog_and_reports_failures(tmp_path, monkeypatch, catalog_error):
    class Engine:
        def dispose(self):
            pass

    seen = []
    monkeypatch.setattr(sys, 'argv', ['content-release', '--input-dir', str(tmp_path), '--apply'])
    monkeypatch.setattr(cli, 'publication_database_url', lambda: 'postgresql://configured')
    monkeypatch.setattr(cli, 'create_engine', lambda *args, **kwargs: Engine())
    monkeypatch.setattr(cli, 'publish', lambda *args, **kwargs: {'status': 'published', 'revision': 'current'})
    monkeypatch.setattr(cli, 'enabled', lambda: False)
    def sync(engine, *, apply):
        seen.append(apply)
        if catalog_error:
            raise RuntimeError('storage unavailable')
        return {'status': 'published', 'contentRevision': 'current'}
    monkeypatch.setattr('services.client_api.opinion_trades.publish_catalog.sync_active_content', sync)
    if catalog_error:
        with pytest.raises(SystemExit) as error:
            cli.main()
        assert error.value.code == 1
    else:
        cli.main()
    receipt = json.loads((tmp_path / 'supabase-publication.json').read_text())
    assert seen == [True]
    assert receipt['tradeCatalog']['status'] == ('failed' if catalog_error else 'published')
    assert receipt['status'] == 'published'

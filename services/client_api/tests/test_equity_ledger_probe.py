from contextlib import nullcontext
import json
from types import SimpleNamespace

import pytest

from services.client_api import probe_equity_ledger as probe


PAYLOAD = {"ticker": "ASTS", "side": "buy", "amount": "1", "slippageBps": 50, "maxNetworkFeeBps": 100}


def test_hash_matches_canonical_field_order_and_binds_constraints():
    account, owner, client = "account", "0x" + "2" * 40, "client"
    original = probe.request_params(account, owner, client, PAYLOAD)
    reordered = dict(reversed(list(PAYLOAD.items())))
    assert original["hash"] == probe.request_params(account, owner, client, reordered)["hash"]
    assert original["hash"] == probe.request_params(account, owner, "retry", PAYLOAD)["hash"]
    for patch in ({"amount": "2"}, {"side": "sell"}, {"ticker": "SPY"}, {"slippageBps": 51},
                  {"maxNetworkFeeBps": 101}, {"minimumOutput": "1"}):
        assert original["hash"] != probe.request_params(account, owner, client, {**PAYLOAD, **patch})["hash"]
    assert original["hash"] != probe.request_params("other", owner, client, PAYLOAD)["hash"]
    assert original["hash"] != probe.request_params(account, "0x" + "3" * 40, client, PAYLOAD)["hash"]


def test_default_probe_is_read_only_and_report_is_safe(monkeypatch, capsys, tmp_path):
    events = []
    engine = SimpleNamespace(connect=lambda: nullcontext(object()), dispose=lambda: events.append("dispose"))
    monkeypatch.setattr(probe, "publication_database_url", lambda: f"postgresql://user:secret@db.{probe.PROJECT}.supabase.co/postgres")
    monkeypatch.setattr(probe, "create_engine", lambda *args, **kwargs: engine)
    monkeypatch.setattr(probe, "permissions", lambda connection: events.append("permissions"))
    monkeypatch.setattr(probe, "controlled_draft", lambda *args: pytest.fail("Implicit write"))
    output = tmp_path / "probe.json"
    monkeypatch.setattr("sys.argv", ["probe", "--output", str(output)])
    probe.main()
    raw = capsys.readouterr().out
    assert "secret" not in raw
    report = json.loads(output.read_text())
    assert report["migrationPermissionsVerified"] is True
    assert report["executionEnabled"] is False
    assert report["fundsMoved"] is False
    assert report["providerQuoteTest"] is False
    assert "probeClientIntentId" not in report
    assert events == ["permissions", "dispose"]


def test_other_project_rejected_before_connection(monkeypatch, capsys):
    monkeypatch.setattr(probe, "publication_database_url", lambda: "postgresql://user:secret@db.other.supabase.co/postgres")
    monkeypatch.setattr(probe, "create_engine", lambda *args, **kwargs: pytest.fail("Wrong project connected"))
    monkeypatch.setattr("sys.argv", ["probe"])
    with pytest.raises(SystemExit) as result:
        probe.main()
    assert result.value.code == 1
    assert "secret" not in capsys.readouterr().out


def test_project_database_requires_exact_trusted_host_and_pooler_identity():
    for value in (f"postgresql://postgres@db.{probe.PROJECT}.supabase.co/postgres",
                  f"postgresql://postgres.{probe.PROJECT}@aws-0-region.pooler.supabase.com/postgres"):
        assert probe.project_database(probe.make_url(value))
    for value in (f"postgresql://postgres.{probe.PROJECT}@other.example/postgres",
                  f"postgresql://postgres@db.{probe.PROJECT}.supabase.co.other.example/postgres",
                  f"postgresql://postgres.other@aws-0-region.pooler.supabase.com/postgres",
                  f"postgresql://postgres@db.{probe.PROJECT}.supabase.co/other"):
        assert not probe.project_database(probe.make_url(value))


def test_database_exception_is_not_printed(monkeypatch, capsys):
    monkeypatch.setattr(probe, "publication_database_url", lambda: f"postgresql://user:secret@db.{probe.PROJECT}.supabase.co/postgres")
    def broken(*args, **kwargs):
        raise RuntimeError("secret database address")
    monkeypatch.setattr(probe, "create_engine", broken)
    monkeypatch.setattr("sys.argv", ["probe", "--apply"])
    with pytest.raises(SystemExit):
        probe.main()
    assert "secret" not in capsys.readouterr().out


def test_preparation_probe_is_explicit_and_read_only(monkeypatch, capsys):
    events = []
    engine = SimpleNamespace(connect=lambda: nullcontext(object()), dispose=lambda: None)
    monkeypatch.setattr(probe, "publication_database_url", lambda: f"postgresql://user:secret@db.{probe.PROJECT}.supabase.co/postgres")
    monkeypatch.setattr(probe, "create_engine", lambda *args, **kwargs: engine)
    monkeypatch.setattr(probe, "permissions", lambda connection: None)
    monkeypatch.setattr(probe, "preparation_permissions", lambda connection: {"preparationSchemaVerified": True})
    monkeypatch.setattr(probe, "preparation_lock_probe", lambda engine: {"concurrentSharedLockTest": True})
    monkeypatch.setattr(probe, "controlled_draft", lambda *args: events.append("unexpected_write"))
    monkeypatch.setattr("sys.argv", ["probe", "--preparations"])
    probe.main()
    report = json.loads(capsys.readouterr().out)
    assert report["preparationSchemaVerified"] is True
    assert report["concurrentSharedLockTest"] is True
    assert report["fundsMoved"] is False
    assert events == []


def test_preparation_probe_rejects_write_option_before_connect(monkeypatch, capsys):
    monkeypatch.setattr(probe, "create_engine", lambda *args, **kwargs: pytest.fail("Unexpected connection"))
    monkeypatch.setattr("sys.argv", ["probe", "--preparations", "--apply"])
    with pytest.raises(SystemExit):
        probe.main()
    assert "secret" not in capsys.readouterr().out

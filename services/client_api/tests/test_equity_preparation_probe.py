from datetime import datetime, timezone
import json

from services.client_api.probe_equity_preparations import synthetic_params


def test_synthetic_boundary_is_exact_and_non_executable():
    now = datetime(2026, 10, 1, microsecond=123456, tzinfo=timezone.utc)
    params = synthetic_params("a", "0x" + "1" * 40, "b", now)
    preview, material, prepared = (json.loads(params[key]) for key in ("preview", "material", "prepared"))
    assert preview["executionEnabled"] is False
    assert preview["gasCoverage"] == "unverified"
    assert material["input"]["amount"] == "1"
    assert material["expiresAt"] == prepared["order"]["validTo"] * 1000
    assert prepared["expiresAt"] == preview["candidates"][0]["expiresAt"]
    assert material["order"] == prepared["order"]
    assert len(prepared["orderUid"]) == 114
    assert "signature" not in prepared


def test_synthetic_probes_never_reuse_uid_or_fingerprint():
    args = ("a", "0x" + "1" * 40, "b", datetime.now(timezone.utc))
    first, second = (json.loads(synthetic_params(*args)["prepared"]) for _ in range(2))
    assert first["orderUid"] != second["orderUid"]
    assert first["fingerprint"] != second["fingerprint"]

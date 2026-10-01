from copy import deepcopy
import json
from pathlib import Path

import pytest
import yaml
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = yaml.safe_load((ROOT / "contracts/openapi/supabase-equities.yaml").read_text())
SCHEMA = {**CONTRACT["components"]["schemas"]["EquitySigningPayload"], "components": CONTRACT["components"]}
PAYLOADS = [v["payload"] for v in json.loads((ROOT / "contracts/fixtures/evm-equity-signing.json").read_text())["vectors"]]


@pytest.mark.parametrize("payload", PAYLOADS)
def test_offline_sdk_signing_vectors_conform(payload):
    Draft202012Validator(SCHEMA).validate(payload)


@pytest.mark.parametrize("patch", [{"state": "reserved"}, {"executionEnabled": True}, {"schema": "arbitrary"},
    {"typedData": {}}, {"signature": "0x"}, {"prepared": {}}, {"preparationHash": "bad"}])
def test_invalid_signing_payload_is_not_a_contract(patch):
    assert list(Draft202012Validator(SCHEMA).iter_errors({**deepcopy(PAYLOADS[0]), **patch}))


def test_http_contract_has_no_signing_or_execution_path():
    assert all(not any(word in path for word in ("signing", "authorize", "submit")) for path in CONTRACT["paths"])

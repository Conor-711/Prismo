"""Synthetic attestation, public test keys 2/3. Never uses Circle or device keys."""

import json
from pathlib import Path

from eth_keys import keys
from eth_utils import keccak

ROOT = Path(__file__).resolve().parents[3]


def vector():
    source = json.loads((ROOT / "ios/BSmartTests/Fixtures/cctp-source-message-vector.json").read_text())
    message = bytearray(bytes.fromhex(source["event"][2:])[64:496])
    message[12:44] = bytes.fromhex("ab" * 32)
    message[144:148] = (1000).to_bytes(4, "big")
    message[312:344] = (200_000).to_bytes(32, "big")
    message[344:376] = (1000).to_bytes(32, "big")
    digest = keccak(message)
    signatures = []
    for value in (2, 3):
        key = keys.PrivateKey(value.to_bytes(32, "big"))
        signature = key.sign_msg_hash(digest)
        serialized = signature.r.to_bytes(32, "big") + signature.s.to_bytes(32, "big") + bytes([27 + signature.v])
        signatures.append((key.public_key.to_checksum_address().lower(), serialized))
    signatures.sort()
    return {"provenance": "Synthetic offline CCTP attestation with public test keys 2/3; eth_keys + keccak. Not Circle signatures.",
            "message": "0x" + message.hex(), "digest": "0x" + digest.hex(),
            "signers": [address for address, _ in signatures],
            "attestation": "0x" + b"".join(signature for _, signature in signatures).hex()}


def test_independent_attestation_vector():
    actual = json.loads((ROOT / "ios/BSmartTests/Fixtures/cctp-attestation-vector.json").read_text())
    assert actual == vector()

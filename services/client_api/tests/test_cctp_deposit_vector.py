"""Independent offline vectors for the native codec; never signs user funds."""

import json
from pathlib import Path

from eth_abi import encode
from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils import keccak


def test_native_cctp_vector_against_independent_crypto_and_abi():
    root = Path(__file__).resolve().parents[3]
    vector = json.loads((root / "ios/BSmartTests/Fixtures/cctp-deposit-vector.json").read_text())
    typed = vector["typedData"]
    key = (1).to_bytes(32, "big")  # Public disposable test vector.
    owner = Account.from_key(key).address.lower()
    assert typed["domain"] == {
        "name": "USD Coin", "version": "2", "chainId": 42161,
        "verifyingContract": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
    }
    assert typed["message"] == {
        "from": owner, "to": "0xa95d9c1f655341597c94393fddc30cf3c08e4fce",
        "value": "10000000", "validAfter": "1769999970", "validBefore": "1770000300",
        "nonce": "0x" + "11" * 32,
    }
    message = encode_typed_data(full_message=typed)
    signed = Account.sign_message(message, key)
    assert "0x" + signed.message_hash.hex() == vector["digest"]
    assert "0x" + signed.signature.hex() == vector["signature"]
    assert Account.recover_message(message, signature=vector["signature"]).lower() == owner
    hook = b"cctp-forward" + bytes(12) + bytes(4) + (24).to_bytes(4, "big") + bytes.fromhex(owner[2:]) + bytes(4)
    assert len(hook) == 56
    assert "0x" + hook.hex() == vector["hook"]
    forwarder = bytes(12) + bytes.fromhex("b21d281dedb17ae5b501f6aa8256fe38c4e45757")
    types = ["(uint256,uint256,uint256,bytes32,uint8,bytes32,bytes32)",
             "(uint256,uint32,bytes32,bytes32,uint256,uint32,bytes)"]
    calldata = keccak(text="batchDepositForBurnWithAuth(" + ",".join(types) + ")")[:4] + encode(types, [
        (10_000_000, 1_769_999_970, 1_770_000_300, bytes.fromhex("11" * 32), signed.v,
         signed.r.to_bytes(32, "big"), signed.s.to_bytes(32, "big")),
        (10_000_000, 19, forwarder, forwarder, 240_000, 1000, hook),
    ])
    assert len(calldata) == 580
    assert "0x" + calldata.hex() == vector["callData"]

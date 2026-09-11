"""Offline type-2 vectors for the iOS funding boundary; public disposable key 1 only."""

import json
from pathlib import Path

import rlp
from eth_account import Account
from eth_utils import keccak, to_checksum_address


ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "ios/BSmartTests/Fixtures"


def source_vectors():
    authorization = json.loads((FIXTURES / "cctp-deposit-vector.json").read_text())
    key = (1).to_bytes(32, "big")
    owner = Account.from_key(key).address.lower()
    calldata = bytes.fromhex(authorization["callData"][2:])
    destination = "0xa95d9c1f655341597c94393fddc30cf3c08e4fce"
    cases = [(0, 200_000, 10_000_000), (7, 250_000, 123_456_789), (128, 300_000, 4_294_967_296)]
    vectors = []
    for nonce, estimate, price in cases:
        gas = (estimate * 120 + 99) // 100
        maximum_price = 2 * max(price, 10_000_000)
        tx = {
            "type": 2, "chainId": 42161, "nonce": nonce, "gas": gas,
            "maxFeePerGas": maximum_price, "maxPriorityFeePerGas": 0,
            "to": to_checksum_address(destination), "value": 0, "data": calldata, "accessList": [],
        }
        signed = Account.sign_transaction(tx, key)
        unsigned_fields = [42161, nonce, 0, maximum_price, gas, bytes.fromhex(destination[2:]), 0, calldata, []]
        digest = keccak(b"\x02" + rlp.encode(unsigned_fields))
        signature = signed.r.to_bytes(32, "big") + signed.s.to_bytes(32, "big") + bytes([signed.v])
        assert Account.recover_transaction(signed.raw_transaction).lower() == owner
        assert bytes(signed.raw_transaction) == b"\x02" + rlp.encode(unsigned_fields + [signed.v, signed.r, signed.s])
        assert signed.hash == keccak(signed.raw_transaction)
        vectors.append({
            "owner": owner, "nonce": hex(nonce), "estimatedGas": hex(estimate), "gasPrice": hex(price),
            "gasLimit": hex(gas), "maximumFeePerGas": hex(maximum_price),
            "maximumNetworkFee": hex(gas * maximum_price),
            "signingHash": "0x" + digest.hex(), "signature": "0x" + signature.hex(),
            "rawTransaction": "0x" + signed.raw_transaction.hex(), "transactionHash": "0x" + signed.hash.hex(),
        })
    return vectors


def test_source_vectors_match_independent_crypto_rlp_and_recovery():
    expected = json.loads((FIXTURES / "cctp-source-transaction-vectors.json").read_text())
    assert expected == source_vectors()
    assert {row["signature"][-2:] for row in expected} == {"00", "01"}


if __name__ == "__main__":
    print(json.dumps(source_vectors(), indent=2))

"""Independent ABI vectors for synthetic forwarding receipts, not mainnet deposits."""

import json
from pathlib import Path

from eth_abi import encode
from eth_utils import keccak

ROOT = Path(__file__).resolve().parents[3]


def vector():
    attested = json.loads((ROOT / "ios/BSmartTests/Fixtures/cctp-attestation-vector.json").read_text())
    message = bytes.fromhex(attested["message"][2:])
    owner = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
    forwarder = "0xb21d281dedb17ae5b501f6aa8256fe38c4e45757"
    wallet = "0x6b9e773128f453f5c2c60935ee2de2cbc5390a24"
    token = "0xb88339cb7199b77e23db6e890353e22632ba630f"
    transmitter = "0x81d40f21f12a8f0e3252bccb954d722d4c464b64"
    messenger = "0x28b5a0e9c621a5badaa536219b3a228c8168cf5d"
    system = "0x2000000000000000000000000000000000000000"
    tx_hash = "0x" + "42" * 32
    block_hash = "0x" + (490).to_bytes(32, "big").hex()

    def topic(signature):
        return "0x" + keccak(text=signature).hex()

    def address_topic(address):
        return "0x" + encode(["address"], [address]).hex()

    def log(address, signature, topics, types, values, index):
        return {"address": address, "topics": [topic(signature)] + topics,
                "data": "0x" + encode(types, values).hex(), "logIndex": hex(index),
                "blockNumber": hex(490), "blockHash": block_hash, "transactionIndex": "0x1",
                "transactionHash": tx_hash, "removed": False}

    variants = {}
    for mode, fee in [("perps", 0), ("fee", 100_000_001), ("spot", 0)]:
        logs = [
            log(transmitter, "MessageReceived(address,uint32,bytes32,bytes32,uint32,bytes)",
                [address_topic(forwarder), "0x" + message[12:44].hex(), "0x" + encode(["uint32"], [1000]).hex()],
                ["uint32", "bytes32", "bytes"], [3, encode(["address"], [messenger]), message[148:]], 10),
            log(token, "Transfer(address,address,uint256)", [address_topic(forwarder), address_topic(wallet)],
                ["uint256"], [9_800_000], 12),
            log(wallet, "Transfer(address,address,uint256)",
                [address_topic(owner if mode == "spot" else wallet), address_topic(system)], ["uint256"], [9_800_000], 13),
        ]
        core = 980_000_000 - fee
        if fee:
            logs.append(log(wallet, "NewCoreAccountFeeApplied(address,uint64,uint256,uint64)", [address_topic(owner)],
                            ["uint64", "uint256", "uint64"], [fee, 9_800_000, core], 14))
        if mode != "spot":
            logs.append(log(wallet, "SendAsset(address,uint64,uint32)", [address_topic(owner)],
                            ["uint64", "uint32"], [core, 0], 16))
        logs.append(log(forwarder, "MintAndForward(address,address,address,uint32,uint256)",
                        [address_topic(owner), address_topic(wallet), address_topic(token)],
                        ["uint32", "uint256"], [0, 9_800_000], 17))
        variants[mode] = {"transactionHash": tx_hash, "blockHash": block_hash, "blockNumber": hex(490),
                          "transactionIndex": "0x1", "status": "0x1", "contractAddress": None, "logs": logs}
    return {"provenance": "Synthetic receipts using eth_abi and Keccak; not mainnet transactions or funds.",
            "hash": tx_hash, "variants": variants}


def test_independent_forwarding_vectors():
    actual = json.loads((ROOT / "ios/BSmartTests/Fixtures/cctp-forward-vector.json").read_text())
    assert actual == vector()

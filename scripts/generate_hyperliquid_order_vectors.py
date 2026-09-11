"""Offline official-SDK vectors. Only the public disposable private key 1 is used."""

import argparse
import hashlib
import importlib.metadata
import json
from decimal import Decimal
from pathlib import Path

import msgpack
from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils import keccak
from hyperliquid.utils import signing
from hyperliquid.utils.types import Cloid


def generate() -> dict:
    assert importlib.metadata.version("hyperliquid-python-sdk") == "0.24.0"
    assert msgpack.__version__ == "1.1.2"
    wallet = Account.from_key(bytes(31) + b"\x01")
    cases = [
        ("native", 0, 5, "0.01234", "62000.0", True, False),
        ("builder", 110002, 3, "3.1250", "230.900", True, False),
        ("reduce-sell", 110002, 3, "1.200", "220.5", False, True),
        ("integer-exemption", 1, 4, "2", "123456", False, False),
        ("fractional-price", 2, 0, "1200", "0.001234", True, False),
        ("builder-code", 110002, 3, "3.125", "230.9", True, False),
        ("builder-code-max", 0, 5, "0.01234", "62000", False, True),
    ]
    vectors = []
    for index, (name, asset, decimals, size, price, buy, reduce_only) in enumerate(cases):
        cloid = "0x" + f"{index + 1:032x}"
        nonce = 1_789_084_800_000 + index
        expiry = nonce + 30_000
        wire = signing.order_request_to_order_wire(
            {"coin": "fixture", "is_buy": buy, "sz": float(size), "limit_px": float(price),
             "reduce_only": reduce_only, "order_type": {"limit": {"tif": "Ioc"}},
             "cloid": Cloid.from_str(cloid)}, asset
        )
        assert Decimal(wire["p"]) == Decimal(price) and Decimal(wire["s"]) == Decimal(size)
        # Another public disposable key's address, never a production recipient.
        builder = ({"b": Account.from_key(bytes(31) + b"\x02").address.lower(),
                    "f": 100 if name == "builder-code-max" else 10}
                   if name.startswith("builder-code") else None)
        action = signing.order_wires_to_order_action([wire], builder=builder)
        action_hash = signing.action_hash(action, None, nonce, expiry)
        typed = signing.l1_payload(signing.construct_phantom_agent(action_hash, True))
        message = encode_typed_data(full_message=typed)
        digest = keccak(b"\x19" + message.version + message.header + message.body)
        signature = signing.sign_l1_action(wallet, action, None, nonce, expiry, True)
        recovered = signing.recover_agent_or_user_from_l1_action(action, signature, None, nonce, expiry, True)
        assert recovered == wallet.address
        encoded_signature = (
            "0x" + f'{int(signature["r"], 16):064x}' + f'{int(signature["s"], 16):064x}'
            + f'{signature["v"]:02x}'
        )
        typed["message"]["connectionId"] = "0x" + action_hash.hex()
        vectors.append({
            "name": name, "asset": asset, "sizeDecimals": decimals, "inputSize": size,
            "inputPrice": price, "isBuy": buy, "reduceOnly": reduce_only, "cloid": cloid,
            "nonce": nonce, "expiresAfter": expiry, "owner": wallet.address.lower(),
            "action": action, "messagePack": "0x" + msgpack.packb(action).hex(),
            "actionHash": "0x" + action_hash.hex(), "typedData": typed,
            "digest": "0x" + digest.hex(), "signature": encoded_signature,
        })
    return {"sdk": "hyperliquid-python-sdk==0.24.0", "msgpack": "1.1.2",
            "sourceSHA256": hashlib.sha256(Path(signing.__file__).read_bytes()).hexdigest(),
            "notice": "Offline protocol vectors, public key 1. No funding or exchange request.",
            "vectors": vectors}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = generate()
    if args.check:
        assert json.loads(args.output.read_text()) == result, "Official SDK vector mismatch"
        print(f'Checked {len(result["vectors"])} official SDK vectors')
    else:
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(f'Generated {len(result["vectors"])} official SDK vectors')


if __name__ == "__main__":
    main()

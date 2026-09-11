"""Offline EIP-712 withdrawal vectors from Circle's schema; public key 1 only."""

import argparse
import importlib.metadata
import json
from pathlib import Path

from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils import keccak


def generate() -> dict:
    wallet = Account.from_key(bytes(31) + b"\x01")
    recipient = Account.from_key(bytes(31) + b"\x02").address.lower()
    fields = [
        ("hyperliquidChain", "string"), ("token", "string"), ("amount", "string"),
        ("sourceDex", "string"), ("destinationRecipient", "string"), ("addressEncoding", "string"),
        ("destinationChainId", "uint32"), ("gasLimit", "uint64"), ("data", "bytes"), ("nonce", "uint64"),
    ]
    domain_fields = [("name", "string"), ("version", "string"), ("chainId", "uint256"), ("verifyingContract", "address")]
    vectors = []
    for index, (source, amount) in enumerate([("spot", "10"), ("", "10.123456"), ("spot", "0.000001")]):
        message = {
            "hyperliquidChain": "Mainnet", "token": "USDC", "amount": amount, "sourceDex": source,
            "destinationRecipient": recipient, "addressEncoding": "hex", "destinationChainId": 3,
            "gasLimit": 200000, "data": "0x", "nonce": 1789084800000 + index,
        }
        typed = {
            "domain": {"name": "HyperliquidSignTransaction", "version": "1", "chainId": 42161,
                       "verifyingContract": "0x" + "0" * 40},
            "types": {"EIP712Domain": [{"name": n, "type": t} for n, t in domain_fields],
                      "HyperliquidTransaction:SendToEvmWithData": [{"name": n, "type": t} for n, t in fields]},
            "primaryType": "HyperliquidTransaction:SendToEvmWithData", "message": message,
        }
        encoded = encode_typed_data(full_message=typed)
        signed = wallet.sign_message(encoded)
        assert Account.recover_message(encoded, signature=signed.signature) == wallet.address
        digest = keccak(b"\x19" + encoded.version + encoded.header + encoded.body)
        vectors.append({"owner": wallet.address.lower(), "typedData": typed, "digest": "0x" + digest.hex(),
                        "signature": "0x" + signed.signature.hex(),
                        "action": {**message, "type": "sendToEvmWithData", "signatureChainId": "0xa4b1"}})
    return {"implementation": "eth-account==" + importlib.metadata.version("eth-account"),
            "source": "https://developers.circle.com/cctp/howtos/withdraw-usdc-from-hypercore-to-evm",
            "notice": "Offline vectors only. No wallet secrets, RPC or exchange writes.", "vectors": vectors}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = generate()
    if args.check:
        assert json.loads(args.output.read_text()) == result, "Withdrawal vector mismatch"
        print(f'Checked {len(result["vectors"])} withdrawal vectors')
    else:
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        print(f'Generated {len(result["vectors"])} withdrawal vectors')


if __name__ == "__main__":
    main()

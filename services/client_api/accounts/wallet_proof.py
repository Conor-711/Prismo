from datetime import UTC, datetime

from eth_account import Account
from eth_account.messages import encode_defunct
from eth_keys.exceptions import BadSignature
from eth_utils import ValidationError

from .wallet_models import WalletChallenge


# ECDSA low-s canonical form; do not accept alternate encodings of a proof.
SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141


def timestamp(value: datetime) -> str:
    return value.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def binding_message(challenge: WalletChallenge) -> str:
    return "\n".join([
        "bSmart wallet binding v1",
        "Audience: https://api.bsmart.today/v1/auth/wallet",
        f"Account: {challenge.accountId}",
        f"Address: {challenge.address}",
        "Chain ID: 42161",
        f"Challenge: {challenge.id}",
        f"Nonce: {challenge.nonce}",
        f"Issued At: {timestamp(challenge.issuedAt)}",
        f"Expires At: {timestamp(challenge.expiresAt)}",
        "This only links your wallet to bSmart. It does not authorize a transfer or trade.",
    ])


def verifies_binding(challenge: WalletChallenge, signature: str) -> bool:
    try:
        if len(signature) != 132 or not signature.startswith("0x"):
            return False
        raw = bytes.fromhex(signature[2:])
        r, s = int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:64], "big")
        if raw[64] not in (27, 28) or not 0 < r < SECP256K1_ORDER or not 0 < s <= SECP256K1_ORDER // 2:
            return False
        recovered = Account.recover_message(encode_defunct(text=binding_message(challenge)), signature=raw)
        return recovered.lower() == challenge.address and int(challenge.address[2:], 16) != 0
    except (ValueError, TypeError, IndexError, BadSignature, ValidationError):
        return False

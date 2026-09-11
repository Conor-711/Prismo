"""Disposable Apple/OAuth test material. Never imports application credentials."""
import base64
import json
import os

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from services.client_api.accounts.apple_oauth import AppleOAuthSettings
from services.client_api.accounts.credential_cipher import CredentialCipher

CODE = "disposable-native-code-" * 3
REFRESH = "disposable-provider-refresh-" * 3
ACCESS = "disposable-provider-access-" * 3


def apple_settings():
    return AppleOAuthSettings("today.bsmart.ios", "TESTTEAM01", "TESTKEY001",
        ec.generate_private_key(ec.SECP256R1()), CredentialCipher("v1", {"v1": os.urandom(32)}))


def configure_apple_files(monkeypatch, tmp_path):
    for key in ("BSMART_GOOGLE_SERVER_CLIENT_ID", "BSMART_GOOGLE_IOS_CLIENT_ID"):
        monkeypatch.delenv(key, raising=False)
    settings = apple_settings()
    signing = tmp_path / "test-only.p8"
    signing.write_bytes(settings.signing_key.private_bytes(serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    signing.chmod(0o600)
    keyring = tmp_path / "test-only-keyring.json"
    keyring.write_text(json.dumps({"active": "v1", "keys": {
        "v1": base64.b64encode(settings.cipher.keys["v1"]).decode()}}))
    keyring.chmod(0o600)
    for key, value in {
        "BSMART_ACCOUNT_AUTH_DEVELOPMENT": "1", "BSMART_APPLE_CLIENT_ID": settings.client_id,
        "BSMART_APPLE_TEAM_ID": settings.team_id, "BSMART_APPLE_KEY_ID": settings.key_id,
        "BSMART_APPLE_PRIVATE_KEY_FILE": str(signing), "BSMART_ACCOUNT_CREDENTIAL_KEY_FILE": str(keyring),
    }.items():
        monkeypatch.setenv(key, value)
    return settings, signing, keyring

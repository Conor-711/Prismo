"""Authenticated storage for provider refresh credentials, never wallet keys."""
import base64
import json
import os
import re
import stat
from dataclasses import dataclass, field
from types import MappingProxyType
from typing import Mapping

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class CredentialUnavailable(Exception):
    pass


def protected_file(path: str) -> bytes:
    if not os.path.isabs(path):
        raise ValueError("An absolute protected-file path is required")
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        if (not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077
                or info.st_uid != os.geteuid() or not 1 <= info.st_size <= 16384):
            raise ValueError("Invalid protected-file permissions or size")
        raw = os.read(descriptor, 16385)
        if len(raw) != info.st_size:
            raise ValueError("Protected file changed")
        return raw
    finally:
        os.close(descriptor)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON key")
        result[key] = value
    return result


@dataclass(frozen=True)
class CredentialCipher:
    active: str
    keys: Mapping[str, bytes] = field(repr=False)

    def __post_init__(self):
        if (not 1 <= len(self.keys) <= 8 or self.active not in self.keys
                or any(not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", key) or len(value) != 32
                       for key, value in self.keys.items())):
            raise ValueError("Invalid provider credential keyring")
        object.__setattr__(self, "keys", MappingProxyType(dict(self.keys)))

    @classmethod
    def from_file(cls, path: str):
        document = json.loads(protected_file(path), object_pairs_hook=unique_object)
        if set(document) != {"active", "keys"} or not isinstance(document["keys"], dict):
            raise ValueError("Invalid provider credential keyring")
        return cls(document["active"], {key: base64.b64decode(value, validate=True)
                                       for key, value in document["keys"].items()})

    @staticmethod
    def context(account_id: str, subject: str, client_id: str, key_id: str) -> bytes:
        return json.dumps(["bSmart.apple.refresh.v1", account_id, subject, client_id, key_id],
                          separators=(",", ":"), ensure_ascii=True).encode()

    def seal(self, token: str, account_id: str, subject: str, client_id: str) -> tuple[str, bytes]:
        if not 32 <= len(token) <= 8192 or not all(33 <= ord(c) <= 126 for c in token):
            raise CredentialUnavailable()
        nonce = os.urandom(12)
        ciphertext = AESGCM(self.keys[self.active]).encrypt(
            nonce, token.encode(), self.context(account_id, subject, client_id, self.active))
        return self.active, nonce + ciphertext

    def open(self, key_id: str, ciphertext: bytes, account_id: str, subject: str, client_id: str) -> str:
        try:
            if not 60 <= len(ciphertext) <= 8220:
                raise CredentialUnavailable()
            return AESGCM(self.keys[key_id]).decrypt(ciphertext[:12], ciphertext[12:],
                self.context(account_id, subject, client_id, key_id)).decode("ascii")
        except (InvalidTag, KeyError, ValueError, TypeError, UnicodeError):
            raise CredentialUnavailable() from None

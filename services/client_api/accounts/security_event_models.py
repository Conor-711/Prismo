import hashlib
import json
from dataclasses import dataclass, field
from datetime import datetime


def subject_key(provider: str, subject: str) -> str:
    return hashlib.sha256(f"{provider}\0{subject}".encode()).hexdigest()


@dataclass(frozen=True)
class VerifiedSecurityEvent:
    provider: str
    jti: str = field(repr=False)
    kind: str
    subject: str | None = field(repr=False)
    occurred_at: datetime
    action: str
    verification_hash: str | None = None

    @property
    def receipt_id(self):
        return subject_key(self.provider, self.jti)

    @property
    def fingerprint(self):
        fields = [self.provider, self.kind, subject_key(self.provider, self.subject) if self.subject else None,
                  self.occurred_at.isoformat(), self.action, self.verification_hash]
        return hashlib.sha256(json.dumps(fields, separators=(",", ":")).encode()).hexdigest()

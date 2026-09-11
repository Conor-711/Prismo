"""Deletion tickets contain no reusable account or wallet authorization."""
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import Field, SecretStr, model_validator

from .models import AccountModel
from .session_renewal import SessionRenewalRepository


class DeletionStatusInput(AccountModel):
    statusToken: SecretStr = Field(min_length=32, max_length=256)

    @model_validator(mode="after")
    def valid_ticket(self):
        if not SessionRenewalRepository.valid_token(self.statusToken.get_secret_value()):
            raise ValueError("Invalid deletion ticket")
        return self


class DeletionInput(DeletionStatusInput):
    id: UUID
    confirmDeletion: bool = Field(strict=True)
    walletRecoveryConfirmed: bool = Field(strict=True)

    @model_validator(mode="after")
    def confirmed(self):
        if not self.confirmDeletion or not self.walletRecoveryConfirmed:
            raise ValueError("Deletion confirmation required")
        return self


class DeletionStatus(AccountModel):
    id: UUID
    status: Literal["pending", "completed"]
    requestedAt: datetime
    completedAt: datetime | None
    retryAfterSeconds: int


class DeletionRejected(Exception):
    pass


class DeletionReauthenticationRequired(Exception):
    pass

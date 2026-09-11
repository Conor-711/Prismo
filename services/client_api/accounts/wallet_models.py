from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, StringConstraints


Address = Annotated[str, StringConstraints(min_length=42, max_length=42, pattern=r"^0x[0-9a-f]{40}$")]


class WalletModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class WalletRegistration(WalletModel):
    accountId: UUID
    address: Address | None


class WalletChallengeInput(WalletModel):
    address: Address


class WalletChallenge(WalletModel):
    id: UUID
    accountId: UUID
    address: Address
    nonce: Annotated[str, StringConstraints(min_length=64, max_length=64, pattern=r"^[0-9a-f]{64}$")]
    issuedAt: datetime
    expiresAt: datetime


class WalletBindingInput(WalletModel):
    challengeId: UUID
    signature: Annotated[str, StringConstraints(min_length=132, max_length=132, pattern=r"^0x[0-9a-fA-F]{130}$")]

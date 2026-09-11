from datetime import datetime
from typing import Literal
from uuid import UUID
import re

from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator

Provider = Literal["apple", "google"]


class AccountModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class AuthConfiguration(AccountModel):
    providers: list[Provider]
    depositsEnabled: Literal[False] = False
    tradingEnabled: Literal[False] = False


class ChallengeInput(AccountModel):
    provider: Provider


class AuthChallenge(AccountModel):
    id: UUID
    nonce: str
    expiresAt: datetime
    providerNonce: str | None = None


class SessionInput(AccountModel):
    challengeId: UUID
    expectedAccountId: UUID | None = None
    provider: Provider
    idToken: SecretStr = Field(min_length=32, max_length=16384)
    authorizationCode: SecretStr | None = Field(default=None, min_length=32, max_length=2048)
    nonce: SecretStr | None = Field(default=None, min_length=32, max_length=128)

    @model_validator(mode="after")
    def provider_assertion(self):
        if "nonce" in self.model_fields_set and (self.nonce is None or not re.fullmatch(
                r"[A-Za-z0-9_-]{32,128}", self.nonce.get_secret_value())):
            raise ValueError("Invalid sign-in nonce")
        if "expectedAccountId" in self.model_fields_set and self.expectedAccountId is None:
            raise ValueError("Expected account must be a UUID")
        if self.provider == "apple":
            if self.authorizationCode is None or not all(33 <= ord(c) <= 126 for c in self.authorizationCode.get_secret_value()):
                raise ValueError("Apple authorization code required")
        elif "authorizationCode" in self.model_fields_set:
            raise ValueError("Google does not accept an Apple authorization code")
        return self


class TradingAccount(AccountModel):
    id: UUID
    provider: Provider


class RefreshInput(AccountModel):
    refreshToken: SecretStr = Field(min_length=32, max_length=256)

    @model_validator(mode="after")
    def valid_token(self):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", self.refreshToken.get_secret_value()):
            raise ValueError("Invalid renewal credential")
        return self


class AccountSession(AccountModel):
    account: TradingAccount
    accessToken: str = Field(repr=False)
    expiresAt: datetime
    refreshToken: str = Field(repr=False)
    refreshExpiresAt: datetime

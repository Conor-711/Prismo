"""Disposable account-deletion fixtures; never reads live credentials or databases."""
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from sqlalchemy import event

from services.client_api.accounts.apple_repository import AppleGrantRepository
from services.client_api.accounts.deletion_models import DeletionInput
from services.client_api.accounts.deletion_work import AccountDeletionWorkRepository
from services.client_api.accounts.oidc import VerifiedIdentity
from services.client_api.accounts.repository import AccountBase, AccountRepository
from services.client_api.opinion_trades.repository import TradeBase
from services.client_api.tests.apple_test_support import REFRESH, apple_settings


@pytest.fixture
def accounts(tmp_path):
    result = AccountRepository(f"sqlite:///{tmp_path / 'deletion-only.db'}")
    @event.listens_for(result.engine, "connect")
    def foreign_keys(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")
    AccountBase.metadata.create_all(result.engine)
    TradeBase.metadata.create_all(result.engine)
    yield result
    result.engine.dispose()


def login(accounts, provider="google", subject="disposable-owner", installation=None, settings=None, issued_at=None):
    installation = installation or uuid4()
    identity = VerifiedIdentity(provider, subject, issued_at or datetime.now(UTC))
    challenge = accounts.challenge(installation, provider)
    if provider == "apple":
        settings = settings or apple_settings()
        grants = AppleGrantRepository(accounts)
        claim = grants.claim(challenge.id, installation, identity, settings.client_id)
        result = grants.finish(claim, REFRESH, settings.cipher)
    else:
        result = accounts.issue(challenge.id, installation, identity)
    return installation, result


def payload():
    return DeletionInput(id=uuid4(), statusToken="disposable-deletion-ticket-" + uuid4().hex,
                         confirmDeletion=True, walletRecoveryConfirmed=True)


def accept(accounts, session, request=None, settings=None, clock=lambda: datetime.now(UTC)):
    repository, request = AccountDeletionWorkRepository(accounts, clock=clock), request or payload()
    result = repository.begin(session.account.id, session.accessToken, request, settings.client_id if settings else None)
    return repository, request, result

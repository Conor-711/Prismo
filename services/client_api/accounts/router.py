import httpx
import hashlib
import hmac
from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

from .models import AccountSession, AuthChallenge, AuthConfiguration, ChallengeInput, RefreshInput, SessionInput, TradingAccount
from .oidc import IdentityUnavailable, InvalidIdentity, OIDCVerifier, ProviderKeys
from .repository import AccountRepository, ChallengeRejected, ChallengeThrottled
from .settings import AccountAuthSettings
from .wallet_routes import add_wallet_routes
from .apple_oauth import AppleCodeExchange
from .apple_repository import AppleGrantRepository
from .credential_cipher import CredentialUnavailable
from .session_renewal import SessionRenewalRepository
from .security_event_routes import add_security_event_routes
from .deletion_routes import add_deletion_routes
from .supabase_identity import SupabaseGoogleIdentity


def make_account_router(settings: AccountAuthSettings, repository: AccountRepository,
                        client: httpx.AsyncClient, require_installation) -> APIRouter:
    router = APIRouter(prefix="/v1/auth", tags=["Trading account"])
    verifier = OIDCVerifier(settings, ProviderKeys(client))
    apple_grants = AppleGrantRepository(repository)
    renewals = SessionRenewalRepository(repository)
    bearer = HTTPBearer(auto_error=False)

    def no_store(response: Response):
        response.headers["Cache-Control"] = "no-store"
        response.headers["Pragma"] = "no-cache"

    def available(provider: str | None = None):
        if not settings.providers or (provider and provider not in settings.providers):
            raise HTTPException(503, "Account sign-in is not available yet.", headers={"Cache-Control": "no-store"})

    @router.get("/configuration", response_model=AuthConfiguration)
    def configuration(response: Response):
        no_store(response)
        return AuthConfiguration(providers=settings.providers)

    @router.post("/challenges", response_model=AuthChallenge)
    def challenge(payload: ChallengeInput, response: Response, installation=Depends(require_installation)):
        no_store(response)
        available(payload.provider)
        try:
            challenge = repository.challenge(installation.installation_id, payload.provider)
            if settings.uses_supabase:
                challenge.providerNonce = hashlib.sha256(challenge.nonce.encode()).hexdigest()
            return challenge
        except ChallengeThrottled:
            raise HTTPException(429, "Please wait before trying again.", headers={"Retry-After": "300"})
        except SQLAlchemyError:
            raise HTTPException(503, "Account service unavailable.")

    @router.post("/sessions", response_model=AccountSession)
    async def sign_in(payload: SessionInput, response: Response, installation=Depends(require_installation)):
        no_store(response)
        available(payload.provider)
        try:
            nonce_hash = await run_in_threadpool(repository.nonce_hash, payload.challengeId,
                                                installation.installation_id, payload.provider)
            if settings.uses_supabase:
                if payload.nonce is None or not hmac.compare_digest(
                    hashlib.sha256(payload.nonce.get_secret_value().encode()).hexdigest(), nonce_hash
                ):
                    raise InvalidIdentity()
                identity = await verifier.verify(payload.provider, payload.idToken.get_secret_value(), nonce_hash,
                                                 nonce_is_hashed=True)
                identity = await SupabaseGoogleIdentity(settings, client).verify(
                    identity, payload.idToken.get_secret_value(), payload.nonce.get_secret_value())
            else:
                if payload.nonce is not None:
                    raise InvalidIdentity()
                identity = await verifier.verify(payload.provider, payload.idToken.get_secret_value(), nonce_hash)
            if payload.provider == "apple":
                if settings.apple is None or payload.authorizationCode is None:
                    raise IdentityUnavailable()
                claim = await run_in_threadpool(apple_grants.claim, payload.challengeId, installation.installation_id,
                                               identity, settings.apple.client_id)
                grant = await AppleCodeExchange(settings.apple, client).exchange(payload.authorizationCode.get_secret_value())
                exchanged = await verifier.verify("apple", grant.id_token, nonce_hash)
                if exchanged != identity:
                    raise InvalidIdentity()
                return await run_in_threadpool(apple_grants.finish, claim, grant.refresh_token, settings.apple.cipher,
                                               payload.expectedAccountId)
            return await run_in_threadpool(repository.issue, payload.challengeId,
                                           installation.installation_id, identity, payload.expectedAccountId)
        except (ChallengeRejected, InvalidIdentity):
            raise HTTPException(401, "Sign-in expired or could not be verified. Please try again.")
        except (IdentityUnavailable, CredentialUnavailable, SQLAlchemyError):
            raise HTTPException(503, "Account service unavailable.")

    @router.post("/sessions/refresh", response_model=AccountSession)
    def refresh(payload: RefreshInput, response: Response, installation=Depends(require_installation)):
        no_store(response)
        available()
        try:
            return renewals.rotate(payload.refreshToken.get_secret_value(), installation.installation_id)
        except ChallengeRejected:
            raise HTTPException(401, "Session expired or could not be verified. Please sign in again.")
        except ChallengeThrottled:
            raise HTTPException(429, "Please wait before trying again.", headers={"Retry-After": "60"})
        except SQLAlchemyError:
            raise HTTPException(503, "Account service unavailable.")

    @router.post("/sessions/revoke", status_code=204)
    def revoke_refresh(payload: RefreshInput, installation=Depends(require_installation)):
        available()
        try:
            renewals.revoke_refresh(payload.refreshToken.get_secret_value(), installation.installation_id)
        except SQLAlchemyError:
            raise HTTPException(503, "Account service unavailable.")
        return Response(status_code=204, headers={"Cache-Control": "no-store"})

    def authenticated(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        available()
        if credentials is None or credentials.scheme.lower() != "bearer":
            raise HTTPException(401, "Account sign-in required.")
        try:
            account = repository.authenticate(credentials.credentials)
        except SQLAlchemyError:
            raise HTTPException(503, "Account service unavailable.")
        if account is None:
            raise HTTPException(401, "Account sign-in required.")
        return account, credentials.credentials

    @router.get("/account", response_model=TradingAccount)
    def account(response: Response, session=Depends(authenticated)):
        no_store(response)
        return session[0]

    @router.delete("/sessions/current", status_code=204)
    def sign_out(session=Depends(authenticated)):
        try:
            repository.revoke(session[1])
        except SQLAlchemyError:
            raise HTTPException(503, "Account service unavailable.")
        return Response(status_code=204, headers={"Cache-Control": "no-store"})

    add_wallet_routes(router, repository, authenticated, no_store)
    add_security_event_routes(router, settings, repository, client)
    add_deletion_routes(router, settings, repository, client, authenticated, require_installation, available, no_store)
    return router

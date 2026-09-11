import httpx
from fastapi import APIRouter, HTTPException, Request, Response
from sqlalchemy.exc import SQLAlchemyError
from starlette.concurrency import run_in_threadpool

from .oidc import IdentityUnavailable, InvalidIdentity, ProviderKeys
from .provider_http import unique_json
from .repository import AccountRepository, ChallengeRejected
from .security_event_repository import SecurityEventRepository
from .security_event_verifier import GoogleRISCConfiguration, SecurityEventVerifier
from .settings import AccountAuthSettings


def add_security_event_routes(router: APIRouter, settings: AccountAuthSettings,
                              accounts: AccountRepository, client: httpx.AsyncClient):
    verifier = SecurityEventVerifier(settings, ProviderKeys(client), GoogleRISCConfiguration(client))
    events = SecurityEventRepository(accounts)

    def reject(status: int, detail: str):
        return HTTPException(status, detail, headers={"Cache-Control": "no-store"})

    async def receive(provider: str, request: Request):
        if provider not in settings.verification_providers:
            raise reject(503, "Security event receiver unavailable.")
        mime = request.headers.get("content-type", "").split(";", 1)[0].strip().lower()
        expected = "application/json" if provider == "apple" else "application/secevent+jwt"
        if mime != expected or request.headers.get("content-encoding", "identity").lower() != "identity":
            raise reject(415, "Unsupported security event media.")
        body = bytearray()
        async for chunk in request.stream():
            body.extend(chunk)
            if len(body) > 20480:
                raise reject(413, "Security event request too large.")
        try:
            if provider == "apple":
                envelope = unique_json(body)
                if not isinstance(envelope, dict) or set(envelope) != {"payload"}:
                    raise InvalidIdentity()
                token = envelope["payload"]
            else:
                token = body.decode("ascii")
            event = await verifier.verify(provider, token)
            await run_in_threadpool(events.apply, event)
        except (InvalidIdentity, ChallengeRejected, ValueError, TypeError):
            raise reject(400, "Invalid security event.") from None
        except (IdentityUnavailable, SQLAlchemyError):
            raise reject(503, "Security event processing unavailable.") from None
        return Response(status_code=200 if provider == "apple" else 202, headers={"Cache-Control": "no-store"})

    @router.post("/security-events/apple", status_code=200)
    async def apple(request: Request):
        return await receive("apple", request)

    @router.post("/security-events/google", status_code=202)
    async def google(request: Request):
        return await receive("google", request)

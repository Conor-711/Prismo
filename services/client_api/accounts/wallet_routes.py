from fastapi import Depends, HTTPException, Response
from sqlalchemy.exc import SQLAlchemyError

from .repository import ChallengeRejected, ChallengeThrottled
from .wallet_models import WalletBindingInput, WalletChallenge, WalletChallengeInput, WalletRegistration
from .wallet_repository import WalletConflict, WalletRepository


def add_wallet_routes(router, repository, authenticated, no_store):
    wallets = WalletRepository(repository)

    def run(operation):
        try:
            return operation()
        except ChallengeRejected:
            raise HTTPException(401, "Wallet proof expired or could not be verified.")
        except WalletConflict:
            raise HTTPException(409, "A different wallet is already linked. Restore the existing wallet.")
        except ChallengeThrottled:
            raise HTTPException(429, "Please wait before trying again.", headers={"Retry-After": "300"})
        except SQLAlchemyError:
            raise HTTPException(503, "Wallet service unavailable.")

    @router.get("/wallet", response_model=WalletRegistration)
    def registration(response: Response, session=Depends(authenticated)):
        no_store(response)
        return run(lambda: wallets.registration(session[0].id))

    @router.post("/wallet/challenges", response_model=WalletChallenge)
    def challenge(payload: WalletChallengeInput, response: Response, session=Depends(authenticated)):
        no_store(response)
        return run(lambda: wallets.challenge(session[0].id, session[1], payload.address))

    @router.put("/wallet", response_model=WalletRegistration)
    def bind(payload: WalletBindingInput, response: Response, session=Depends(authenticated)):
        no_store(response)
        return run(lambda: wallets.bind(session[0].id, session[1], payload.challengeId, payload.signature))

"""Rollback-only multi-connection SQL acceptance, never provider quotes or signatures."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from uuid import uuid4

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from .config import normalize_database_url
from .content_release.__main__ import publication_database_url
from .probe_equity_ledger import PROJECT, CHANGE, permissions, preparation_permissions, signing_permissions, project_database

PREPARE = text("""select intent_id::text,state,intent_version from public.bsmart_equity_prepare(
    cast(:account as uuid),cast(:id as uuid),:owner,0,cast(:preview as jsonb),
    cast(:material as jsonb),cast(:prepared as jsonb),:hash)""")


def synthetic_params(account, owner, intent_id, now):
    # SQL transaction boundary only. Deliberately not a cryptographically valid
    # CoW order, provider evidence, or an accepted authorization. Always rollback.
    expiry = (now + timedelta(minutes=2)).replace(microsecond=0)
    instrument = {"network": "Ethereum", "chainId": 1, "token": "0x" + "1" * 40,
                  "usdc": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "symbol": "ASTSx",
                  "assetId": str(uuid4()), "tokenVariant": "raw", "maxLeverage": 1}
    payload = {"ticker": "ASTS", "side": "buy", "amount": "1", "slippageBps": 50, "maxNetworkFeeBps": 100}
    fingerprint = uuid4().hex + uuid4().hex
    order = {"receiver": owner, "kind": "sell", "partiallyFillable": False, "feeAmount": "0",
             "sellAmount": "1000000", "buyAmount": "1", "validTo": int(expiry.timestamp())}
    prepared = {"schema": "cow_order_v1", "intentId": intent_id, "account": account, "intentVersion": 1,
                "owner": owner, "side": "buy", "instrument": instrument, "order": order, "domain": {},
                "orderUid": "0x" + uuid4().hex * 3 + uuid4().hex[:16], "orderDigest": "0x" + "a" * 64,
                "fingerprint": fingerprint, "expiresAt": expiry.isoformat()}
    material = {"version": 1, "account": account, "owner": owner, "input": payload,
                "instrument": instrument, "order": order, "domain": {}, "quote": {"verified": True},
                "expiresAt": int(expiry.timestamp()) * 1000}
    candidate = {"owner": owner, "receiver": owner, "executable": False, "providerVerified": True,
                 "fingerprint": fingerprint, "observedAt": now.isoformat(), "expiresAt": expiry.isoformat(),
                 "instrument": instrument, "inputAmountRaw": "1000000", "minimumOutputAmountRaw": "1"}
    preview = {"ticker": "ASTS", "side": "buy", "executionEnabled": False, "returnTransferImplemented": False,
               "gasCoverage": "unverified", "defaultSaleProceedsDestination": "hyperliquid_perps", "candidates": [candidate]}
    return {"account": account, "owner": owner, "id": intent_id, "hash": "b" * 64,
            "preview": json.dumps(preview), "material": json.dumps(material), "prepared": json.dumps(prepared)}


def rejected(connection, statement, params, code, message=None):
    savepoint = connection.begin_nested()
    try:
        connection.execute(statement, params)
    except Exception as error:
        original = getattr(error, "orig", None)
        actual = getattr(getattr(original, "diag", None), "message_primary", None)
        savepoint.rollback()
        if getattr(original, "sqlstate", None) != code or (message is not None and actual != message):
            raise RuntimeError("concurrent_write_unexpected_error") from None
    else:
        savepoint.rollback()
        raise RuntimeError("concurrent_write_not_rejected")


def concurrent_preparations(engine, handle, signing_exposure=False):
    with engine.connect() as connection:
        target = connection.execute(text("""select w.account_id::text,w.address from public.bsmart_wallets w
            join public.bsmart_feed_profiles p on p.account_id=w.account_id where p.handle=:handle"""),
            {"handle": handle.removeprefix("@").lower()}).one()
    ids = []
    with engine.connect() as first, engine.connect() as second:
        tx1, tx2 = first.begin(), second.begin()
        try:
            for connection in (first, second):
                # Rollback-only seed rows avoid the create RPC's account-wide
                # idempotency lock masking the distinct wallet reservation race.
                intent_id = str(uuid4())
                payload = {"ticker": "ASTS", "side": "buy", "amount": "1", "slippageBps": 50, "maxNetworkFeeBps": 100}
                connection.execute(text("""insert into public.bsmart_equity_intents
                    (id,client_intent_id,account_id,wallet_address,request_hash,input)
                    values(cast(:id as uuid),cast(:client as uuid),cast(:account as uuid),:owner,:hash,cast(:input as jsonb))"""),
                    {"id": intent_id, "client": str(uuid4()), "account": target.account_id,
                     "owner": target.address, "hash": "a" * 64, "input": json.dumps(payload)})
                ids.append(intent_id)
                connection.execute(text("set local role service_role"))
                connection.execute(text("set local lock_timeout='150ms'"))
            now = first.execute(text("select clock_timestamp()")).scalar_one()
            p1 = synthetic_params(target.account_id, target.address, ids[0], now)
            p2 = synthetic_params(target.account_id, target.address, ids[1], now)
            reserved = first.execute(PREPARE, p1).mappings().one()
            if reserved["state"] != "reserved":
                raise RuntimeError("first_reservation_failed")

            def contend():
                rejected(second, PREPARE, p2, "23505", "wallet_activity_in_progress")
                row = second.execute(text("select version,state,preview from public.bsmart_equity_intents where id=cast(:id as uuid)"), p2).one()
                if row.version != 0 or row.state != "draft" or row.preview is not None:
                    raise RuntimeError("failed_quote_not_rolled_back")
                # Existing wallet-first RPCs wait briefly, then fail at the same
                # lock. This is not mistaken for an accepted withdrawal.
                params = {**p2, "nonce": int(now.timestamp()) * 1000, "expiry": (now + timedelta(minutes=2)).isoformat()}
                rejected(second, text("""select public.bsmart_withdrawal_reserve(cast(:account as uuid),
                    cast(:id as uuid),:owner,:owner,'1','',:nonce)"""), params, "55P03")
                rejected(second, text("""select public.bsmart_across_withdrawal_reserve(cast(:account as uuid),
                    cast(:id as uuid),:owner,:owner,'perps',1000000,'{}',cast(:expiry as timestamptz),'123')"""), params, "55P03")
                return True

            with ThreadPoolExecutor(max_workers=1) as pool:
                if not pool.submit(contend).result(timeout=15):
                    raise RuntimeError("concurrent_probe_failed")
            tx1.rollback()
            result = second.execute(PREPARE, p2).mappings().one()
            retry = second.execute(PREPARE, p2).mappings().one()
            if result != retry or result["state"] != "reserved" or result["intent_version"] != 1:
                raise RuntimeError("release_retry_failed")
            if signing_exposure:
                start = text("""select state,signing_started_at from public.bsmart_equity_signing_start(
                    cast(:account as uuid),cast(:id as uuid),:owner,1,:hash)""")
                exposed = second.execute(start, p2).mappings().one()
                if exposed["state"] != "signing" or exposed["signing_started_at"] is None or second.execute(start, p2).mappings().one() != exposed:
                    raise RuntimeError("signing_exposure_retry_failed")
                rejected(second, CHANGE, {**p2, "version": 1, "action": "cancel"}, "22023", "preparation_conflict")
            else:
                second.execute(CHANGE, {**p2, "version": 1, "action": "cancel"})
        finally:
            if tx1.is_active:
                tx1.rollback()
            if tx2.is_active:
                tx2.rollback()
    with engine.connect() as connection:
        for table, column in (("bsmart_equity_intents", "id"), ("bsmart_equity_preparations", "intent_id"),
                              ("bsmart_equity_legs", "intent_id"), ("bsmart_withdrawals", "id"), ("bsmart_across_withdrawals", "id")):
            if connection.execute(text(f"select count(*) from public.{table} where {column}=any(cast(:ids as uuid[]))"), {"ids": ids}).scalar_one():
                raise RuntimeError("probe_rows_not_rolled_back")
    return {"concurrentReservationAcceptanceTest": True, "failedNestedQuoteRollbackVerified": True,
            "legacyReserveSharedLockVerified": True, "afterRollbackReservationVerified": True,
            "immutableRetryVerified": True, "allProbeRowsRolledBack": True, "syntheticSQLBoundaryOnly": True,
            "signingExposureRollbackVerified": signing_exposure}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rollback-writes", action="store_true", help="Required explicit opt-in; briefly reserves an existing wallet inside rollback-only transactions")
    parser.add_argument("--signing-exposure", action="store_true", help="Also test migration 007 exposure/retry/cancel guard inside rollback")
    parser.add_argument("--handle", default="imconnorzhang")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    engine = None
    stage = "configuration"
    try:
        if not args.rollback_writes:
            raise RuntimeError("explicit_rollback_write_opt_in_required")
        url = make_url(normalize_database_url(publication_database_url()))
        if not project_database(url):
            raise RuntimeError("wrong_project")
        engine = create_engine(url, connect_args={"connect_timeout": 10, "prepare_threshold": None,
            "options": "-c statement_timeout=10000 -c lock_timeout=5000"})
        stage = "permissions"
        with engine.connect() as connection:
            permissions(connection)
            preparation_permissions(connection)
            if args.signing_exposure:
                signing_permissions(connection)
        report = {"project": PROJECT, "observedAt": datetime.now(timezone.utc).isoformat(), "ddlExecuted": False,
                  "providerQuoteTest": False, "cryptoValidationTest": False, "authenticatedHTTPTest": False,
                  "fundsMoved": False, "ordersSubmitted": False, "signaturesCreated": False, "executionEnabled": False}
        stage = "rollback_write_probe"
        report.update(concurrent_preparations(engine, args.handle, args.signing_exposure))
        if args.output:
            args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report), flush=True)
    except Exception as error:
        print(json.dumps({"errorType": type(error).__name__, "stage": stage,
            "sqlstate": getattr(getattr(error, "orig", None), "sqlstate", None),
            "message": "Preparation probe failed; credentials and account data suppressed"}), flush=True)
        raise SystemExit(1) from None
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    main()

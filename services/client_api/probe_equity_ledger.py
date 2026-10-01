"""Verify migrated equity ledger; optional controlled draft tests, never funds or orders."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
from uuid import uuid4

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from .config import normalize_database_url
from .content_release.__main__ import publication_database_url

PROJECT = "dzyitinagewdfkzjkuiz"
FUNCTIONS = (
    "bsmart_equity_intent_create(uuid,text,uuid,jsonb,text)",
    "bsmart_equity_intent_change(uuid,uuid,text,integer,text,jsonb)",
    "bsmart_equity_leg_claim(uuid,integer)",
    "bsmart_equity_leg_observe(uuid,integer,text,text)",
)
CREATE = text("""select id::text,state,version from public.bsmart_equity_intent_create(
    cast(:account as uuid),:owner,cast(:client as uuid),cast(:input as jsonb),:hash)""")
CHANGE = text("""select id::text,state,version from public.bsmart_equity_intent_change(
    cast(:account as uuid),cast(:id as uuid),:owner,:version,:action,null)""")
QUOTE = text("""select id::text,state,version,quote_expires_at from public.bsmart_equity_intent_change(
    cast(:account as uuid),cast(:id as uuid),:owner,:version,'quote',cast(:preview as jsonb))""")


def request_params(account, owner, client_id, payload):
    canonical = {"schema": 1, "account": account, "owner": owner,
                 "ticker": payload["ticker"], "side": payload["side"], "amount": payload["amount"],
                 "slippageBps": payload["slippageBps"], "maxNetworkFeeBps": payload["maxNetworkFeeBps"],
                 "minimumOutput": payload.get("minimumOutput")}
    return {"account": account, "owner": owner, "client": client_id, "input": json.dumps(payload),
            "hash": hashlib.sha256(json.dumps(canonical, separators=(",", ":")).encode()).hexdigest()}


def project_database(url):
    host = (url.host or "").lower()
    return url.database == "postgres" and (host == f"db.{PROJECT}.supabase.co" or
        (host.endswith(".pooler.supabase.com") and url.username == f"postgres.{PROJECT}"))


def permissions(connection):
    tables = connection.execute(text("""select relname,relrowsecurity from pg_class
        where oid in (to_regclass('public.bsmart_equity_intents'),to_regclass('public.bsmart_equity_legs'))""")).all()
    if len(tables) != 2 or not all(row.relrowsecurity for row in tables):
        raise RuntimeError("ledger_rls_missing")
    for name in FUNCTIONS:
        values = connection.execute(text("""select to_regprocedure(:name) is not null as present,
            has_function_privilege('service_role',:name,'EXECUTE') as service,
            has_function_privilege('authenticated',:name,'EXECUTE') as authenticated,
            has_function_privilege('anon',:name,'EXECUTE') as anon"""), {"name": "public." + name}).one()
        if not values.present or not values.service or values.authenticated or values.anon:
            raise RuntimeError("rpc_privileges_invalid")
        protected = connection.execute(text("""select prosecdef and
            'search_path=""'=any(proconfig) as protected from pg_proc where oid=to_regprocedure(:name)"""),
            {"name": "public." + name}).scalar_one()
        if not protected:
            raise RuntimeError("rpc_search_path_unprotected")
    for table in ("bsmart_equity_intents", "bsmart_equity_legs"):
        for role in ("authenticated", "anon", "service_role"):
            writable = connection.execute(text("select has_table_privilege(:role,:table,'INSERT,UPDATE,DELETE')"),
                {"role": role, "table": "public." + table}).scalar_one()
            if writable:
                raise RuntimeError("direct_mutation_grant")
    for column in ("lease_id", "leased_until", "evidence_hash", "request_hash"):
        if connection.execute(text("select has_column_privilege('authenticated','public.bsmart_equity_legs',:column,'SELECT')"),
                              {"column": column}).scalar_one():
            raise RuntimeError("private_leg_columns_readable")
    if not connection.execute(text("select has_column_privilege('authenticated','public.bsmart_equity_legs','provider_id','SELECT')")).scalar_one():
        raise RuntimeError("safe_leg_columns_unreadable")


def preparation_permissions(connection):
    """Read-only deployment check; never retrieves orders or signatures."""
    table = "public.bsmart_equity_preparations"
    if not connection.execute(text("select coalesce((select relrowsecurity from pg_class where oid=to_regclass(:name)),false)"),
                              {"name": table}).scalar_one():
        raise RuntimeError("preparation_migration_missing")
    for role in ("anon", "authenticated", "service_role"):
        if connection.execute(text("select has_table_privilege(:role,:table,'INSERT,UPDATE,DELETE')"),
                              {"role": role, "table": table}).scalar_one():
            raise RuntimeError("preparation_direct_write_grant")
        readable = connection.execute(text("select has_table_privilege(:role,:table,'SELECT')"),
                                      {"role": role, "table": table}).scalar_one()
        if readable != (role == "service_role"):
            raise RuntimeError("preparation_private_read_grant")
    for role in ("anon", "authenticated"):
        for column in ("material", "prepared", "signature", "authorization_hash", "preparation_hash"):
            if connection.execute(text("select has_column_privilege(:role,:table,:column,'SELECT')"),
                {"role": role, "table": table, "column": column}).scalar_one():
                raise RuntimeError("preparation_private_column_grant")
    for name in ("bsmart_equity_prepare(uuid,uuid,text,integer,jsonb,jsonb,jsonb,text)",
                 "bsmart_equity_authorize_prepared(uuid,uuid,text,integer,text,text,text)"):
        for role in ("service_role", "anon", "authenticated"):
            allowed = connection.execute(text("select has_function_privilege(:role,:name,'EXECUTE')"),
                                         {"role": role, "name": "public." + name}).scalar_one()
            if allowed != (role == "service_role"):
                raise RuntimeError("preparation_rpc_grant")
        if not connection.execute(text("""select prosecdef and 'search_path=""'=any(proconfig)
            from pg_proc where oid=to_regprocedure(:name)"""), {"name": "public." + name}).scalar_one():
            raise RuntimeError("preparation_rpc_unprotected")
    for table_name, trigger in (("bsmart_withdrawals", "bsmart_withdrawal_activity_guard"),
        ("bsmart_across_withdrawals", "bsmart_across_activity_guard"),
        ("bsmart_equity_preparations", "bsmart_equity_preparation_guard"),
        ("bsmart_equity_intents", "bsmart_equity_prepared_intent_guard"),
        ("bsmart_equity_legs", "bsmart_equity_execution_closed")):
        if not connection.execute(text("""select exists(select 1 from pg_trigger
            where tgrelid=to_regclass(:table) and tgname=:trigger and not tgisinternal and tgenabled='O')"""),
            {"table": "public." + table_name, "trigger": trigger}).scalar_one():
            raise RuntimeError("preparation_trigger_missing")
    states = dict(connection.execute(text("select state,count(*) from public.bsmart_equity_preparations group by state")).all())
    return {"preparationSchemaVerified": True, "preparationStates": states,
            "signingEnabled": False, "concurrentReservationAcceptanceTest": False}


def preparation_lock_probe(engine):
    """Two read-only transactions, synthetic owner; no user rows or funds."""
    params = {"owner": "0x" + uuid4().hex + uuid4().hex[:8], "id": str(uuid4())}
    guard = text("select public.bsmart_wallet_activity_assert(:owner,'equity',cast(:id as uuid))")

    def contender():
        try:
            with engine.begin() as connection:
                connection.execute(text("set transaction read only"))
                connection.execute(guard, params)
        except Exception as error:
            original = getattr(error, "orig", None)
            if getattr(original, "sqlstate", None) == "23505" and getattr(
                getattr(original, "diag", None), "message_primary", None) == "wallet_activity_in_progress":
                return True
            raise RuntimeError("shared_lock_probe_unexpected_error") from None
        raise RuntimeError("shared_lock_contention_not_rejected")

    with engine.begin() as connection:
        connection.execute(text("set transaction read only"))
        # Same key as the old ordinary/Across reserve RPCs. Reentrant guard must
        # pass, while another connection fails closed without waiting on a row.
        connection.execute(text("select pg_advisory_xact_lock(hashtextextended(:owner,0))"), params)
        connection.execute(guard, params)
        with ThreadPoolExecutor(max_workers=1) as pool:
            if not pool.submit(contender).result(timeout=15):
                raise RuntimeError("shared_lock_probe_failed")
    with engine.begin() as connection:
        connection.execute(text("set transaction read only"))
        connection.execute(guard, params)
    return {"concurrentSharedLockTest": True, "sharedLockUsesLegacyKey": True,
            "sharedLockFailClosed": True, "sharedLockReleaseVerified": True}


def signing_permissions(connection):
    """Read-only check of signing exposure migration, never private payloads."""
    name = "public.bsmart_equity_signing_start(uuid,uuid,text,integer,text)"
    for role in ("service_role", "anon", "authenticated"):
        if connection.execute(text("select has_function_privilege(:role,:name,'EXECUTE')"),
            {"role": role, "name": name}).scalar_one() != (role == "service_role"):
            raise RuntimeError("signing_rpc_grant")
    if not connection.execute(text("""select prosecdef and 'search_path=""'=any(proconfig)
        from pg_proc where oid=to_regprocedure(:name)"""), {"name": name}).scalar_one():
        raise RuntimeError("signing_rpc_unprotected")
    for role in ("anon", "authenticated"):
        if connection.execute(text("""select has_column_privilege(:role,
            'public.bsmart_equity_preparations','signing_started_at','SELECT')"""), {"role": role}).scalar_one():
            raise RuntimeError("signing_private_column_grant")
    index = connection.execute(text("select pg_get_indexdef(to_regclass('public.bsmart_one_equity_reservation_per_wallet'))")).scalar_one()
    if not index or "signing" not in index:
        raise RuntimeError("signing_wallet_index_missing")
    for name in ("bsmart_wallet_activity_assert(text,text,uuid)", "bsmart_equity_prepared_intent_guard()",
                 "bsmart_equity_preparation_guard()", "bsmart_equity_authorize_prepared(uuid,uuid,text,integer,text,text,text)"):
        if not connection.execute(text("select position('signing' in prosrc)>0 from pg_proc where oid=to_regprocedure(:name)"),
            {"name": "public." + name}).scalar_one():
            raise RuntimeError("signing_guard_missing")
    return {"signingExposureSchemaVerified": True, "signingHTTPEnabled": False}


def expect_error(connection, statement, params, message):
    savepoint = connection.begin_nested()
    try:
        connection.execute(statement, params)
    except Exception as error:
        original = getattr(error, "orig", None)
        actual = getattr(getattr(original, "diag", None), "message_primary", None)
        savepoint.rollback()
        if actual != message:
            raise RuntimeError("unexpected_database_error") from None
    else:
        savepoint.rollback()
        raise RuntimeError("expected_conflict_missing")


def preview_transaction(connection, change):
    # Synthetic SQL boundary fixtures never leave this savepoint or call a provider.
    savepoint = connection.begin_nested()
    try:
        now = connection.execute(text("select clock_timestamp()")).scalar_one()
        candidate = {"owner": change["owner"], "receiver": change["owner"], "executable": False,
                     "fingerprint": "a" * 64, "observedAt": now.isoformat(),
                     "expiresAt": (now + timedelta(minutes=2)).isoformat()}
        later = {**candidate, "fingerprint": "b" * 64,
                 "expiresAt": (now + timedelta(minutes=3)).isoformat()}
        preview = {"ticker": "ASTS", "side": "buy", "executionEnabled": False,
                   "returnTransferImplemented": False, "gasCoverage": "unverified",
                   "defaultSaleProceedsDestination": "hyperliquid_perps", "candidates": [candidate, later]}

        def params(value):
            return {**change, "preview": json.dumps(value)}

        for patch in ({"executionEnabled": True}, {"returnTransferImplemented": True},
                      {"gasCoverage": "sponsored"}, {"ticker": "SPY"}, {"candidates": []},
                      {"candidates": [{**candidate, "receiver": "0x" + "1" * 40}]},
                      {"candidates": [{**candidate, "executable": True}]},
                      {"candidates": [{**candidate, "expiresAt": (now - timedelta(seconds=1)).isoformat()}]},
                      {"candidates": [{**candidate, "observedAt": (now - timedelta(seconds=31)).isoformat()}]}):
            expect_error(connection, QUOTE, params({**preview, **patch}), "invalid_saved_preview")
        quoted = connection.execute(QUOTE, params(preview)).mappings().one()
        if quoted["state"] != "quoted" or quoted["version"] != 1 or quoted["quote_expires_at"] != now + timedelta(minutes=2):
            raise RuntimeError("preview_cas_failed")
        retry = connection.execute(QUOTE, params(preview)).mappings().one()
        if retry["version"] != 1:
            raise RuntimeError("preview_retry_failed")
        expect_error(connection, QUOTE, params({**preview, "candidates": [later]}), "intent_version_conflict")
        expect_error(connection, CHANGE, change, "intent_version_conflict")
        connection.execute(CHANGE, {**change, "version": 1})
        expect_error(connection, QUOTE, {**params(preview), "version": 2}, "intent_state_conflict")
    finally:
        savepoint.rollback()


def controlled_draft(engine, handle):
    with engine.connect() as connection:
        target = connection.execute(text("""select w.account_id::text,w.address from public.bsmart_wallets w
            join public.bsmart_feed_profiles p on p.account_id=w.account_id where p.handle=:handle"""),
            {"handle": handle.removeprefix("@").lower()}).one()
    client_id = str(uuid4())
    payload = {"ticker": "ASTS", "side": "buy", "amount": "1", "slippageBps": 50, "maxNetworkFeeBps": 100}
    params = request_params(target.account_id, target.address, client_id, payload)

    def create():
        with engine.begin() as connection:
            connection.execute(text("set local role service_role"))
            return connection.execute(CREATE, params).mappings().one()["id"]

    final_state = None
    try:
        with ThreadPoolExecutor(max_workers=3) as pool:
            ids = list(pool.map(lambda _: create(), range(3)))
        if len(set(ids)) != 1:
            raise RuntimeError("concurrent_duplicate_drafts")
        intent_id = ids[0]
        with engine.begin() as connection:
            connection.execute(text("set local role service_role"))
            altered = {**params, "input": json.dumps({**payload, "amount": "2"})}
            expect_error(connection, CREATE, altered, "intent_idempotency_conflict")
            change = {"account": target.account_id, "owner": target.address, "id": intent_id, "version": 0, "action": "cancel"}
            expect_error(connection, CHANGE, {**change, "account": str(uuid4())}, "intent_not_found")
            expect_error(connection, CHANGE, {**change, "owner": "0x" + "1" * 40}, "wallet_changed")
            expect_error(connection, CHANGE, {**change, "version": 1}, "intent_version_conflict")
            preview_transaction(connection, change)
            cancelled = connection.execute(CHANGE, change).mappings().one()
            again = connection.execute(CHANGE, change).mappings().one()
            if cancelled["state"] != "cancelled" or again["version"] != 1:
                raise RuntimeError("cancel_retry_failed")
            expect_error(connection, CHANGE, {**change, "version": 1, "action": "quote"}, "intent_state_conflict")
            replay = connection.execute(CREATE, params).mappings().one()
            if replay["id"] != intent_id or replay["state"] != "cancelled":
                raise RuntimeError("cancelled_intent_recreated")

        # Database role simulation, not an actual authenticated App/HTTP test.
        for subject, expected in ((target.account_id, 1), (str(uuid4()), 0)):
            with engine.begin() as connection:
                connection.execute(text("set local role authenticated"))
                connection.execute(text("select set_config('request.jwt.claim.sub',:subject,true)"), {"subject": subject})
                connection.execute(text("select set_config('request.jwt.claims',:claims,true)"), {"claims": json.dumps({"sub": subject})})
                count = connection.execute(text("select count(*) from public.bsmart_equity_intents where id=cast(:id as uuid)"), {"id": intent_id}).scalar_one()
                if count != expected:
                    raise RuntimeError("rls_identity_leak")
    finally:
        # Clean up only this probe's known ID; retain a cancelled audit row.
        with engine.begin() as connection:
            connection.execute(text("set local role service_role"))
            current = connection.execute(text("""select id::text,state,version from public.bsmart_equity_intents
                where account_id=cast(:account as uuid) and client_intent_id=cast(:client as uuid)"""), params).mappings().one_or_none()
            if current:
                if current["state"] in ("draft", "quoted"):
                    current = connection.execute(CHANGE, {**params, "id": current["id"], "version": current["version"], "action": "cancel"}).mappings().one()
                final_state = current["state"]
    if final_state != "cancelled":
        raise RuntimeError("probe_cleanup_incomplete")
    return {"concurrentCreateDeduplicated": True, "differentInputRejected": True,
            "versionCASVerified": True, "cancelRetryVerified": True, "postCancelQuoteRejected": True,
            "crossAccountMutationRejected": True, "ownerMismatchRejected": True,
            "syntheticPreviewRollbackVerified": True, "previewExpiryGuardsVerified": True,
            "accountRLSRoleSimulationVerified": True, "probeFinalState": final_state, "probeClientIntentId": client_id}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Create one controlled draft and leave it cancelled")
    parser.add_argument("--preparations", action="store_true", help="Read-only check of preparation migration and shared guards")
    parser.add_argument("--signing-exposure", action="store_true", help="Also verify migration 007; requires --preparations")
    parser.add_argument("--handle", default="imconnorzhang")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    engine = None
    try:
        if args.preparations and args.apply:
            raise RuntimeError("preparation_probe_is_read_only")
        if args.signing_exposure and not args.preparations:
            raise RuntimeError("signing_probe_requires_preparations")
        url = make_url(normalize_database_url(publication_database_url()))
        if not project_database(url):
            raise RuntimeError("wrong_project")
        engine = create_engine(url, connect_args={"connect_timeout": 10, "prepare_threshold": None,
            "options": "-c statement_timeout=10000 -c lock_timeout=5000"})
        with engine.connect() as connection:
            permissions(connection)
            preparations = preparation_permissions(connection) if args.preparations else {}
            if args.signing_exposure:
                preparations.update(signing_permissions(connection))
        report = {"project": PROJECT, "observedAt": datetime.now(timezone.utc).isoformat(),
                  "migrationPermissionsVerified": True, "ddlExecuted": False, "providerQuoteTest": False,
                  "authenticatedHTTPTest": False, "fundsMoved": False, "ordersSubmitted": False, "executionEnabled": False}
        report.update(preparations)
        if args.preparations:
            report.update(preparation_lock_probe(engine))
        if args.apply:
            report.update(controlled_draft(engine, args.handle))
        if args.output:
            args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report), flush=True)
    except Exception as error:
        print(json.dumps({"errorType": type(error).__name__, "message": "Equity probe failed; credentials and account data suppressed"}), flush=True)
        raise SystemExit(1) from None
    finally:
        if engine is not None:
            engine.dispose()


if __name__ == "__main__":
    main()

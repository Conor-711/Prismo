"""Per-user event ledger and three daily APNs digest slots; schema is manual."""
import json
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import text

SHANGHAI = ZoneInfo("Asia/Shanghai")
SLOT_HOURS = (8, 18, 22)
SLOT_GRACE = timedelta(minutes=30)

MATCHES = """(
    (d.notify_authors and ((q.event_kind='opinion' and lower(q.actor_id)=any(d.followed_author_ids))
        or (q.event_kind='movement' and lower(q.actor_id)=any(d.followed_money_ids))))
    or (d.notify_tickers and q.ticker=any(d.followed_tickers))
    or (d.notify_holdings and q.ticker=any(d.held_tickers))
)"""


def due_slot(now=None):
    now = (now or datetime.now(timezone.utc)).astimezone(SHANGHAI)
    for hour in SLOT_HOURS:
        slot = now.replace(hour=hour, minute=0, second=0, microsecond=0)
        if slot <= now < slot + SLOT_GRACE:
            return slot.astimezone(timezone.utc)
    return None


def enqueue(session, revision, events):
    if not events:
        return 0
    result = session.execute(text("""
        with events as (
            select * from jsonb_to_recordset(cast(:events as jsonb)) as e(
                event_kind text, event_id uuid, actor_id text, ticker text, actor_name text)
        ), matched as (
            select distinct d.user_id,e.event_kind,e.event_id,e.actor_id,e.ticker,e.actor_name
            from events e join bsmart_push_devices d on d.enabled
                and d.updated_at > now() - interval '30 days'
            where (d.notify_authors and (
                    (e.event_kind='opinion' and lower(e.actor_id)=any(d.followed_author_ids)) or
                    (e.event_kind='movement' and lower(e.actor_id)=any(d.followed_money_ids))))
               or (d.notify_tickers and e.ticker=any(d.followed_tickers))
               or (d.notify_holdings and e.ticker=any(d.held_tickers))
        )
        insert into bsmart_interest_push_events
            (user_id,event_kind,event_id,actor_id,ticker,actor_name)
        select user_id,event_kind,event_id,actor_id,ticker,actor_name from matched
        on conflict (user_id,event_kind,event_id) do nothing
    """), {"events": json.dumps(events, ensure_ascii=False)})
    return result.rowcount


def prepare_slot(engine, slot):
    """Atomically reserve at most one batch per user in a fixed UTC+8 slot."""
    with engine.begin() as db:
        db.execute(text("select pg_advisory_xact_lock(721534916)"))
        # A server outage before dispatch defers unsent events to the next slot.
        db.execute(text("""
            update bsmart_interest_push_events q set state='pending',slot_at=null
            where state='batched' and exists (
                select 1 from bsmart_interest_push_batches b
                where b.user_id=q.user_id and b.slot_at=q.slot_at and b.state='pending'
                    and b.slot_at < :slot)
        """), {"slot": slot})
        db.execute(text("""
            update bsmart_interest_push_batches set state='skipped'
            where state='pending' and slot_at < :slot
        """), {"slot": slot})
        db.execute(text(f"""
            update bsmart_interest_push_events q set state='skipped'
            where q.state='pending' and q.created_at <= :slot and not exists (
                select 1 from bsmart_push_devices d where d.user_id=q.user_id and d.enabled
                    and d.updated_at > now()-interval '30 days' and {MATCHES})
        """), {"slot": slot})
        rows = db.execute(text(f"""
            with eligible as (
                select distinct q.user_id,q.event_kind,q.event_id,d.id as device_id,d.updated_at
                from bsmart_interest_push_events q join bsmart_push_devices d on d.user_id=q.user_id
                where q.state='pending' and q.created_at <= :slot and d.enabled
                    and d.updated_at > now()-interval '30 days' and {MATCHES}
            ), counts as (
                select user_id,count(distinct (event_kind,event_id)) as item_count from eligible group by user_id
            ), preferred as (
                select distinct on (user_id) user_id,device_id from eligible
                order by user_id,updated_at desc,device_id
            )
            insert into bsmart_interest_push_batches(user_id,slot_at,device_id,item_count)
            select c.user_id,:slot,p.device_id,c.item_count from counts c join preferred p using(user_id)
            on conflict(user_id,slot_at) do nothing returning user_id
        """), {"slot": slot}).fetchall()
        users = [str(row[0]) for row in rows]
        if users:
            db.execute(text(f"""
                update bsmart_interest_push_events q set state='batched',slot_at=:slot
                where q.user_id=any(cast(:users as uuid[])) and q.state='pending'
                    and q.created_at <= :slot and exists (
                        select 1 from bsmart_push_devices d where d.user_id=q.user_id and d.enabled
                            and d.updated_at > now()-interval '30 days' and {MATCHES})
            """), {"slot": slot, "users": users})
        return len(users)


def claim(engine, now=None):
    now = now or datetime.now(timezone.utc)
    with engine.begin() as db:
        # Never reclaim a sending batch: a lost APNs response must not produce a duplicate.
        db.execute(text(f"""
            update bsmart_interest_push_batches b set state='skipped'
            where b.state='pending' and b.slot_at + interval '30 minutes' > :now and not exists (
                select 1 from bsmart_push_devices d where d.id=b.device_id and d.user_id=b.user_id
                    and d.enabled and d.updated_at > now()-interval '30 days' and exists (
                        select 1 from bsmart_interest_push_events q
                        where q.user_id=b.user_id and q.slot_at=b.slot_at and {MATCHES}))
        """), {"now": now})
        row = db.execute(text("""
            select b.*,d.apns_token,d.environment,d.locale
            from bsmart_interest_push_batches b join bsmart_push_devices d on d.id=b.device_id
            where b.state='pending' and b.slot_at <= :now
                and b.slot_at + interval '30 minutes' > :now and d.enabled and d.user_id=b.user_id
            order by b.slot_at,b.user_id limit 1 for update of b skip locked
        """), {"now": now}).mappings().first()
        if not row:
            return None
        delivery = dict(row)
        db.execute(text("""
            update bsmart_interest_push_batches set state='sending',attempts=1
            where user_id=:user_id and slot_at=:slot_at and state='pending'
        """), delivery)
        return delivery


def complete(engine, delivery, state, status, invalid_token=False):
    with engine.begin() as db:
        result = db.execute(text("""
            update bsmart_interest_push_batches set state=:state,last_status=:status
            where user_id=:user_id and slot_at=:slot_at and state='sending'
        """), {**delivery, "state": state, "status": status})
        if invalid_token and result.rowcount:
            db.execute(text("""update bsmart_push_devices set enabled=false
                where id=:device_id and user_id=:user_id and apns_token=:apns_token and environment=:environment
            """), delivery)

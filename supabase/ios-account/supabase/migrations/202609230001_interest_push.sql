-- Apply manually to the native iOS Supabase project after 202609160001_content_notifications.sql.
begin;

alter table public.bsmart_push_devices
    add column followed_author_ids text[] not null default '{}',
    add column followed_money_ids text[] not null default '{}',
    add column followed_tickers text[] not null default '{}',
    add column held_tickers text[] not null default '{}',
    add column notify_authors boolean not null default true,
    add column notify_tickers boolean not null default true,
    add column notify_holdings boolean not null default true;

create table public.bsmart_interest_push_events (
    user_id uuid not null references auth.users(id) on delete cascade,
    event_kind text not null check (event_kind in ('opinion', 'movement')),
    event_id uuid not null,
    actor_id text not null,
    ticker text not null,
    actor_name text not null,
    state text not null default 'pending' check (state in ('pending', 'batched', 'skipped')),
    created_at timestamptz not null default now(),
    slot_at timestamptz,
    primary key (user_id, event_kind, event_id)
);
create index bsmart_interest_push_events_pending on public.bsmart_interest_push_events(state, created_at);
create table public.bsmart_interest_push_batches (
    user_id uuid not null references auth.users(id) on delete cascade,
    slot_at timestamptz not null,
    constraint bsmart_interest_slot_time check (
        extract(hour from slot_at at time zone 'Asia/Shanghai') in (8,18,22)
        and extract(minute from slot_at at time zone 'Asia/Shanghai') = 0
        and extract(second from slot_at at time zone 'Asia/Shanghai') = 0
    ),
    device_id uuid not null references public.bsmart_push_devices(id) on delete cascade,
    item_count integer not null check (item_count > 0),
    state text not null default 'pending' check (state in ('pending', 'sending', 'accepted', 'failed', 'skipped')),
    attempts integer not null default 0 check (attempts between 0 and 1),
    apns_id uuid not null default gen_random_uuid(),
    last_status integer,
    primary key (user_id, slot_at)
);
create index bsmart_interest_push_batches_pending on public.bsmart_interest_push_batches(state, slot_at);
alter table public.bsmart_interest_push_events enable row level security;
alter table public.bsmart_interest_push_batches enable row level security;
revoke all on public.bsmart_interest_push_events, public.bsmart_interest_push_batches
    from public, anon, authenticated, service_role;

create function public.bsmart_set_push_interests(
    p_user uuid, p_installation uuid, p_authors text[], p_money text[],
    p_tickers text[], p_holdings text[], p_notify_authors boolean,
    p_notify_tickers boolean, p_notify_holdings boolean
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    interest text;
begin
    if p_authors is null or p_money is null or p_tickers is null or p_holdings is null
       or p_notify_authors is null or p_notify_tickers is null or p_notify_holdings is null
       or pg_catalog.cardinality(p_authors) > 150 or pg_catalog.cardinality(p_money) > 150
       or pg_catalog.cardinality(p_tickers) > 150 or pg_catalog.cardinality(p_holdings) > 150 then
        return false;
    end if;
    foreach interest in array p_authors || p_money || p_tickers || p_holdings loop
        if interest is null or pg_catalog.length(interest) not between 1 and 160
           or interest ~ '[[:cntrl:]]' then return false; end if;
    end loop;
    update public.bsmart_push_devices set
        followed_author_ids=p_authors, followed_money_ids=p_money,
        followed_tickers=p_tickers, held_tickers=p_holdings,
        notify_authors=p_notify_authors, notify_tickers=p_notify_tickers,
        notify_holdings=p_notify_holdings, updated_at=now()
    where user_id=p_user and installation_id=p_installation and enabled;
    return found;
end;
$$;
revoke all on function public.bsmart_set_push_interests(uuid,uuid,text[],text[],text[],text[],boolean,boolean,boolean)
    from public, anon, authenticated;
grant execute on function public.bsmart_set_push_interests(uuid,uuid,text[],text[],text[],text[],boolean,boolean,boolean)
    to service_role;

-- A token or installation transferred to another account must not inherit its interests.
create or replace function public.bsmart_register_push(p_user uuid, p_installation uuid, p_token text,
    p_environment text, p_locale text, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_installation::text, 0));
    update public.bsmart_push_devices set enabled = false where installation_id = p_installation;
    insert into public.bsmart_push_devices(installation_id,user_id,apns_token,environment,locale,enabled)
        values(p_installation,p_user,p_token,p_environment,p_locale,p_enabled)
        on conflict(environment,apns_token) do update set
            followed_author_ids=case when public.bsmart_push_devices.user_id=excluded.user_id
                then public.bsmart_push_devices.followed_author_ids else '{}'::text[] end,
            followed_money_ids=case when public.bsmart_push_devices.user_id=excluded.user_id
                then public.bsmart_push_devices.followed_money_ids else '{}'::text[] end,
            followed_tickers=case when public.bsmart_push_devices.user_id=excluded.user_id
                then public.bsmart_push_devices.followed_tickers else '{}'::text[] end,
            held_tickers=case when public.bsmart_push_devices.user_id=excluded.user_id
                then public.bsmart_push_devices.held_tickers else '{}'::text[] end,
            installation_id=excluded.installation_id,user_id=excluded.user_id,
            locale=excluded.locale,enabled=excluded.enabled,updated_at=now();
end;
$$;
commit;

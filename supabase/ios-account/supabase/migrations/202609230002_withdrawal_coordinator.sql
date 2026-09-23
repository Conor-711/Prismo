-- Run on the bSmart account project before enabling coordinated withdrawals.
begin;

create table public.bsmart_withdrawals (
    id uuid primary key,
    account_id uuid not null references auth.users(id) on delete cascade,
    wallet_address text not null,
    recipient text not null,
    amount text not null,
    source_dex text not null check (source_dex in ('', 'spot')),
    nonce bigint not null,
    state text not null check (state in
        ('reserved', 'submitting', 'accepted', 'uncertain', 'core_debited', 'rejected', 'cancelled', 'expired')),
    response jsonb,
    ledger_hash text,
    ledger_time bigint,
    created_at timestamptz not null default clock_timestamp(),
    updated_at timestamptz not null default clock_timestamp(),
    expires_at timestamptz not null,
    unique (wallet_address, nonce),
    check (wallet_address ~ '^0x[0-9a-f]{40}$'),
    check (recipient ~ '^0x[0-9a-f]{40}$'),
    check (amount ~ '^(0|[1-9][0-9]{0,12})(\.[0-9]{1,6})?$' and amount::numeric > 0),
    check (nonce > 0)
);
create unique index bsmart_one_pending_withdrawal_per_wallet on public.bsmart_withdrawals(wallet_address)
    where state in ('reserved', 'submitting', 'uncertain');
create index bsmart_withdrawals_account_history on public.bsmart_withdrawals(account_id, created_at desc);
alter table public.bsmart_withdrawals enable row level security;
revoke all on public.bsmart_withdrawals from public, anon, authenticated;
grant select, insert, update on public.bsmart_withdrawals to service_role;

create function public.bsmart_withdrawal_reserve(
    p_account uuid, p_id uuid, p_wallet text, p_recipient text, p_amount text, p_source text, p_nonce bigint)
returns public.bsmart_withdrawals language plpgsql security definer set search_path = '' as $$
declare result public.bsmart_withdrawals;
begin
    if p_account is null or p_id is null or p_wallet is null or p_recipient is null or p_amount is null
       or p_source not in ('', 'spot') or p_wallet !~ '^0x[0-9a-f]{40}$'
       or p_recipient !~ '^0x[0-9a-f]{40}$'
       or p_recipient = '0x0000000000000000000000000000000000000000'
       or p_amount !~ '^(0|[1-9][0-9]{0,12})(\.[0-9]{1,6})?$'
       or p_amount::numeric <= 0 or p_nonce is null
       or abs(p_nonce - floor(extract(epoch from clock_timestamp()) * 1000)::bigint) > 30000 then
        raise exception 'invalid_withdrawal' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(p_wallet, 0));
    if not exists (select 1 from public.bsmart_wallets
                   where account_id = p_account and address = p_wallet) then
        raise exception 'wallet_mismatch' using errcode = '22023';
    end if;
    update public.bsmart_withdrawals set state = 'expired', updated_at = clock_timestamp()
        where wallet_address = p_wallet and state = 'reserved' and expires_at <= clock_timestamp();
    if exists (select 1 from public.bsmart_withdrawals
               where wallet_address = p_wallet and state in ('reserved', 'submitting', 'uncertain')) then
        raise exception 'withdrawal_pending' using errcode = '23505';
    end if;
    insert into public.bsmart_withdrawals
        (id, account_id, wallet_address, recipient, amount, source_dex, nonce, state, expires_at)
        values (p_id, p_account, p_wallet, p_recipient, p_amount, p_source, p_nonce,
                'reserved', clock_timestamp() + interval '60 seconds') returning * into result;
    return result;
end;
$$;

create function public.bsmart_withdrawal_transition(
    p_account uuid, p_id uuid, p_from text, p_to text, p_response jsonb default null,
    p_hash text default null, p_ledger_time bigint default null)
returns public.bsmart_withdrawals language plpgsql security definer set search_path = '' as $$
declare result public.bsmart_withdrawals;
begin
    if not ((p_from = 'reserved' and p_to in ('submitting', 'cancelled', 'expired'))
        or (p_from = 'submitting' and p_to in ('accepted', 'uncertain', 'rejected', 'core_debited'))
        or (p_from in ('accepted', 'uncertain') and p_to = 'core_debited')) then
        raise exception 'invalid_transition' using errcode = '22023';
    end if;
    update public.bsmart_withdrawals
        set state = p_to, response = coalesce(p_response, response),
            ledger_hash = coalesce(p_hash, ledger_hash), ledger_time = coalesce(p_ledger_time, ledger_time),
            updated_at = clock_timestamp()
        where id = p_id and account_id = p_account and state = p_from
          and (p_from <> 'reserved' or p_to = 'expired' or expires_at > clock_timestamp())
          and (p_to <> 'expired' or expires_at <= clock_timestamp())
          and (p_to <> 'core_debited' or (p_hash ~ '^0x[0-9a-f]{64}$' and p_ledger_time > 0))
        returning * into result;
    if not found then raise exception 'invalid_transition' using errcode = '22023'; end if;
    return result;
end;
$$;

revoke all on function public.bsmart_withdrawal_reserve(uuid,uuid,text,text,text,text,bigint) from public, anon, authenticated;
revoke all on function public.bsmart_withdrawal_transition(uuid,uuid,text,text,jsonb,text,bigint) from public, anon, authenticated;
grant execute on function public.bsmart_withdrawal_reserve(uuid,uuid,text,text,text,text,bigint) to service_role;
grant execute on function public.bsmart_withdrawal_transition(uuid,uuid,text,text,jsonb,text,bigint) to service_role;

commit;

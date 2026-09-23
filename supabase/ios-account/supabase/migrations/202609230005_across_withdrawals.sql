begin;

create table public.bsmart_across_withdrawals (
    id uuid primary key,
    account_id uuid not null references auth.users(id) on delete cascade,
    wallet_address text not null,
    recipient text not null,
    source_dex text not null check (source_dex in ('spot', 'perps')),
    amount_units numeric(20, 0) not null check (amount_units > 0),
    quote jsonb not null,
    quote_expires_at timestamptz not null,
    deposit_id text not null unique,
    state text not null check (state in (
        'quoted', 'quote_expired', 'submitting', 'submitted', 'uncertain',
        'deposit_pending', 'deposit_failed', 'filled', 'expired', 'refunded', 'cancelled'
    )),
    provider_status text,
    provider_response jsonb,
    attempted_at timestamptz,
    checked_at timestamptz,
    created_at timestamptz not null default clock_timestamp(),
    updated_at timestamptz not null default clock_timestamp(),
    check (wallet_address ~ '^0x[0-9a-f]{40}$'),
    check (recipient ~ '^0x[0-9a-f]{40}$'),
    check (deposit_id ~ '^[0-9]{1,100}$')
);

create unique index bsmart_one_pending_across_withdrawal_per_wallet
    on public.bsmart_across_withdrawals(wallet_address)
    where state in ('quoted', 'submitting', 'submitted', 'uncertain', 'deposit_pending', 'expired');
create index bsmart_across_withdrawals_account_history
    on public.bsmart_across_withdrawals(account_id, created_at desc);

alter table public.bsmart_across_withdrawals enable row level security;
revoke all on public.bsmart_across_withdrawals from public, anon, authenticated;
grant select, insert, update on public.bsmart_across_withdrawals to service_role;

create function public.bsmart_across_withdrawal_reserve(
    p_account uuid, p_id uuid, p_wallet text, p_recipient text, p_source text,
    p_amount_units numeric, p_quote jsonb, p_quote_expires_at timestamptz, p_deposit_id text
) returns public.bsmart_across_withdrawals
language plpgsql security definer set search_path = '' as $$
declare result public.bsmart_across_withdrawals;
begin
    if p_account is null or p_id is null or p_wallet !~ '^0x[0-9a-f]{40}$'
       or p_recipient !~ '^0x[0-9a-f]{40}$'
       or p_recipient = '0x0000000000000000000000000000000000000000'
       or p_source not in ('spot', 'perps') or p_amount_units <= 0
       or p_amount_units <> trunc(p_amount_units) or p_quote is null
       or p_quote_expires_at <= clock_timestamp() + interval '5 seconds'
       or p_quote_expires_at > clock_timestamp() + interval '5 minutes'
       or p_deposit_id !~ '^[0-9]{1,100}$' then
        raise exception 'invalid_across_quote' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(p_wallet, 0));
    if not exists (select 1 from public.bsmart_wallets
                   where account_id = p_account and address = p_wallet) then
        raise exception 'wallet_mismatch' using errcode = '22023';
    end if;
    update public.bsmart_across_withdrawals
       set state = 'quote_expired', updated_at = clock_timestamp()
     where wallet_address = p_wallet and state = 'quoted' and quote_expires_at <= clock_timestamp();
    if exists (select 1 from public.bsmart_withdrawals
               where wallet_address = p_wallet and state in
                   ('reserved', 'submitting', 'accepted', 'uncertain', 'core_debited'))
       or exists (select 1 from public.bsmart_across_withdrawals
                  where wallet_address = p_wallet and state in
                      ('quoted', 'submitting', 'submitted', 'uncertain', 'deposit_pending', 'expired')) then
        raise exception 'withdrawal_pending' using errcode = '23505';
    end if;
    insert into public.bsmart_across_withdrawals
        (id, account_id, wallet_address, recipient, source_dex, amount_units,
         quote, quote_expires_at, deposit_id, state)
    values (p_id, p_account, p_wallet, p_recipient, p_source, p_amount_units,
            p_quote, p_quote_expires_at, p_deposit_id, 'quoted')
    returning * into result;
    return result;
end;
$$;

revoke all on function public.bsmart_across_withdrawal_reserve(uuid,uuid,text,text,text,numeric,jsonb,timestamptz,text)
    from public, anon, authenticated;
grant execute on function public.bsmart_across_withdrawal_reserve(uuid,uuid,text,text,text,numeric,jsonb,timestamptz,text)
    to service_role;

commit;

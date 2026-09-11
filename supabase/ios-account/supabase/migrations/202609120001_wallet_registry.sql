-- Operator-run on the bSmart AUTH project only. No content tables are changed.
begin;

create schema if not exists bsmart_private;
revoke all on schema bsmart_private from public, anon, authenticated;

create table public.bsmart_wallets (
    account_id uuid primary key references auth.users(id),
    address text not null unique check (
        address ~ '^0x[0-9a-f]{40}$' and address <> '0x0000000000000000000000000000000000000000'
    ),
    created_at timestamptz not null default now()
);
alter table public.bsmart_wallets enable row level security;
revoke all on public.bsmart_wallets from public, anon, authenticated;
grant select on public.bsmart_wallets to authenticated;
grant select, insert on public.bsmart_wallets to service_role;
create policy wallet_owner_read on public.bsmart_wallets for select to authenticated
    using (account_id = (select auth.uid()));

create table bsmart_private.wallet_challenges (
    account_id uuid primary key references auth.users(id),
    id uuid not null unique default gen_random_uuid(),
    address text not null,
    token_hash text not null,
    nonce text not null,
    issued_at timestamptz not null,
    expires_at timestamptz not null,
    consumed boolean not null default false
);
revoke all on bsmart_private.wallet_challenges from public, anon, authenticated;

create function public.bsmart_wallet_challenge(p_account uuid, p_token_hash text, p_address text, p_nonce text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    c bsmart_private.wallet_challenges;
    bound text;
    issued timestamptz := date_trunc('second', clock_timestamp());
begin
    if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$'
       or p_nonce is null or p_nonce !~ '^[0-9a-f]{64}$'
       or p_address is null or p_address !~ '^0x[0-9a-f]{40}$'
       or p_address = '0x0000000000000000000000000000000000000000' then
        raise exception 'invalid_input' using errcode = '22023';
    end if;
    -- Serialize create/consume for the same account; never replace a bound address.
    perform pg_advisory_xact_lock(hashtextextended(p_account::text, 0));
    select address into bound from public.bsmart_wallets where account_id = p_account;
    if bound is not null and bound <> p_address then
        raise exception 'wallet_conflict' using errcode = '23505';
    end if;
    if exists(select 1 from bsmart_private.wallet_challenges
              where account_id = p_account and issued_at > issued - interval '5 seconds') then
        raise exception 'rate_limit' using errcode = 'P0001';
    end if;
    insert into bsmart_private.wallet_challenges(account_id, address, token_hash, nonce, issued_at, expires_at)
        values(p_account, p_address, p_token_hash, p_nonce, issued, issued + interval '5 minutes')
        on conflict (account_id) do update set id = gen_random_uuid(), address = excluded.address,
            token_hash = excluded.token_hash, nonce = excluded.nonce, issued_at = excluded.issued_at,
            expires_at = excluded.expires_at, consumed = false
        returning * into c;
    return jsonb_build_object('id', c.id, 'accountId', c.account_id, 'address', c.address, 'nonce', c.nonce,
        'issuedAt', to_char(c.issued_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'expiresAt', to_char(c.expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
end;
$$;

create function public.bsmart_wallet_challenge_read(p_account uuid, p_token_hash text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c bsmart_private.wallet_challenges;
begin
    select * into c from bsmart_private.wallet_challenges
        where account_id = p_account and id = p_id and token_hash = p_token_hash
          and expires_at > clock_timestamp() and not consumed;
    if not found then raise exception 'invalid_proof' using errcode = '22023'; end if;
    return jsonb_build_object('id', c.id, 'accountId', c.account_id, 'address', c.address, 'nonce', c.nonce,
        'issuedAt', to_char(c.issued_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'expiresAt', to_char(c.expires_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
end;
$$;

create function public.bsmart_wallet_commit(p_account uuid, p_token_hash text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c bsmart_private.wallet_challenges; bound text;
begin
    perform pg_advisory_xact_lock(hashtextextended(p_account::text, 0));
    select * into c from bsmart_private.wallet_challenges
        where account_id = p_account and id = p_id and token_hash = p_token_hash
          and expires_at > clock_timestamp() and not consumed for update;
    if not found then raise exception 'invalid_proof' using errcode = '22023'; end if;
    insert into public.bsmart_wallets(account_id, address) values(p_account, c.address)
        on conflict (account_id) do nothing;
    select address into bound from public.bsmart_wallets where account_id = p_account;
    if bound <> c.address then raise exception 'wallet_conflict' using errcode = '23505'; end if;
    update bsmart_private.wallet_challenges set consumed = true where account_id = p_account and id = p_id;
    return jsonb_build_object('accountId', p_account, 'address', bound);
end;
$$;

revoke all on function public.bsmart_wallet_challenge(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.bsmart_wallet_challenge_read(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public.bsmart_wallet_commit(uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.bsmart_wallet_challenge(uuid,text,text,text) to service_role;
grant execute on function public.bsmart_wallet_challenge_read(uuid,text,uuid) to service_role;
grant execute on function public.bsmart_wallet_commit(uuid,text,uuid) to service_role;

commit;

-- An open Relay deposit address is pinned to the authenticated account's
-- wallet and exact USDC-to-HyperCore route. Never overwrite a shown address.
begin;

create table public.bsmart_funding_addresses (
    account_id uuid not null references auth.users(id),
    wallet_address text not null,
    network text not null check (network in ('arbitrum', 'monad', 'base', 'ethereum', 'bnb')),
    origin_chain_id integer not null,
    origin_currency text not null,
    destination_chain_id integer not null check (destination_chain_id = 1337),
    destination_currency text not null check (destination_currency = '0x00000000000000000000000000000000'),
    deposit_address text not null,
    request_id text not null,
    created_at timestamptz not null default clock_timestamp(),
    primary key (account_id, wallet_address, network),
    check (wallet_address ~ '^0x[0-9a-f]{40}$' and wallet_address <> '0x0000000000000000000000000000000000000000'),
    check (origin_currency ~ '^0x[0-9a-f]{40}$'),
    check (deposit_address ~ '^0x[0-9a-f]{40}$' and deposit_address <> wallet_address),
    check (request_id ~ '^0x[0-9a-f]{64}$')
);
alter table public.bsmart_funding_addresses enable row level security;
revoke all on public.bsmart_funding_addresses from public, anon, authenticated;
grant select, insert on public.bsmart_funding_addresses to service_role;

commit;

-- Publish one audited follow-ability snapshot atomically. No client may write scores.
begin;

create table public.bsmart_investor_ability_snapshot (
  id integer primary key default 1 check (id = 1),
  revision bigint not null check (revision > 0),
  scoring_version text not null check (scoring_version = 'follow-ability-v1'),
  as_of timestamptz not null,
  items jsonb not null check (jsonb_typeof(items) = 'array'),
  published_at timestamptz not null default now()
);

revoke all on public.bsmart_investor_ability_snapshot from public, anon, authenticated;
grant select, insert, update, delete on public.bsmart_investor_ability_snapshot to service_role;

commit;

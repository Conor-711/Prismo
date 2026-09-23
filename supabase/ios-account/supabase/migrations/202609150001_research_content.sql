-- Manual deployment only. Isolated research tables; no user/wallet schema changes.
begin;
create table if not exists public.bsmart_content_releases (
  revision text primary key check (revision ~ '^[a-f0-9]{64}$'),
  manifest jsonb not null,
  provenance jsonb not null,
  created_at timestamptz not null default now()
);
create table if not exists public.bsmart_content_pages (
  revision text not null references public.bsmart_content_releases(revision),
  collection text not null,
  owner text not null,
  page integer not null check (page >= 0),
  payload jsonb not null,
  primary key (revision, collection, owner, page)
);
create table if not exists public.bsmart_content_active (
  channel text primary key check (channel = 'production'),
  revision text not null references public.bsmart_content_releases(revision),
  activated_at timestamptz not null default now()
);
alter table public.bsmart_content_releases enable row level security;
alter table public.bsmart_content_pages enable row level security;
alter table public.bsmart_content_active enable row level security;
revoke all on public.bsmart_content_releases, public.bsmart_content_pages,
  public.bsmart_content_active from public, anon, authenticated, service_role;
grant select on public.bsmart_content_releases, public.bsmart_content_pages,
  public.bsmart_content_active to service_role;
comment on table public.bsmart_content_pages is 'Immutable research only; no balances, wallet or user states. Publish via trusted PostgreSQL operator.';
commit;

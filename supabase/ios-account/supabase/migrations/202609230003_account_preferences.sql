begin;

create table if not exists public.bsmart_account_preferences (
  account_id uuid primary key references auth.users(id) on delete cascade,
  onboarding_completed boolean not null default false,
  followed_authors text[] not null default '{}',
  followed_money text[] not null default '{}',
  revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint bsmart_account_preferences_author_limit check (cardinality(followed_authors) <= 1000),
  constraint bsmart_account_preferences_money_limit check (cardinality(followed_money) <= 1000)
);

alter table public.bsmart_account_preferences enable row level security;
revoke all on public.bsmart_account_preferences from anon, authenticated;
grant select, insert, update, delete on public.bsmart_account_preferences to service_role;

-- Existing completed profiles predate server-side onboarding state. New profiles
-- start incomplete and are marked complete only after the onboarding finish call.
insert into public.bsmart_account_preferences(account_id, onboarding_completed)
select account_id, revision > 0 from public.bsmart_feed_profiles
on conflict (account_id) do nothing;

commit;

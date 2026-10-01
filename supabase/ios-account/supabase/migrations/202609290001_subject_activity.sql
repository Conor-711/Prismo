begin;

create table public.bsmart_subject_activity_snapshots (
  channel text primary key check (channel = 'production'),
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  constraint subject_activity_schema check (
    payload->>'schemaVersion' = '1'
    and jsonb_typeof(payload->'subjects') = 'array'
    and jsonb_typeof(payload->'events') = 'array'
  )
);

alter table public.bsmart_subject_activity_snapshots enable row level security;
revoke all on public.bsmart_subject_activity_snapshots from anon, authenticated;
grant select, insert, update on public.bsmart_subject_activity_snapshots to service_role;

commit;

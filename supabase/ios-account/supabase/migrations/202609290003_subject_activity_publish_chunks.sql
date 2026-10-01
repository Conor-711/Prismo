begin;

create table public.bsmart_subject_activity_publish_chunks (
  publication_id uuid not null,
  chunk_index integer not null check (chunk_index >= 0),
  payload_text text not null check (octet_length(payload_text) between 1 and 400000),
  created_at timestamptz not null default now(),
  primary key (publication_id, chunk_index)
);

alter table public.bsmart_subject_activity_publish_chunks enable row level security;
revoke all on public.bsmart_subject_activity_publish_chunks from anon, authenticated;
grant select, insert, delete on public.bsmart_subject_activity_publish_chunks to service_role;

commit;

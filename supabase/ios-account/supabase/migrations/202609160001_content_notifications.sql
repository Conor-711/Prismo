-- Run manually in the native iOS Supabase project, never the web project.
begin;
create table public.bsmart_push_devices (
    id uuid primary key default gen_random_uuid(),
    installation_id uuid not null,
    user_id uuid not null references auth.users(id) on delete cascade,
    apns_token text not null check (apns_token ~ '^[a-f0-9]{64,200}$'),
    environment text not null check (environment in ('production', 'development')),
    locale text not null check (length(locale) between 1 and 64),
    enabled boolean not null default true,
    updated_at timestamptz not null default now(),
    unique (environment, apns_token)
);
create index bsmart_push_installation on public.bsmart_push_devices(installation_id, user_id);
create table public.bsmart_content_push_deliveries (
    revision text not null references public.bsmart_content_releases(revision),
    device_id uuid not null references public.bsmart_push_devices(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    state text not null default 'pending' check (state in ('pending','sending','accepted','skipped','failed')),
    attempts integer not null default 0,
    available_at timestamptz not null default now(),
    expires_at timestamptz not null default now() + interval '24 hours',
    lease_id uuid,
    leased_until timestamptz,
    apns_id uuid not null default gen_random_uuid(),
    last_status integer,
    primary key (revision, device_id)
);
create index bsmart_push_pending on public.bsmart_content_push_deliveries(state, available_at);
alter table public.bsmart_push_devices enable row level security;
alter table public.bsmart_content_push_deliveries enable row level security;
revoke all on public.bsmart_push_devices, public.bsmart_content_push_deliveries
    from public, anon, authenticated, service_role;

create function public.bsmart_register_push(p_user uuid, p_installation uuid, p_token text,
    p_environment text, p_locale text, p_enabled boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_installation::text, 0));
    update public.bsmart_push_devices set enabled = false
        where installation_id = p_installation;
    insert into public.bsmart_push_devices(installation_id,user_id,apns_token,environment,locale,enabled)
        values(p_installation,p_user,p_token,p_environment,p_locale,p_enabled)
        on conflict(environment,apns_token) do update set
            installation_id=excluded.installation_id,user_id=excluded.user_id,
            locale=excluded.locale,enabled=excluded.enabled,updated_at=now();
end;
$$;
create function public.bsmart_unregister_push(p_user uuid, p_installation uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_installation::text, 0));
    update public.bsmart_push_devices set enabled=false
        where installation_id=p_installation and user_id=p_user;
end;
$$;
revoke all on function public.bsmart_register_push(uuid,uuid,text,text,text,boolean) from public,anon,authenticated;
revoke all on function public.bsmart_unregister_push(uuid,uuid) from public,anon,authenticated;
grant execute on function public.bsmart_register_push(uuid,uuid,text,text,text,boolean) to service_role;
grant execute on function public.bsmart_unregister_push(uuid,uuid) to service_role;
commit;

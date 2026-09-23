-- Activity uses the platform public profile, never Google email or authentication metadata.
-- Retain the flags for old readers, but remove user-controlled visibility.
begin;

alter table public.bsmart_feed_profiles alter column visible set default true;
alter table public.bsmart_feed_profiles alter column feed_visible set default true;

create or replace function public.bsmart_activity_always_public()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.visible := true;
  new.feed_visible := true;
  return new;
end;
$$;
revoke all on function public.bsmart_activity_always_public() from public, anon, authenticated;

create trigger bsmart_activity_always_public
before insert or update on public.bsmart_feed_profiles
for each row execute function public.bsmart_activity_always_public();

update public.bsmart_feed_profiles set visible = true, feed_visible = true
where not visible or not feed_visible;

commit;

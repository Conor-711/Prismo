-- Apply manually after the compatibility repair. Uses existing authoritative social follows.
begin;
create or replace function public.bsmart_activity_push_matches(p_device uuid,p_user uuid,p_actor text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.bsmart_push_devices d where d.id=p_device
    and d.user_id=p_user and d.enabled and d.environment='production'
    and d.updated_at>now()-interval '30 days' and d.notify_authors
    and (lower(p_actor)=any(d.followed_author_ids) or exists(
      select 1 from public.bsmart_social_follows f join public.bsmart_feed_profiles p on p.account_id=f.followed_id
      where f.follower_id=p_user and 'bsmart:'||p.public_id::text=lower(p_actor) and p.visible and p.feed_visible))
    and not exists(select 1 from public.bsmart_push_devices newer
      where newer.user_id=d.user_id and newer.enabled and newer.environment='production'
        and (newer.updated_at,newer.id)>(d.updated_at,d.id)));
$$;
revoke all on function public.bsmart_activity_push_matches(uuid,uuid,text) from public,anon,authenticated;
commit;

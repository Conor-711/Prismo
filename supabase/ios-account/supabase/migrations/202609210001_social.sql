-- Apply to the iOS account project after account profiles. The edge function
-- supplies p_actor only after verifying the Supabase access token.
begin;

create table public.bsmart_social_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  primary key(follower_id, followed_id),
  check(follower_id <> followed_id)
);
create index bsmart_social_followers on public.bsmart_social_follows(followed_id, created_at desc);

create table public.bsmart_social_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  body text not null check(char_length(body) between 1 and 2000),
  sent_at timestamptz not null default clock_timestamp(),
  read_at timestamptz,
  check(sender_id <> recipient_id)
);
create index bsmart_social_sent on public.bsmart_social_messages(sender_id, recipient_id, sent_at desc, id desc);
create index bsmart_social_received on public.bsmart_social_messages(recipient_id, sender_id, sent_at desc, id desc);
create index bsmart_social_unread on public.bsmart_social_messages(recipient_id, sent_at desc) where read_at is null;

alter table public.bsmart_social_follows enable row level security;
alter table public.bsmart_social_messages enable row level security;
revoke all on public.bsmart_social_follows, public.bsmart_social_messages from public, anon, authenticated;
grant select, insert, update, delete on public.bsmart_social_follows, public.bsmart_social_messages to service_role;

create function public.bsmart_social_follow(p_actor uuid, p_peer_public uuid, p_follow boolean)
returns void language plpgsql security invoker set search_path = '' as $$
declare peer uuid;
begin
  select account_id into peer from public.bsmart_feed_profiles
    where public_id = p_peer_public and revision > 0;
  if peer is null or peer = p_actor then raise exception 'invalid_peer'; end if;
  if p_follow then
    insert into public.bsmart_social_follows(follower_id, followed_id)
      values(p_actor, peer) on conflict do nothing;
  else
    delete from public.bsmart_social_follows where follower_id = p_actor and followed_id = peer;
  end if;
end;
$$;

create function public.bsmart_social_snapshot(p_actor uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'following', coalesce((select jsonb_agg(jsonb_build_object('profile',
      jsonb_build_object('id', p.public_id, 'nickname', p.nickname, 'handle', p.handle,
        'avatarURL', p.avatar_url), 'at', f.created_at) order by f.created_at desc)
      from public.bsmart_social_follows f join public.bsmart_feed_profiles p on p.account_id = f.followed_id
      where f.follower_id = p_actor), '[]'::jsonb),
    'followers', coalesce((select jsonb_agg(jsonb_build_object('profile',
      jsonb_build_object('id', p.public_id, 'nickname', p.nickname, 'handle', p.handle,
        'avatarURL', p.avatar_url), 'at', f.created_at) order by f.created_at desc)
      from public.bsmart_social_follows f join public.bsmart_feed_profiles p on p.account_id = f.follower_id
      where f.followed_id = p_actor), '[]'::jsonb),
    'conversations', coalesce((with peers as (
      select distinct case when sender_id = p_actor then recipient_id else sender_id end as peer_id
      from public.bsmart_social_messages where sender_id = p_actor or recipient_id = p_actor
    ) select jsonb_agg(jsonb_build_object('profile',
      jsonb_build_object('id', p.public_id, 'nickname', p.nickname, 'handle', p.handle,
        'avatarURL', p.avatar_url),
      'lastMessage', jsonb_build_object('id', m.id, 'isMine', m.sender_id = p_actor,
        'text', m.body, 'sentAt', m.sent_at),
      'unreadCount', (select count(*) from public.bsmart_social_messages unread
        where unread.sender_id = peers.peer_id and unread.recipient_id = p_actor and unread.read_at is null))
      order by m.sent_at desc, m.id desc)
      from peers join public.bsmart_feed_profiles p on p.account_id = peers.peer_id
      join lateral (select * from public.bsmart_social_messages message
        where (message.sender_id = p_actor and message.recipient_id = peers.peer_id)
           or (message.recipient_id = p_actor and message.sender_id = peers.peer_id)
        order by message.sent_at desc, message.id desc limit 1) m on true), '[]'::jsonb)
  );
$$;

create function public.bsmart_social_messages_page(p_actor uuid, p_peer_public uuid,
  p_before_at timestamptz default null, p_before_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare peer uuid; result jsonb;
begin
  select account_id into peer from public.bsmart_feed_profiles where public_id = p_peer_public;
  if peer is null or peer = p_actor or (p_before_at is null) <> (p_before_id is null) then
    raise exception 'invalid_peer';
  end if;
  with selected as (
    select id, sender_id, body, sent_at from public.bsmart_social_messages m
    where ((m.sender_id = p_actor and m.recipient_id = peer)
        or (m.sender_id = peer and m.recipient_id = p_actor))
      and (p_before_at is null or (m.sent_at, m.id) < (p_before_at, p_before_id))
    order by m.sent_at desc, m.id desc limit 51
  ), page as (select * from selected order by sent_at desc, id desc limit 50)
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'isMine', sender_id = p_actor,
      'text', body, 'sentAt', sent_at) order by sent_at, id) from page), '[]'::jsonb),
    'nextBeforeAt', case when (select count(*) from selected) > 50
      then (select sent_at from page order by sent_at, id limit 1) else null end,
    'nextBeforeID', case when (select count(*) from selected) > 50
      then (select id from page order by sent_at, id limit 1) else null end
  ) into result;
  if p_before_at is null then
    update public.bsmart_social_messages set read_at = clock_timestamp()
      where sender_id = peer and recipient_id = p_actor and read_at is null;
  end if;
  return result;
end;
$$;

create function public.bsmart_social_send(p_actor uuid, p_peer_public uuid, p_text text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare peer uuid; message public.bsmart_social_messages; trimmed text := btrim(p_text);
begin
  select account_id into peer from public.bsmart_feed_profiles
    where public_id = p_peer_public and revision > 0;
  if peer is null or peer = p_actor then raise exception 'invalid_peer'; end if;
  if trimmed is null or char_length(trimmed) not between 1 and 2000 then raise exception 'invalid_message'; end if;
  if (select count(*) from public.bsmart_social_messages
      where sender_id = p_actor and sent_at > clock_timestamp() - interval '1 hour') >= 60 then
    raise exception 'rate_limited';
  end if;
  insert into public.bsmart_social_messages(sender_id, recipient_id, body)
    values(p_actor, peer, trimmed) returning * into message;
  return jsonb_build_object('id', message.id, 'isMine', true,
    'text', message.body, 'sentAt', message.sent_at);
end;
$$;

revoke all on function public.bsmart_social_follow(uuid, uuid, boolean),
  public.bsmart_social_snapshot(uuid),
  public.bsmart_social_messages_page(uuid, uuid, timestamptz, uuid),
  public.bsmart_social_send(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.bsmart_social_follow(uuid, uuid, boolean),
  public.bsmart_social_snapshot(uuid),
  public.bsmart_social_messages_page(uuid, uuid, timestamptz, uuid),
  public.bsmart_social_send(uuid, uuid, text) to service_role;
commit;

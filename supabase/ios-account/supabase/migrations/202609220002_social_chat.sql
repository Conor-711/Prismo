-- Operator-applied migration for the iOS account project, not the content DB.
begin;

alter table public.bsmart_social_messages alter column recipient_id drop not null;
alter table public.bsmart_social_messages drop constraint bsmart_social_messages_body_check;
alter table public.bsmart_social_messages
  add column image_hash text,
  add column image_width integer,
  add column image_height integer,
  add column reply_to_id uuid references public.bsmart_social_messages(id) on delete set null,
  add constraint bsmart_chat_body check (char_length(body) <= 2000 and (length(btrim(body)) > 0 or image_hash is not null)),
  add constraint bsmart_chat_image check (
    (image_hash is null and image_width is null and image_height is null) or
    (image_hash is not null and image_hash ~ '^[a-f0-9]{64}$'
      and image_width is not null and image_width between 1 and 2048
      and image_height is not null and image_height between 1 and 2048));
create index bsmart_chat_global on public.bsmart_social_messages(sent_at desc, id desc)
  where recipient_id is null;
create index bsmart_chat_sender_rate on public.bsmart_social_messages(sender_id, sent_at desc);

create table public.bsmart_chat_uploads (
  id uuid primary key,
  sender_id uuid not null references auth.users(id) on delete cascade,
  image_hash text not null check (image_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);
create index bsmart_chat_upload_rate on public.bsmart_chat_uploads(sender_id, created_at desc);
alter table public.bsmart_chat_uploads enable row level security;
revoke all on public.bsmart_chat_uploads from public, anon, authenticated;
grant select, insert, delete on public.bsmart_chat_uploads to service_role;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
  values ('bsmart-chat-images', 'bsmart-chat-images', false, 2097152, array['image/jpeg'])
  on conflict(id) do nothing;

create function public.bsmart_chat_peer(p_actor uuid, p_room text)
returns uuid language plpgsql stable security invoker set search_path = '' as $$
declare peer uuid;
begin
  if not exists(select 1 from public.bsmart_feed_profiles where account_id = p_actor and revision > 0) then
    raise exception 'profile_required';
  end if;
  if p_room = 'global' then return null; end if;
  select account_id into peer from public.bsmart_feed_profiles
    where public_id::text = lower(p_room) and revision > 0;
  if peer is null or peer = p_actor then raise exception 'invalid_peer'; end if;
  return peer;
end;
$$;

create function public.bsmart_chat_reserve_image(p_actor uuid, p_room text, p_id uuid, p_hash text)
returns void language plpgsql security invoker set search_path = '' as $$
declare previous public.bsmart_chat_uploads;
begin
  perform public.bsmart_chat_peer(p_actor, p_room);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text, 0));
  select * into previous from public.bsmart_chat_uploads where id = p_id;
  if found then
    if previous.sender_id <> p_actor or previous.image_hash <> p_hash then
      raise exception 'idempotency_conflict';
    end if;
    return;
  end if;
  if (select count(*) from public.bsmart_chat_uploads where sender_id = p_actor
      and created_at > clock_timestamp() - interval '1 hour') >= 60 then raise exception 'rate_limited'; end if;
  insert into public.bsmart_chat_uploads(id, sender_id, image_hash) values(p_id, p_actor, p_hash);
end;
$$;

-- Called only after the enclosing RPC has verified room access.
create function public.bsmart_chat_message(p_id uuid, p_actor uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('id', m.id, 'isMine', m.sender_id = p_actor,
    'text', m.body, 'sentAt', m.sent_at,
    'sender', jsonb_build_object('id', p.public_id, 'nickname', p.nickname,
      'handle', p.handle, 'avatarURL', p.avatar_url),
    'image', case when m.image_hash is not null then jsonb_build_object(
      'path', m.id::text || '-' || m.image_hash || '.jpg', 'width', m.image_width, 'height', m.image_height) else null end,
    'reply', case when r.id is not null then jsonb_build_object('id', r.id,
      'senderName', rp.nickname, 'text', left(r.body, 240), 'hasImage', r.image_hash is not null) else null end)
  from public.bsmart_social_messages m
  join public.bsmart_feed_profiles p on p.account_id = m.sender_id
  left join public.bsmart_social_messages r on r.id = m.reply_to_id
  left join public.bsmart_feed_profiles rp on rp.account_id = r.sender_id
  where m.id = p_id;
$$;

create function public.bsmart_chat_page(p_actor uuid, p_room text,
  p_before_at timestamptz default null, p_before_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare peer uuid := public.bsmart_chat_peer(p_actor, p_room); result jsonb;
begin
  if (p_before_at is null) <> (p_before_id is null) then raise exception 'invalid_cursor'; end if;
  with selected as (
    select id, sent_at from public.bsmart_social_messages m
    where ((peer is null and m.recipient_id is null) or
      (peer is not null and ((m.sender_id = p_actor and m.recipient_id = peer) or
                            (m.sender_id = peer and m.recipient_id = p_actor))))
      and (p_before_at is null or (m.sent_at, m.id) < (p_before_at, p_before_id))
    order by m.sent_at desc, m.id desc limit 51
  ), page as (select * from selected order by sent_at desc, id desc limit 50)
  select jsonb_build_object('items', coalesce((select jsonb_agg(public.bsmart_chat_message(id, p_actor)
    order by sent_at, id) from page), '[]'::jsonb),
    'nextBeforeAt', case when (select count(*) from selected) > 50
      then (select sent_at from page order by sent_at, id limit 1) else null end,
    'nextBeforeID', case when (select count(*) from selected) > 50
      then (select id from page order by sent_at, id limit 1) else null end) into result;
  if peer is not null and p_before_at is null then
    update public.bsmart_social_messages set read_at = clock_timestamp()
      where sender_id = peer and recipient_id = p_actor and read_at is null;
  end if;
  return result;
end;
$$;

create function public.bsmart_chat_send(p_actor uuid, p_room text, p_id uuid, p_text text,
  p_reply_id uuid default null, p_image_hash text default null,
  p_image_width integer default null, p_image_height integer default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare peer uuid := public.bsmart_chat_peer(p_actor, p_room);
  previous public.bsmart_social_messages; trimmed text := btrim(p_text);
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text, 0));
  if p_id is null or trimmed is null or char_length(trimmed) > 2000 or
     (trimmed = '' and p_image_hash is null) then raise exception 'invalid_message'; end if;
  if p_image_hash is not null and not exists (select 1 from public.bsmart_chat_uploads
    where id = p_id and sender_id = p_actor and image_hash = p_image_hash) then raise exception 'invalid_image'; end if;
  select * into previous from public.bsmart_social_messages where id = p_id;
  if found then
    if previous.sender_id <> p_actor or previous.recipient_id is distinct from peer or
       previous.body <> trimmed or previous.reply_to_id is distinct from p_reply_id or
       previous.image_hash is distinct from p_image_hash then raise exception 'idempotency_conflict'; end if;
    return public.bsmart_chat_message(p_id, p_actor);
  end if;
  if p_reply_id is not null and not exists (
    select 1 from public.bsmart_social_messages m where m.id = p_reply_id and
      ((peer is null and m.recipient_id is null) or (peer is not null and
        ((m.sender_id = p_actor and m.recipient_id = peer) or (m.sender_id = peer and m.recipient_id = p_actor))))
  ) then raise exception 'invalid_reply'; end if;
  if (select count(*) from public.bsmart_social_messages
      where sender_id = p_actor and sent_at > clock_timestamp() - interval '1 hour') >= 60 then
    raise exception 'rate_limited';
  end if;
  insert into public.bsmart_social_messages(id, sender_id, recipient_id, body,
    reply_to_id, image_hash, image_width, image_height)
    values(p_id, p_actor, peer, trimmed, p_reply_id, p_image_hash, p_image_width, p_image_height);
  return public.bsmart_chat_message(p_id, p_actor);
end;
$$;

revoke all on function public.bsmart_chat_reserve_image(uuid, text, uuid, text),
  public.bsmart_chat_peer(uuid, text), public.bsmart_chat_message(uuid, uuid),
  public.bsmart_chat_page(uuid, text, timestamptz, uuid),
  public.bsmart_chat_send(uuid, text, uuid, text, uuid, text, integer, integer) from public, anon, authenticated;
grant execute on function public.bsmart_chat_reserve_image(uuid, text, uuid, text),
  public.bsmart_chat_peer(uuid, text), public.bsmart_chat_message(uuid, uuid),
  public.bsmart_chat_page(uuid, text, timestamptz, uuid),
  public.bsmart_chat_send(uuid, text, uuid, text, uuid, text, integer, integer) to service_role;
commit;

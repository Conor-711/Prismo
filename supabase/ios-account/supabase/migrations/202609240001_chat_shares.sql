begin;

alter table public.bsmart_social_messages add column shared_content jsonb;
alter table public.bsmart_social_messages drop constraint bsmart_chat_body;
alter table public.bsmart_social_messages add constraint bsmart_chat_body check (
  char_length(body) <= 2000 and (length(btrim(body)) > 0 or image_hash is not null or shared_content is not null)
);
alter table public.bsmart_social_messages add constraint bsmart_chat_share_valid check (
  shared_content is null or (
    jsonb_typeof(shared_content) = 'object' and octet_length(shared_content::text) <= 4096 and
    coalesce(shared_content->>'kind', '') in ('opinion', 'investor', 'ticker') and
    coalesce(length(shared_content->>'id'), 0) between 1 and 128 and
    coalesce(length(shared_content->>'title'), 0) between 1 and 100
  )
);

create or replace function public.bsmart_chat_message(p_id uuid, p_actor uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('id', m.id, 'isMine', m.sender_id = p_actor,
    'text', m.body, 'sentAt', m.sent_at, 'share', m.shared_content,
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

drop function public.bsmart_chat_send(uuid, text, uuid, text, uuid, text, integer, integer);
create function public.bsmart_chat_send(p_actor uuid, p_room text, p_id uuid, p_text text,
  p_reply_id uuid default null, p_image_hash text default null,
  p_image_width integer default null, p_image_height integer default null, p_share jsonb default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare peer uuid := public.bsmart_chat_peer(p_actor, p_room);
  previous public.bsmart_social_messages; trimmed text := btrim(p_text);
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_actor::text, 0));
  if p_id is null or trimmed is null or char_length(trimmed) > 2000 or
     (trimmed = '' and p_image_hash is null and p_share is null) then raise exception 'invalid_message'; end if;
  if p_share is not null and (jsonb_typeof(p_share) <> 'object' or
      octet_length(p_share::text) > 4096 or coalesce(p_share->>'kind', '') not in ('opinion', 'investor', 'ticker') or
      coalesce(length(p_share->>'id'), 0) not between 1 and 128 or
      coalesce(length(p_share->>'title'), 0) not between 1 and 100) then raise exception 'invalid_share'; end if;
  if p_image_hash is not null and not exists (select 1 from public.bsmart_chat_uploads
    where id = p_id and sender_id = p_actor and image_hash = p_image_hash) then raise exception 'invalid_image'; end if;
  select * into previous from public.bsmart_social_messages where id = p_id;
  if found then
    if previous.sender_id <> p_actor or previous.recipient_id is distinct from peer or
       previous.body <> trimmed or previous.reply_to_id is distinct from p_reply_id or
       previous.image_hash is distinct from p_image_hash or
       previous.shared_content is distinct from p_share then raise exception 'idempotency_conflict'; end if;
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
    reply_to_id, image_hash, image_width, image_height, shared_content)
    values(p_id, p_actor, peer, trimmed, p_reply_id, p_image_hash, p_image_width, p_image_height, p_share);
  return public.bsmart_chat_message(p_id, p_actor);
end;
$$;

revoke all on function public.bsmart_chat_send(uuid, text, uuid, text, uuid, text, integer, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.bsmart_chat_send(uuid, text, uuid, text, uuid, text, integer, integer, jsonb)
  to service_role;
commit;

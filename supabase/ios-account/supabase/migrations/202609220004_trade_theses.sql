-- Apply manually to the iOS account project. No execution or wallet changes.
begin;
create index bsmart_feed_owner_time on public.bsmart_feed_orders(account_id, executed_at desc, id)
  where execution is not null;
create table public.bsmart_trade_theses (
  trade_id uuid primary key references public.bsmart_feed_orders(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000 and body ~ '[^[:space:]]'),
  published_at timestamptz not null default clock_timestamp()
);
create table public.bsmart_trade_thesis_likes (
  trade_id uuid not null references public.bsmart_trade_theses(trade_id) on delete cascade,
  account_id uuid not null references auth.users(id) on delete cascade,
  primary key (trade_id, account_id)
);
alter table public.bsmart_trade_theses enable row level security;
alter table public.bsmart_trade_thesis_likes enable row level security;
revoke all on public.bsmart_trade_theses, public.bsmart_trade_thesis_likes from public, anon, authenticated;
grant select, insert, delete on public.bsmart_trade_theses, public.bsmart_trade_thesis_likes to service_role;

create function public.bsmart_thesis_json(p_trade uuid, p_actor uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('id', t.trade_id, 'body', t.body, 'publishedAt', t.published_at,
    'likeCount', (select count(*) from public.bsmart_trade_thesis_likes l where l.trade_id = t.trade_id),
    'likedByMe', exists(select 1 from public.bsmart_trade_thesis_likes l
      where l.trade_id = t.trade_id and l.account_id = p_actor))
  from public.bsmart_trade_theses t where t.trade_id = p_trade;
$$;

create function public.bsmart_feed_social_page(p_actor uuid, p_offset integer, p_limit integer,
  p_profile uuid default null, p_mine boolean default false, p_cloid text default null)
returns jsonb language sql stable security invoker set search_path = '' as $$
  with selected as (
    select o.*, p.public_id, p.nickname, p.handle, p.avatar_url, t.trade_id as thesis_id
    from public.bsmart_feed_orders o join public.bsmart_feed_profiles p using(account_id)
    left join public.bsmart_trade_theses t on t.trade_id = o.id
    where p.visible and p.feed_visible and o.execution is not null and o.executed_at is not null
      and coalesce(o.opinion->>'sourceKind', 'account') = 'account'
      and (o.opinion->>'platformPercentile')::numeric between 0 and 1
      and (p_profile is null or p.public_id = p_profile)
      and (not p_mine or o.account_id = p_actor)
      and (p_cloid is null or (o.cloid = p_cloid and o.account_id = p_actor))
      and (p_mine or p_cloid is not null or t.trade_id is not null
        or (o.opinion->>'platformPercentile')::numeric <= 0.25)
    order by o.executed_at desc, o.id
    limit greatest(1, least(p_limit, 30)) + 1 offset greatest(p_offset, 0)
  ), page as (select * from selected order by executed_at desc, id limit greatest(1, least(p_limit, 30)))
  select jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object(
    'id', id, 'trader', jsonb_build_object('id', public_id, 'nickname', nickname, 'handle', handle, 'avatarURL', avatar_url),
    'opinion', opinion, 'side', execution->>'side', 'notionalUSD', execution->>'notionalUSD',
    'marketCoin', execution->>'marketCoin', 'executedAt', executed_at,
    'thesis', public.bsmart_thesis_json(id, p_actor),
    'canLikeThesis', account_id <> p_actor and thesis_id is not null,
    'canPublishThesis', account_id = p_actor and thesis_id is null
  ) order by executed_at desc, id) from page), '[]'::jsonb),
    'nextOffset', case when (select count(*) from selected) > p_limit then p_offset + p_limit else null end);
$$;

create function public.bsmart_thesis_publish(p_actor uuid, p_trade uuid, p_body text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare o public.bsmart_feed_orders; existing text;
begin
  if p_body is null or char_length(p_body) not between 1 and 1000 or p_body !~ '[^[:space:]]'
    or p_body ~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]' then
    return jsonb_build_object('error', 'invalid_input');
  end if;
  select * into o from public.bsmart_feed_orders where id = p_trade and account_id = p_actor for update;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if o.execution is null or o.executed_at is null then return jsonb_build_object('error', 'trade_pending'); end if;
  if coalesce(o.opinion->>'sourceKind', 'account') <> 'account'
    or not coalesce((o.opinion->>'platformPercentile')::numeric between 0 and 1, false) then
    return jsonb_build_object('error', 'invalid_input');
  end if;
  select body into existing from public.bsmart_trade_theses where trade_id = p_trade;
  if found and existing <> p_body then return jsonb_build_object('error', 'thesis_exists'); end if;
  insert into public.bsmart_trade_theses(trade_id, body) values(p_trade, p_body) on conflict do nothing;
  return public.bsmart_thesis_json(p_trade, p_actor);
end;
$$;

create function public.bsmart_thesis_like(p_actor uuid, p_trade uuid, p_liked boolean)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare owner_id uuid;
begin
  if p_liked is null then return jsonb_build_object('error', 'invalid_input'); end if;
  select o.account_id into owner_id from public.bsmart_trade_theses t
    join public.bsmart_feed_orders o on o.id = t.trade_id
    join public.bsmart_feed_profiles p on p.account_id = o.account_id
    where t.trade_id = p_trade and p.visible and p.feed_visible and o.execution is not null for update of t;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if owner_id = p_actor then return jsonb_build_object('error', 'own_thesis'); end if;
  if p_liked then
    insert into public.bsmart_trade_thesis_likes values(p_trade, p_actor) on conflict do nothing;
  else
    delete from public.bsmart_trade_thesis_likes where trade_id = p_trade and account_id = p_actor;
  end if;
  return public.bsmart_thesis_json(p_trade, p_actor);
end;
$$;
-- Row locking requires UPDATE privilege; no client role can reach these tables.
grant update on public.bsmart_trade_theses to service_role;
revoke all on function public.bsmart_thesis_json(uuid, uuid),
  public.bsmart_feed_social_page(uuid, integer, integer, uuid, boolean, text),
  public.bsmart_thesis_publish(uuid, uuid, text), public.bsmart_thesis_like(uuid, uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.bsmart_thesis_json(uuid, uuid),
  public.bsmart_feed_social_page(uuid, integer, integer, uuid, boolean, text),
  public.bsmart_thesis_publish(uuid, uuid, text), public.bsmart_thesis_like(uuid, uuid, boolean) to service_role;
commit;

-- Manual compatibility repair after 202610010002. Safe to rerun; no historical sends.
begin;
update public.bsmart_activity_push_settings set enabled=false where singleton;
create or replace function public.bsmart_activity_push_configure(p_enabled boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_enabled is null then return false; end if;
  update public.bsmart_activity_push_settings set enabled=p_enabled where singleton;
  return true;
end; $$;

create or replace function public.bsmart_activity_push_matches(p_device uuid,p_user uuid,p_actor text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.bsmart_push_devices d where d.id=p_device
    and d.user_id=p_user and d.enabled and d.environment='production'
    and d.updated_at>now()-interval '30 days' and d.notify_authors
    and lower(p_actor)=any(d.followed_author_ids)
    and not exists(select 1 from public.bsmart_push_devices newer
      where newer.user_id=d.user_id and newer.enabled and newer.environment='production'
        and (newer.updated_at,newer.id)>(d.updated_at,d.id)));
$$;

create or replace function public.bsmart_activity_push_enqueue(p_publication text,p_events jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare queued integer; unseen jsonb;
begin
  if jsonb_typeof(p_events)<>'array' or jsonb_array_length(p_events)>20000
    or p_publication is null or length(p_publication)>160 then raise exception 'Invalid push publication'; end if;
  -- Shared identity ledger prevents reintroduced data and unselected candidates being replayed.
  perform pg_catalog.pg_advisory_xact_lock(721534917);
  with candidates as (
    select distinct on(e.event_kind,e.event_id) e.*
    from jsonb_to_recordset(p_events) as e(event_kind text,event_id text,actor_id text,
      actor_name text,ticker text,body text,follow_return numeric,published_at timestamptz)
    where e.event_kind in ('subject','native_post','native_trade')
      and length(e.event_id) between 1 and 1024 and length(e.actor_id) between 1 and 160
      and length(e.actor_name) between 1 and 160 and e.ticker ~ '^[A-Z][A-Z0-9.]{0,19}$'
      and length(trim(e.body)) between 1 and 8000 and e.published_at<=now()
      and (e.follow_return is null or e.follow_return::text not in ('NaN','Infinity','-Infinity'))
    order by e.event_kind,e.event_id,e.published_at desc
  ), fresh as (
    insert into public.bsmart_activity_push_seen(event_kind,event_id)
    select event_kind,event_id from candidates on conflict do nothing returning *
  ) select coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb) into unseen
    from candidates c join fresh f using(event_kind,event_id);
  if not (select enabled from public.bsmart_activity_push_settings where singleton) then return 0; end if;
  with events as (
    select e.*,coalesce(e.follow_return,m.follow_return) as ranking_return
    from jsonb_to_recordset(unseen) as e(event_kind text,event_id text,actor_id text,
      actor_name text,ticker text,body text,follow_return numeric,published_at timestamptz)
    left join public.bsmart_push_return_metrics m on m.actor_id=lower(e.actor_id)
  ), matched as (
    select distinct d.user_id,e.* from events e join public.bsmart_push_devices d
      on public.bsmart_activity_push_matches(d.id,d.user_id,e.actor_id)
    where not exists(select 1 from public.bsmart_activity_push_outbox o
      where o.user_id=d.user_id and o.event_kind=e.event_kind and o.event_id=e.event_id)
  ), latest as (
    select distinct on(user_id,actor_id) * from matched where event_kind='subject'
    order by user_id,actor_id,published_at desc,event_id
  ), ranked as (
    select *,row_number() over(partition by user_id order by ranking_return desc nulls last,
      published_at desc,actor_id,event_id) as place from latest
  ), selected as (
    select user_id,event_kind,event_id,actor_id,actor_name,ticker,body,ranking_return from ranked where place<=2
    union all
    select user_id,event_kind,event_id,actor_id,actor_name,ticker,body,ranking_return from matched
      where event_kind in ('native_post','native_trade')
  ) insert into public.bsmart_activity_push_outbox
    (user_id,publication,event_kind,event_id,actor_id,actor_name,ticker,body,follow_return)
    select user_id,p_publication,event_kind,event_id,lower(actor_id),actor_name,ticker,body,ranking_return
    from selected on conflict(user_id,event_kind,event_id) do nothing;
  get diagnostics queued=row_count;
  if queued>0 then
    begin perform public.bsmart_push_run_worker();
    exception when others then null; -- Confirmed data must survive a wake-up failure; cron drains it.
    end;
  end if;
  return queued;
end; $$;

create or replace function public.bsmart_activity_push_claim()
returns jsonb language plpgsql security definer set search_path='' as $$
declare item record; device record;
begin
  if not (select enabled from public.bsmart_activity_push_settings where singleton) then return null; end if;
  update public.bsmart_activity_push_outbox o set state='skipped' where state='pending'
    and (expires_at<=now() or not exists(select 1 from public.bsmart_push_devices d
      where public.bsmart_activity_push_matches(d.id,o.user_id,o.actor_id))
      or (o.event_kind like 'native_%' and not exists(select 1 from public.bsmart_feed_profiles p
        where 'bsmart:'||p.public_id::text=o.actor_id and p.visible and p.feed_visible)));
  select * into item from public.bsmart_activity_push_outbox where state='pending'
    order by created_at,id limit 1 for update skip locked;
  if not found then return null; end if;
  select * into device from public.bsmart_push_devices d
    where public.bsmart_activity_push_matches(d.id,item.user_id,item.actor_id)
    order by updated_at desc,id limit 1;
  if not found then return null; end if;
  update public.bsmart_activity_push_outbox set state='sending',attempts=1,
    device_id=device.id,device_updated_at=device.updated_at where id=item.id;
  return jsonb_build_object('user_id',item.user_id,'device_id',device.id,'apns_id',item.apns_id,
    'apns_token',device.apns_token,'environment',device.environment,'locale',device.locale,
    'device_updated_at',device.updated_at,'slot_at',item.created_at,'item_count',1,
    'notice',jsonb_build_object('id',item.id,'eventKind',item.event_kind,'eventID',item.event_id,
      'actorID',item.actor_id,'actorName',item.actor_name,'ticker',item.ticker,'body',item.body,
      'expiresAt',item.expires_at));
end; $$;

create or replace function public.bsmart_activity_push_complete(p_id uuid,p_apns_id uuid,p_status integer,p_invalid boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare item record;
begin
  if p_status is not null and p_status not between 100 and 599 then return false; end if;
  if p_invalid is null or (p_invalid and (p_status is null or p_status not in(400,410))) then return false; end if;
  update public.bsmart_activity_push_outbox set state=case when p_status=200 then 'accepted' else 'failed' end,
    last_status=p_status where id=p_id and apns_id=p_apns_id and state='sending' returning * into item;
  if not found then return false; end if;
  if p_invalid then update public.bsmart_push_devices set enabled=false where id=item.device_id
    and user_id=item.user_id and updated_at=item.device_updated_at; end if;
  return true;
end; $$;

create or replace function public.bsmart_activity_push_platform_key(p_event jsonb)
returns text language sql immutable set search_path='' as $$
  select case when coalesce(p_event->>'sourcePostId','')<>'' then
    jsonb_build_array(lower(p_event->>'authorId'),p_event->>'sourcePostId',upper(p_event->>'ticker'))::text
    else p_event->>'id' end;
$$;

create or replace function public.bsmart_activity_push_continue()
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if (select enabled from public.bsmart_activity_push_settings where singleton)
    and exists(select 1 from public.bsmart_activity_push_outbox where state='pending' and expires_at>now()) then
    perform public.bsmart_push_run_worker(); return true;
  end if;
  return false;
end; $$;

create or replace function public.bsmart_activity_push_content_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare events jsonb; provenance jsonb;
begin
  if tg_op='INSERT' or new.revision=old.revision or new.channel<>'production' then return new; end if;
  select r.provenance into provenance from public.bsmart_content_releases r where r.revision=new.revision;
  if provenance->>'kind' is null or provenance->>'kind' not in ('daily-x','platform-refresh')
    or (select r.created_at from public.bsmart_content_releases r where r.revision=new.revision)
      <=(select r.created_at from public.bsmart_content_releases r where r.revision=old.revision)
    then return new; end if;
  with prior as (
    select distinct public.bsmart_activity_push_platform_key(e) as id
    from public.bsmart_content_pages p cross join lateral jsonb_array_elements(p.payload->'items') e
    where p.revision=old.revision and p.collection in ('smart-account-updates','smart-account-evidence')
  ), current_events as (
    select distinct on(public.bsmart_activity_push_platform_key(e)) e from public.bsmart_content_pages p
    cross join lateral jsonb_array_elements(p.payload->'items') e
    where p.revision=new.revision and p.collection='smart-account-updates'
    order by public.bsmart_activity_push_platform_key(e)
  ) select coalesce(jsonb_agg(jsonb_build_object('event_kind','subject',
    'event_id',public.bsmart_activity_push_platform_key(e),'actor_id',lower(e->>'authorId'),
    'actor_name',left(e->>'authorName',160),'ticker',upper(e->>'ticker'),
    'body',left(e->>'originalText',8000),'published_at',e->>'publishedAt')), '[]'::jsonb) into events
    from current_events where not exists(select 1 from prior where prior.id=public.bsmart_activity_push_platform_key(e))
      and lower(coalesce(e->>'platform',''))<>'bsmart';
  perform public.bsmart_activity_push_enqueue(new.revision,events);
  return new;
end; $$;

create or replace function public.bsmart_activity_push_subject_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare events jsonb;
begin
  if tg_op='INSERT' or new.channel<>'production'
    or current_setting('bsmart.push_suppress',true)='true' then return new; end if;
  with prior as (select e->>'id' as id from jsonb_array_elements(old.payload->'events') e),
  subjects as (select s->>'id' as id,s->>'name' as name,
    case when jsonb_typeof(s->'research'->'meanOpenReturn')='number'
      then (s->'research'->>'meanOpenReturn')::numeric else null end as follow_return
    from jsonb_array_elements(new.payload->'subjects') s)
  select coalesce(jsonb_agg(jsonb_build_object('event_kind','subject','event_id',e->>'id',
    'actor_id',lower(s.id),'actor_name',left(s.name,160),'ticker',upper(e->>'ticker'),
    'body',left(coalesce(nullif(e->>'originalText',''),nullif(e->>'summary',''),
      concat_ws(' · ',e->>'action',e->>'amountRange',e->>'assetDescription',e->>'assetName')),8000),
    'follow_return',s.follow_return,'published_at',(e->>'displayDay')||'T00:00:00Z')), '[]'::jsonb)
    into events from jsonb_array_elements(new.payload->'events') e join subjects s on s.id=e->>'subjectID'
    where not exists(select 1 from prior where prior.id=e->>'id') and coalesce(e->>'isSample','false')='false';
  perform public.bsmart_activity_push_enqueue('subjects:'||md5(new.payload::text),events);
  return new;
end; $$;

create or replace function public.bsmart_activity_push_trade_body(p_intent jsonb,p_execution jsonb)
returns text language plpgsql immutable set search_path='' as $$
declare value numeric; action text; dollars text;
begin
  if p_execution->>'notionalUSD' !~ '^[0-9]{1,20}(\.[0-9]{1,36})?$'
    or p_execution->>'side' not in ('long','short') or p_intent->>'ticker' !~ '^[A-Z][A-Z0-9.]{0,19}$' then return null; end if;
  value:=(p_execution->>'notionalUSD')::numeric;
  if value<=0 then return null; end if;
  dollars:=case when value<0.01 then '<0.01' else trim(trailing '.' from trim(trailing '0' from round(value,2)::text)) end;
  action:=case when p_intent->>'reduceOnly'='true' then
    case when p_execution->>'side'='long' then '平空了' else '平多了' end
    else case when p_execution->>'side'='long' then '做多了' else '做空了' end end;
  return action||'$'||dollars||'的$'||(p_intent->>'ticker')||'仓位';
end; $$;

create or replace function public.bsmart_activity_push_native_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare o public.bsmart_feed_orders; p public.bsmart_feed_profiles; kind text; event_key text; body text;
  published timestamptz;
begin
  if tg_table_name='bsmart_trade_theses' then
    select * into o from public.bsmart_feed_orders where id=new.trade_id;
    kind:='native_post'; event_key:=new.trade_id::text; published:=new.published_at;
  else
    if tg_op='UPDATE' and old.execution is not null then return new; end if;
    o:=new; kind:='native_trade'; event_key:=new.id::text; published:=o.executed_at;
  end if;
  if o.execution is null or o.executed_at is null then return new; end if;
  select * into p from public.bsmart_feed_profiles where account_id=o.account_id and visible and feed_visible;
  if not found then return new; end if;
  body:=public.bsmart_activity_push_trade_body(o.intent,o.execution);
  if body is null then return new; end if;
  perform public.bsmart_activity_push_enqueue(kind||':'||event_key,jsonb_build_array(jsonb_build_object(
    'event_kind',kind,'event_id',event_key,'actor_id','bsmart:'||p.public_id::text,
    'actor_name',p.nickname,'ticker',o.intent->>'ticker','body',body,
    'published_at',published)));
  return new;
end; $$;
-- Establish the deployment baseline without dispatching existing content.
insert into public.bsmart_activity_push_seen(event_kind,event_id)
select 'subject',public.bsmart_activity_push_platform_key(e)
from public.bsmart_content_pages p join public.bsmart_content_active a on a.revision=p.revision
cross join lateral jsonb_array_elements(p.payload->'items') e
where a.channel='production' and p.collection in ('smart-account-updates','smart-account-evidence')
  and length(public.bsmart_activity_push_platform_key(e)) between 1 and 1024
on conflict do nothing;
insert into public.bsmart_activity_push_seen(event_kind,event_id)
select 'subject',e->>'id' from public.bsmart_subject_activity_snapshots s
cross join lateral jsonb_array_elements(s.payload->'events') e
where s.channel='production' and length(e->>'id') between 1 and 1024 on conflict do nothing;
insert into public.bsmart_activity_push_seen(event_kind,event_id)
select 'native_trade',id::text from public.bsmart_feed_orders where execution is not null
union all select 'native_post',trade_id::text from public.bsmart_trade_theses on conflict do nothing;


revoke all on function public.bsmart_activity_push_configure(boolean),
  public.bsmart_activity_push_matches(uuid,uuid,text),public.bsmart_activity_push_enqueue(text,jsonb),
  public.bsmart_activity_push_claim(),public.bsmart_activity_push_complete(uuid,uuid,integer,boolean),
  public.bsmart_activity_push_continue(),
  public.bsmart_activity_push_content_changed(),public.bsmart_activity_push_subject_changed(),
  public.bsmart_activity_push_native_changed(),public.bsmart_activity_push_platform_key(jsonb),
  public.bsmart_activity_push_trade_body(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.bsmart_activity_push_configure(boolean),
  public.bsmart_activity_push_claim(),public.bsmart_activity_push_complete(uuid,uuid,integer,boolean),
  public.bsmart_activity_push_continue() to service_role;

select cron.schedule('bsmart-content-push','* * * * *','select public.bsmart_push_run_worker();');
commit;

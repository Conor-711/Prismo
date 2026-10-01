begin;

create or replace function public.bsmart_subject_activity_read(p_subject_id text default null)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select jsonb_set(
    jsonb_set(
      payload,
      '{subjects}',
      case when p_subject_id is null then payload->'subjects'
           else coalesce((
             select jsonb_agg(subject)
             from jsonb_array_elements(payload->'subjects') as subject
             where subject->>'id' = p_subject_id
           ), '[]'::jsonb)
      end
    ),
    '{events}',
    coalesce((
      select jsonb_agg(event order by ordinal)
      from jsonb_array_elements(payload->'events') with ordinality as entries(event, ordinal)
      where (p_subject_id is null and event->>'displayDay' >= (current_date - 400)::text)
         or (p_subject_id is not null and event->>'subjectID' = p_subject_id)
    ), '[]'::jsonb)
  )
  from public.bsmart_subject_activity_snapshots
  where channel = 'production';
$$;

revoke all on function public.bsmart_subject_activity_read(text) from public, anon, authenticated;
grant execute on function public.bsmart_subject_activity_read(text) to service_role;

commit;

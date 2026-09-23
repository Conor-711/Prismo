begin;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

do $$ begin
  if not exists (select 1 from vault.secrets where name = 'bsmart_across_worker_token') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'bsmart_across_worker_token');
  end if;
end $$;

create function public.bsmart_across_worker_authorized(p_token text)
returns boolean language sql security definer set search_path = '' as $$
  select length(p_token) = 64 and exists (
    select 1 from vault.decrypted_secrets where name = 'bsmart_across_worker_token'
      and extensions.digest(decrypted_secret, 'sha256') = extensions.digest(p_token, 'sha256')
  );
$$;

create function public.bsmart_across_run_worker()
returns bigint language sql security definer set search_path = '' as $$
  select net.http_post(
    url := 'https://dzyitinagewdfkzjkuiz.supabase.co/functions/v1/bsmart-withdrawals/reconcile',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'bsmart_across_worker_token')),
    body := '{}'::jsonb, timeout_milliseconds := 30000
  );
$$;

revoke all on function public.bsmart_across_worker_authorized(text) from public, anon, authenticated;
revoke all on function public.bsmart_across_run_worker() from public, anon, authenticated;
grant execute on function public.bsmart_across_worker_authorized(text) to service_role;
grant execute on function public.bsmart_across_run_worker() to service_role;

select cron.schedule('bsmart-across-reconcile', '* * * * *',
  'select public.bsmart_across_run_worker();');

commit;

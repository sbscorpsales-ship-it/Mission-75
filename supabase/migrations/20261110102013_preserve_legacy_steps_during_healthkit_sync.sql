-- Preserve pre-provenance daily step entries when HealthKit sync runs.
-- Only replace a previous HealthKit value, or fill an actually empty step field.
create or replace function public.sync_healthkit_daily_steps(
  p_log_date date,
  p_steps integer,
  p_updated_at timestamptz default now()
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;
  if p_log_date is null or p_steps is null or p_steps < 0 then
    raise exception 'A valid date and non-negative step count are required';
  end if;

  insert into public.daily_logs (
    user_id, log_date, steps, steps_source, steps_updated_at
  )
  values (
    v_user_id, p_log_date, p_steps, 'apple_health', coalesce(p_updated_at, now())
  )
  on conflict (user_id, log_date)
  do update set
    steps = excluded.steps,
    steps_source = 'apple_health',
    steps_updated_at = excluded.steps_updated_at
  where public.daily_logs.steps_source = 'apple_health'
     or (
       public.daily_logs.steps_source is null
       and public.daily_logs.steps is null
     );
end;
$$;

revoke all on function public.sync_healthkit_daily_steps(date, integer, timestamptz) from public;
grant execute on function public.sync_healthkit_daily_steps(date, integer, timestamptz) to authenticated;

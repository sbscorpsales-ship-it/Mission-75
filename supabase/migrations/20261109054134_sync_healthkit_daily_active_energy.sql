-- Preserve HealthKit active-energy measurements separately from steps and estimated calories.
alter table public.daily_logs
  add column if not exists active_energy_kcal integer,
  add column if not exists active_energy_source text,
  add column if not exists active_energy_updated_at timestamptz;

alter table public.daily_logs
  add constraint daily_logs_active_energy_nonnegative
  check (active_energy_kcal is null or active_energy_kcal >= 0);

create or replace function public.sync_healthkit_daily_energy(
  p_log_date date,
  p_active_energy_kcal integer,
  p_updated_at timestamptz default now()
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_log_date is null or p_active_energy_kcal is null or p_active_energy_kcal < 0 then
    raise exception 'A valid date and non-negative active energy value are required';
  end if;

  insert into public.daily_logs (
    user_id, log_date, active_energy_kcal, active_energy_source, active_energy_updated_at
  )
  values (
    auth.uid(), p_log_date, p_active_energy_kcal, 'apple_health', coalesce(p_updated_at, now())
  )
  on conflict (user_id, log_date) do update
  set active_energy_kcal = excluded.active_energy_kcal,
      active_energy_source = excluded.active_energy_source,
      active_energy_updated_at = excluded.active_energy_updated_at
  where public.daily_logs.active_energy_updated_at is null
     or excluded.active_energy_updated_at >= public.daily_logs.active_energy_updated_at;
end;
$$;

revoke all on function public.sync_healthkit_daily_energy(date, integer, timestamptz) from public;
revoke all on function public.sync_healthkit_daily_energy(date, integer, timestamptz) from anon;
grant execute on function public.sync_healthkit_daily_energy(date, integer, timestamptz) to authenticated;

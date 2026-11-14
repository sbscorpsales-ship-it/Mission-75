-- GATIVX measured sleep sync. Additive only: existing daily_logs and legacy values remain intact.
alter table public.daily_logs
  add column if not exists sleep_minutes integer,
  add column if not exists sleep_source text,
  add column if not exists sleep_updated_at timestamptz;

comment on column public.daily_logs.sleep_minutes is
  'Measured asleep duration for the local wake-up day, in minutes; null means unavailable.';
comment on column public.daily_logs.sleep_source is
  'Origin of measured sleep duration: apple_health or health_connect.';
comment on column public.daily_logs.sleep_updated_at is
  'Timestamp of the latest measured sleep sync.';

create or replace function public.sync_health_sleep(
  p_log_date date,
  p_sleep_minutes integer,
  p_source text,
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
  if p_log_date is null or p_sleep_minutes is null or p_sleep_minutes < 0 or p_sleep_minutes > 1440 then
    raise exception 'A valid local date and sleep duration between 0 and 1440 minutes are required';
  end if;
  if p_source not in ('apple_health', 'health_connect') then
    raise exception 'Unsupported sleep data source';
  end if;

  insert into public.daily_logs (
    user_id, log_date, sleep_minutes, sleep_source, sleep_updated_at
  )
  values (
    auth.uid(), p_log_date, p_sleep_minutes, p_source, coalesce(p_updated_at, now())
  )
  on conflict (user_id, log_date) do update
  set sleep_minutes = excluded.sleep_minutes,
      sleep_source = excluded.sleep_source,
      sleep_updated_at = excluded.sleep_updated_at
  where public.daily_logs.sleep_source is distinct from 'manual'
    and (
      public.daily_logs.sleep_updated_at is null
      or excluded.sleep_updated_at >= public.daily_logs.sleep_updated_at
    );
end;
$$;

revoke all on function public.sync_health_sleep(date, integer, text, timestamptz) from public;
revoke all on function public.sync_health_sleep(date, integer, text, timestamptz) from anon;
grant execute on function public.sync_health_sleep(date, integer, text, timestamptz) to authenticated;

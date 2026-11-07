-- Keep iPhone CoreMotion daily observations separate from HealthKit's
-- aggregated daily total. Never let a device-only counter overwrite daily_logs.
create table if not exists public.motion_daily_steps (
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,
  steps integer not null check (steps >= 0 and steps <= 200000),
  distance_m numeric,
  source text not null default 'core_motion' check (source = 'core_motion'),
  measured_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, log_date)
);
alter table public.motion_daily_steps enable row level security;
drop policy if exists "Users can read own motion daily steps" on public.motion_daily_steps;
create policy "Users can read own motion daily steps" on public.motion_daily_steps for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can insert own motion daily steps" on public.motion_daily_steps;
create policy "Users can insert own motion daily steps" on public.motion_daily_steps for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update own motion daily steps" on public.motion_daily_steps;
create policy "Users can update own motion daily steps" on public.motion_daily_steps for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update on public.motion_daily_steps to authenticated;
create or replace function public.sync_motion_daily_steps(p_log_date date,p_steps integer,p_updated_at timestamptz default now(),p_distance_m numeric default null)
returns void language plpgsql security invoker set search_path = public as $$
declare v_user_id uuid := auth.uid();
begin
 if v_user_id is null then raise exception 'Authentication required'; end if;
 if p_log_date is null or p_steps is null or p_steps < 0 or p_steps > 200000 then raise exception 'A valid date and non-negative motion step count are required'; end if;
 if p_distance_m is not null and (p_distance_m < 0 or p_distance_m > 1000000) then raise exception 'Invalid motion distance'; end if;
 insert into public.motion_daily_steps(user_id,log_date,steps,distance_m,source,measured_at,updated_at)
 values(v_user_id,p_log_date,p_steps,p_distance_m,'core_motion',coalesce(p_updated_at,now()),now())
 on conflict(user_id,log_date) do update set steps=excluded.steps,distance_m=excluded.distance_m,measured_at=excluded.measured_at,updated_at=now()
 where public.motion_daily_steps.measured_at <= excluded.measured_at;
end; $$;
revoke all on function public.sync_motion_daily_steps(date,integer,timestamptz,numeric) from public;
grant execute on function public.sync_motion_daily_steps(date,integer,timestamptz,numeric) to authenticated;

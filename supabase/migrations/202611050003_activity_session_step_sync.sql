-- Store activity-specific step counts separately from daily HealthKit totals.
-- This prevents double-counting: daily_logs remains the daily aggregate.
create table if not exists public.activity_sessions (
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null,
  activity text not null,
  started_at timestamptz not null,
  finished_at timestamptz not null,
  steps integer not null check (steps >= 0),
  source text not null default 'core_motion',
  created_at timestamptz not null default now(),
  primary key (user_id, session_id),
  check (finished_at >= started_at)
);
alter table public.activity_sessions enable row level security;
drop policy if exists "Users can read their own activity sessions" on public.activity_sessions;
create policy "Users can read their own activity sessions" on public.activity_sessions for select to authenticated using (auth.uid() = user_id);
drop policy if exists "Users can insert their own activity sessions" on public.activity_sessions;
create policy "Users can insert their own activity sessions" on public.activity_sessions for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update their own activity sessions" on public.activity_sessions;
create policy "Users can update their own activity sessions" on public.activity_sessions for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create or replace function public.sync_activity_session_steps(p_session_id uuid, p_activity text, p_started_at timestamptz, p_finished_at timestamptz, p_steps integer)
returns void language plpgsql security invoker set search_path = public as $$
declare v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_session_id is null or p_activity is null or length(trim(p_activity)) = 0 or p_started_at is null or p_finished_at is null or p_finished_at < p_started_at or p_steps is null or p_steps < 0 then
    raise exception 'Invalid activity session data';
  end if;
  insert into public.activity_sessions(user_id, session_id, activity, started_at, finished_at, steps)
  values (v_user_id, p_session_id, trim(p_activity), p_started_at, p_finished_at, p_steps)
  on conflict (user_id, session_id) do update set activity=excluded.activity, started_at=excluded.started_at, finished_at=excluded.finished_at, steps=excluded.steps;
end; $$;
revoke all on function public.sync_activity_session_steps(uuid,text,timestamptz,timestamptz,integer) from public;
grant execute on function public.sync_activity_session_steps(uuid,text,timestamptz,timestamptz,integer) to authenticated;

-- Persist native activity sessions with account-scoped ownership.
-- This migration is checked into source to reproduce the already-applied
-- activity-session schema in fresh/staging databases. It is not being applied
-- to the production project by this change.

create table public.activity_sessions (
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid not null,
    activity text not null,
    started_at timestamptz not null,
    finished_at timestamptz not null,
    steps integer not null,
    source text not null default 'core_motion',
    created_at timestamptz not null default now(),
    route_points jsonb not null default '[]'::jsonb,
    constraint activity_sessions_pkey primary key (user_id, session_id),
    constraint activity_sessions_check check (finished_at >= started_at),
    constraint activity_sessions_steps_check check (steps >= 0)
);

alter table public.activity_sessions enable row level security;

create policy "Users can insert their own activity sessions"
    on public.activity_sessions
    for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users can read their own activity sessions"
    on public.activity_sessions
    for select
    to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can update their own activity sessions"
    on public.activity_sessions
    for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on table public.activity_sessions to authenticated;
grant all on table public.activity_sessions to service_role;

create or replace function public.sync_activity_session_steps(
    p_session_id uuid,
    p_activity text,
    p_started_at timestamptz,
    p_finished_at timestamptz,
    p_steps integer
)
returns void
language plpgsql
security invoker
set search_path = public
as $function$
declare
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null then
        raise exception 'Authentication required';
    end if;

    if p_session_id is null
       or p_activity is null
       or length(trim(p_activity)) = 0
       or p_started_at is null
       or p_finished_at is null
       or p_finished_at < p_started_at
       or p_steps is null
       or p_steps < 0 then
        raise exception 'Invalid activity session data';
    end if;

    insert into public.activity_sessions (
        user_id, session_id, activity, started_at, finished_at, steps
    )
    values (
        v_user_id, p_session_id, trim(p_activity), p_started_at, p_finished_at, p_steps
    )
    on conflict (user_id, session_id) do update
    set activity = excluded.activity,
        started_at = excluded.started_at,
        finished_at = excluded.finished_at,
        steps = excluded.steps;
end;
$function$;

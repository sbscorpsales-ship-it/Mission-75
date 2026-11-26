-- Keep daily action progress member-scoped and remove table privileges that bypass RLS.
-- RLS does not apply to TRUNCATE, so CRUD grants alone must be explicit.
-- CREATE TABLE IF NOT EXISTS also makes this table reproducible on a fresh database;
-- the full historical migration chain still needs to be reconciled separately.

create table if not exists public.daily_action_progress (
    user_id uuid not null references auth.users(id) on delete cascade,
    action_date date not null,
    completed jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now(),
    constraint daily_action_progress_completed_object
        check (jsonb_typeof(completed) = 'object'),
    constraint daily_action_progress_pkey primary key (user_id, action_date)
);

alter table public.daily_action_progress enable row level security;

drop policy if exists "Members can read own daily action progress"
    on public.daily_action_progress;
create policy "Members can read own daily action progress"
    on public.daily_action_progress
    for select
    to authenticated
    using ((select auth.uid()) = user_id);

drop policy if exists "Members can insert own daily action progress"
    on public.daily_action_progress;
create policy "Members can insert own daily action progress"
    on public.daily_action_progress
    for insert
    to authenticated
    with check ((select auth.uid()) = user_id);

drop policy if exists "Members can update own daily action progress"
    on public.daily_action_progress;
create policy "Members can update own daily action progress"
    on public.daily_action_progress
    for update
    to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

drop policy if exists "Members can delete own daily action progress"
    on public.daily_action_progress;
create policy "Members can delete own daily action progress"
    on public.daily_action_progress
    for delete
    to authenticated
    using ((select auth.uid()) = user_id);

-- Remove broad defaults, including TRUNCATE/TRIGGER/REFERENCES. Those are not
-- protected by row-level policies. The authenticated client needs CRUD only.
revoke all privileges on table public.daily_action_progress from public, anon;
revoke all privileges on table public.daily_action_progress from authenticated;
grant select, insert, update, delete
    on table public.daily_action_progress to authenticated;

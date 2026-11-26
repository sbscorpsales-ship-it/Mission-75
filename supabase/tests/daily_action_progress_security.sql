-- Standalone PostgreSQL security regression test.
-- Run after the migration with:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/daily_action_progress_security.sql

do $$
declare
    v_rls_enabled boolean;
    v_policy_count integer;
begin
    select relrowsecurity into v_rls_enabled
    from pg_class
    where oid = 'public.daily_action_progress'::regclass;

    if not coalesce(v_rls_enabled, false) then
        raise exception 'RLS must be enabled on daily_action_progress';
    end if;

    if has_table_privilege('anon', 'public.daily_action_progress', 'SELECT')
       or has_table_privilege('anon', 'public.daily_action_progress', 'INSERT')
       or has_table_privilege('anon', 'public.daily_action_progress', 'UPDATE')
       or has_table_privilege('anon', 'public.daily_action_progress', 'DELETE')
       or has_table_privilege('anon', 'public.daily_action_progress', 'TRUNCATE')
       or has_table_privilege('anon', 'public.daily_action_progress', 'TRIGGER')
       or has_table_privilege('anon', 'public.daily_action_progress', 'REFERENCES') then
        raise exception 'anon must have no table privileges on daily_action_progress';
    end if;

    if has_table_privilege('authenticated', 'public.daily_action_progress', 'TRUNCATE')
       or has_table_privilege('authenticated', 'public.daily_action_progress', 'TRIGGER')
       or has_table_privilege('authenticated', 'public.daily_action_progress', 'REFERENCES') then
        raise exception 'authenticated must not have TRUNCATE, TRIGGER or REFERENCES privileges';
    end if;

    if not has_table_privilege('authenticated', 'public.daily_action_progress', 'SELECT')
       or not has_table_privilege('authenticated', 'public.daily_action_progress', 'INSERT')
       or not has_table_privilege('authenticated', 'public.daily_action_progress', 'UPDATE')
       or not has_table_privilege('authenticated', 'public.daily_action_progress', 'DELETE') then
        raise exception 'authenticated must retain CRUD privileges';
    end if;

    select count(*) into v_policy_count
    from pg_policies
    where schemaname = 'public'
      and tablename = 'daily_action_progress'
      and policyname in (
          'Members can read own daily action progress',
          'Members can insert own daily action progress',
          'Members can update own daily action progress',
          'Members can delete own daily action progress'
      );

    if v_policy_count <> 4 then
        raise exception 'Expected four member-scoped daily_action_progress policies, found %', v_policy_count;
    end if;
end;
$$;

insert into auth.users (id)
values
    ('00000000-0000-4000-8000-000000000001'),
    ('00000000-0000-4000-8000-000000000002')
on conflict (id) do nothing;

insert into public.daily_action_progress (user_id, action_date, completed)
values
    ('00000000-0000-4000-8000-000000000001', date '2026-11-26', '{"walk": true}'::jsonb),
    ('00000000-0000-4000-8000-000000000002', date '2026-11-26', '{"walk": true}'::jsonb)
on conflict (user_id, action_date) do update
set completed = excluded.completed;

set role anon;
do $$
begin
    begin
        perform 1 from public.daily_action_progress;
        raise exception 'anon unexpectedly read daily_action_progress';
    exception when insufficient_privilege then
        null;
    end;
end;
$$;
reset role;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
do $$
declare
    v_visible_rows integer;
begin
    select count(*) into v_visible_rows from public.daily_action_progress;
    if v_visible_rows <> 1 then
        raise exception 'authenticated member must see only their own row; saw %', v_visible_rows;
    end if;

    update public.daily_action_progress
       set completed = '{"walk": false}'::jsonb
     where user_id = '00000000-0000-4000-8000-000000000002';
    if found then
        raise exception 'cross-member UPDATE unexpectedly changed a row';
    end if;

    delete from public.daily_action_progress
     where user_id = '00000000-0000-4000-8000-000000000002';
    if found then
        raise exception 'cross-member DELETE unexpectedly removed a row';
    end if;

    begin
        insert into public.daily_action_progress (user_id, action_date, completed)
        values ('00000000-0000-4000-8000-000000000002', date '2026-11-27', '{}'::jsonb);
        raise exception 'cross-member INSERT unexpectedly succeeded';
    exception when insufficient_privilege then
        null;
    end;

    update public.daily_action_progress
       set completed = '{"walk": false}'::jsonb
     where user_id = '00000000-0000-4000-8000-000000000001'
       and action_date = date '2026-11-26';
    if not found then
        raise exception 'authenticated member could not update their own row';
    end if;

    if (select completed ->> 'walk'
          from public.daily_action_progress
         where user_id = '00000000-0000-4000-8000-000000000001'
           and action_date = date '2026-11-26') <> 'false' then
        raise exception 'authenticated member update did not persist on their own row';
    end if;

    insert into public.daily_action_progress (user_id, action_date, completed)
    values ('00000000-0000-4000-8000-000000000001', date '2026-11-27', '{"strength": true}'::jsonb);
    if not found then
        raise exception 'authenticated member could not insert their own row';
    end if;

    delete from public.daily_action_progress
     where user_id = '00000000-0000-4000-8000-000000000001'
       and action_date = date '2026-11-27';
    if not found then
        raise exception 'authenticated member could not delete their own row';
    end if;
end;
$;
reset role;

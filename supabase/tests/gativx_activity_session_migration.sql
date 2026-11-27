\set ON_ERROR_STOP on

INSERT INTO auth.users (id) VALUES
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

DO $schema_assertions$
DECLARE
    rls_enabled boolean;
    security_definer boolean;
    function_config text[];
    policy_count integer;
BEGIN
    SELECT c.relrowsecurity
      INTO rls_enabled
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'activity_sessions';

    IF NOT COALESCE(rls_enabled, false) THEN
        RAISE EXCEPTION 'activity_sessions must have row-level security enabled';
    END IF;

    SELECT p.prosecdef, p.proconfig
      INTO security_definer, function_config
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'sync_activity_session_steps';

    IF security_definer IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'sync_activity_session_steps must remain SECURITY INVOKER';
    END IF;

    IF function_config IS NULL OR NOT ('search_path=public' = ANY(function_config)) THEN
        RAISE EXCEPTION 'sync_activity_session_steps must pin search_path to public';
    END IF;

    SELECT count(*)
      INTO policy_count
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'activity_sessions'
       AND cmd IN ('INSERT', 'SELECT', 'UPDATE')
       AND roles::text = '{authenticated}';

    IF policy_count <> 3 THEN
        RAISE EXCEPTION 'Expected exactly three authenticated owner policies, found %', policy_count;
    END IF;

    IF has_function_privilege(
        'anon',
        'public.sync_activity_session_steps(uuid,text,timestamptz,timestamptz,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'anon must not execute the activity-session RPC';
    END IF;

    IF NOT has_function_privilege(
        'authenticated',
        'public.sync_activity_session_steps(uuid,text,timestamptz,timestamptz,integer)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'authenticated must execute the activity-session RPC';
    END IF;

    IF has_table_privilege('anon', 'public.activity_sessions', 'SELECT')
       OR has_table_privilege('anon', 'public.activity_sessions', 'INSERT')
       OR has_table_privilege('anon', 'public.activity_sessions', 'UPDATE')
       OR has_table_privilege('anon', 'public.activity_sessions', 'DELETE') THEN
        RAISE EXCEPTION 'anon must not receive direct activity-session table access';
    END IF;
END;
$schema_assertions$;

-- The same session UUID must upsert within one owner, not create duplicates.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false);

SELECT public.sync_activity_session_steps(
    '11111111-1111-4111-8111-111111111111',
    'Walking',
    '2026-11-27T10:00:00Z',
    '2026-11-27T10:30:00Z',
    10
);

SELECT public.sync_activity_session_steps(
    '11111111-1111-4111-8111-111111111111',
    'Hiking',
    '2026-11-27T10:00:00Z',
    '2026-11-27T10:35:00Z',
    15
);

DO $owner_a_assertions$
DECLARE
    visible_count integer;
    saved_steps integer;
    saved_activity text;
    saved_source text;
    saved_route_points jsonb;
BEGIN
    SELECT count(*) INTO visible_count FROM public.activity_sessions;
    SELECT steps, activity, source, route_points
      INTO saved_steps, saved_activity, saved_source, saved_route_points
      FROM public.activity_sessions
     LIMIT 1;

    IF visible_count <> 1 OR saved_steps <> 15 OR saved_activity <> 'Hiking' THEN
        RAISE EXCEPTION 'same-owner retry did not upsert the original activity session';
    END IF;

    IF saved_source <> 'core_motion' OR saved_route_points <> '[]'::jsonb THEN
        RAISE EXCEPTION 'activity-session defaults were not preserved';
    END IF;
END;
$owner_a_assertions$;

-- The same UUID under another account must remain a separate, invisible row.
SELECT set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', false);

SELECT public.sync_activity_session_steps(
    '11111111-1111-4111-8111-111111111111',
    'Running',
    '2026-11-27T11:00:00Z',
    '2026-11-27T11:20:00Z',
    20
);

DO $owner_b_assertions$
DECLARE
    visible_count integer;
    saved_steps integer;
    saved_owner uuid;
    changed_count integer;
BEGIN
    SELECT count(*) INTO visible_count FROM public.activity_sessions;
    SELECT steps, user_id INTO saved_steps, saved_owner
      FROM public.activity_sessions
     LIMIT 1;

    IF visible_count <> 1
       OR saved_steps <> 20
       OR saved_owner <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid THEN
        RAISE EXCEPTION 'account B can see data outside its own activity-session row';
    END IF;

    UPDATE public.activity_sessions
       SET steps = 999
     WHERE user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid
       AND session_id = '11111111-1111-4111-8111-111111111111'::uuid;
    GET DIAGNOSTICS changed_count = ROW_COUNT;

    IF changed_count <> 0 THEN
        RAISE EXCEPTION 'account B modified account A activity data';
    END IF;
END;
$owner_b_assertions$;

RESET ROLE;

DO $global_assertions$
DECLARE
    total_rows integer;
    distinct_owners integer;
BEGIN
    SELECT count(*), count(DISTINCT user_id)
      INTO total_rows, distinct_owners
      FROM public.activity_sessions;

    IF total_rows <> 2 OR distinct_owners <> 2 THEN
        RAISE EXCEPTION 'same session UUID must remain isolated across two owners';
    END IF;
END;
$global_assertions$;

-- The RPC must reject missing identity and invalid measurements before writing.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '', false);

DO $missing_identity$
DECLARE
    rejected boolean := false;
BEGIN
    BEGIN
        PERFORM public.sync_activity_session_steps(
            '22222222-2222-4222-8222-222222222222',
            'Walking',
            '2026-11-27T12:00:00Z',
            '2026-11-27T12:10:00Z',
            1
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM = 'Authentication required' THEN
            rejected := true;
        ELSE
            RAISE;
        END IF;
    END;

    IF NOT rejected THEN
        RAISE EXCEPTION 'activity-session RPC accepted a request without auth.uid()';
    END IF;
END;
$missing_identity$;

SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false);

DO $invalid_payloads$
DECLARE
    rejected boolean;
BEGIN
    rejected := false;
    BEGIN
        PERFORM public.sync_activity_session_steps(
            '33333333-3333-4333-8333-333333333333',
            'Walking',
            '2026-11-27T12:00:00Z',
            '2026-11-27T12:10:00Z',
            -1
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM = 'Invalid activity session data' THEN
            rejected := true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'negative steps were accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM public.sync_activity_session_steps(
            '44444444-4444-4444-8444-444444444444',
            'Walking',
            '2026-11-27T12:10:00Z',
            '2026-11-27T12:00:00Z',
            1
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM = 'Invalid activity session data' THEN
            rejected := true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'finish-before-start was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM public.sync_activity_session_steps(
            '55555555-5555-4555-8555-555555555555',
            '   ',
            '2026-11-27T12:00:00Z',
            '2026-11-27T12:10:00Z',
            1
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM = 'Invalid activity session data' THEN
            rejected := true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'blank activity name was accepted'; END IF;

    rejected := false;
    BEGIN
        PERFORM public.sync_activity_session_steps(
            '66666666-6666-4666-8666-666666666666',
            'Walking',
            '2026-11-27T12:00:00Z',
            '2026-11-27T12:10:00Z',
            NULL
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM = 'Invalid activity session data' THEN
            rejected := true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'unknown step count was written as a session total'; END IF;
END;
$invalid_payloads$;

RESET ROLE;

DO $no_invalid_rows$
DECLARE
    total_rows integer;
BEGIN
    SELECT count(*) INTO total_rows FROM public.activity_sessions;
    IF total_rows <> 2 THEN
        RAISE EXCEPTION 'invalid activity payloads changed the persisted session count';
    END IF;
END;
$no_invalid_rows$;

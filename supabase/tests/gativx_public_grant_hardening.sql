-- Run after the versioned migration and the supabase_admin default-ACL
-- action. This test intentionally fails while either excessive grant remains.

DO $gativx$
DECLARE
  anon_oid oid;
  authenticated_oid oid;
BEGIN
  SELECT oid INTO anon_oid FROM pg_roles WHERE rolname = 'anon';
  SELECT oid INTO authenticated_oid FROM pg_roles WHERE rolname = 'authenticated';
  IF anon_oid IS NULL OR authenticated_oid IS NULL THEN
    RAISE EXCEPTION 'Expected Supabase API roles are missing';
  END IF;

  IF has_table_privilege('anon', 'public.daily_action_progress', 'SELECT')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'INSERT')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'UPDATE')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'DELETE')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'TRUNCATE')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'REFERENCES')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'TRIGGER')
     OR has_table_privilege('anon', 'public.daily_action_progress', 'MAINTAIN') THEN
    RAISE EXCEPTION 'anon retains a privilege on public.daily_action_progress';
  END IF;

  IF NOT has_table_privilege('authenticated', 'public.daily_action_progress', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.daily_action_progress', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.daily_action_progress', 'UPDATE')
     OR NOT has_table_privilege('authenticated', 'public.daily_action_progress', 'DELETE') THEN
    RAISE EXCEPTION 'authenticated lost required CRUD access to daily_action_progress';
  END IF;

  IF has_table_privilege('authenticated', 'public.daily_action_progress', 'TRUNCATE')
     OR has_table_privilege('authenticated', 'public.daily_action_progress', 'REFERENCES')
     OR has_table_privilege('authenticated', 'public.daily_action_progress', 'TRIGGER')
     OR has_table_privilege('authenticated', 'public.daily_action_progress', 'MAINTAIN') THEN
    RAISE EXCEPTION 'authenticated retains a table-wide or unnecessary privilege';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) x
    WHERE d.defaclrole IN ('postgres'::regrole, 'supabase_admin'::regrole)
      AND d.defaclnamespace = 'public'::regnamespace
      AND d.defaclobjtype IN ('r', 'S', 'f')
      AND x.grantee IN (anon_oid, authenticated_oid)
  ) THEN
    RAISE EXCEPTION 'anon or authenticated still has broad public-schema default privileges';
  END IF;
END;
$gativx$;

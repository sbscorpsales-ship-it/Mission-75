-- Run after the versioned migration and the supabase_admin default-ACL
-- action. This test intentionally fails while any excessive grant remains.

-- Probe objects created after hardening must not inherit API-role access.
CREATE TABLE public.gativx_postgres_default_probe (id integer);
CREATE SEQUENCE public.gativx_postgres_default_sequence;
CREATE FUNCTION public.gativx_postgres_default_function()
RETURNS integer LANGUAGE sql AS 'SELECT 1';

SET ROLE supabase_admin;
CREATE TABLE public.gativx_supabase_admin_default_probe (id integer);
CREATE SEQUENCE public.gativx_supabase_admin_default_sequence;
CREATE FUNCTION public.gativx_supabase_admin_default_function()
RETURNS integer LANGUAGE sql AS 'SELECT 1';
RESET ROLE;

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

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND (
        has_table_privilege('anon', c.oid, 'SELECT')
        OR has_table_privilege('anon', c.oid, 'INSERT')
        OR has_table_privilege('anon', c.oid, 'UPDATE')
        OR has_table_privilege('anon', c.oid, 'DELETE')
        OR has_table_privilege('anon', c.oid, 'TRUNCATE')
        OR has_table_privilege('anon', c.oid, 'REFERENCES')
        OR has_table_privilege('anon', c.oid, 'TRIGGER')
        OR has_table_privilege('anon', c.oid, 'MAINTAIN')
      )
  ) THEN
    RAISE EXCEPTION 'anon retains a privilege on a private public-schema table';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND c.relname NOT IN (
        'gativx_postgres_default_probe',
        'gativx_supabase_admin_default_probe'
      )
      AND (
        NOT has_table_privilege('authenticated', c.oid, 'SELECT')
        OR NOT has_table_privilege('authenticated', c.oid, 'INSERT')
        OR NOT has_table_privilege('authenticated', c.oid, 'UPDATE')
        OR NOT has_table_privilege('authenticated', c.oid, 'DELETE')
      )
  ) THEN
    RAISE EXCEPTION 'authenticated lost required CRUD access to a GATIVX table';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'daily_action_progress'
      AND c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'daily_action_progress must retain row-level security';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p')
      AND (
        has_table_privilege('authenticated', c.oid, 'TRUNCATE')
        OR has_table_privilege('authenticated', c.oid, 'REFERENCES')
        OR has_table_privilege('authenticated', c.oid, 'TRIGGER')
        OR has_table_privilege('authenticated', c.oid, 'MAINTAIN')
      )
  ) THEN
    RAISE EXCEPTION 'authenticated retains a table-wide or administrative privilege';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'S'
      AND (
        has_sequence_privilege('anon', c.oid, 'USAGE')
        OR has_sequence_privilege('anon', c.oid, 'SELECT')
        OR has_sequence_privilege('anon', c.oid, 'UPDATE')
        OR has_sequence_privilege('authenticated', c.oid, 'USAGE')
        OR has_sequence_privilege('authenticated', c.oid, 'SELECT')
        OR has_sequence_privilege('authenticated', c.oid, 'UPDATE')
      )
  ) THEN
    RAISE EXCEPTION 'anon or authenticated retains public-schema sequence privileges';
  END IF;

  IF has_table_privilege('anon', 'public.gativx_postgres_default_probe', 'SELECT')
     OR has_table_privilege('authenticated', 'public.gativx_postgres_default_probe', 'SELECT')
     OR has_table_privilege('anon', 'public.gativx_supabase_admin_default_probe', 'SELECT')
     OR has_table_privilege('authenticated', 'public.gativx_supabase_admin_default_probe', 'SELECT') THEN
    RAISE EXCEPTION 'new tables still inherit API-role privileges';
  END IF;

  IF has_sequence_privilege('anon', 'public.gativx_postgres_default_sequence', 'USAGE')
     OR has_sequence_privilege('authenticated', 'public.gativx_postgres_default_sequence', 'USAGE')
     OR has_sequence_privilege('anon', 'public.gativx_supabase_admin_default_sequence', 'USAGE')
     OR has_sequence_privilege('authenticated', 'public.gativx_supabase_admin_default_sequence', 'USAGE') THEN
    RAISE EXCEPTION 'new sequences still inherit API-role privileges';
  END IF;

  IF has_function_privilege('anon', 'public.gativx_postgres_default_function()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.gativx_postgres_default_function()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.gativx_supabase_admin_default_function()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.gativx_supabase_admin_default_function()', 'EXECUTE') THEN
    RAISE EXCEPTION 'new functions still inherit API-role execution';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) x
    WHERE d.defaclrole IN ('postgres'::regrole, 'supabase_admin'::regrole)
      AND (d.defaclnamespace = 'public'::regnamespace OR d.defaclnamespace = 0)
      AND d.defaclobjtype IN ('r', 'S', 'f')
      AND x.grantee IN (0, anon_oid, authenticated_oid)
  ) THEN
    RAISE EXCEPTION 'PUBLIC, anon or authenticated still has broad public-schema default privileges';
  END IF;
END;
$gativx$;

DROP TABLE public.gativx_postgres_default_probe;
DROP TABLE public.gativx_supabase_admin_default_probe;
DROP SEQUENCE public.gativx_postgres_default_sequence;
DROP SEQUENCE public.gativx_supabase_admin_default_sequence;
DROP FUNCTION public.gativx_postgres_default_function();
DROP FUNCTION public.gativx_supabase_admin_default_function();

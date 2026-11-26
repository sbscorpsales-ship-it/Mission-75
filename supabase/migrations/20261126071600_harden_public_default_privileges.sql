-- Fail closed for future objects created in the GATIVX public schema.
--
-- The live mission75-cloud project currently grants anon/authenticated broad
-- default privileges on public tables, sequences and functions for objects
-- created by both postgres and supabase_admin. RLS does not protect TRUNCATE,
-- and PostgreSQL's default PUBLIC EXECUTE would expose newly created functions.
--
-- This changes defaults only; existing tables/functions are not modified here.
-- The global PUBLIC function revocation applies to all schemas for these two
-- owners. Existing per-schema grants (for example anon/authenticated EXECUTE
-- in storage/graphql) remain intact; only implicit PUBLIC execution is removed.
-- Each new client-facing object must receive explicit grants and RLS policies.
-- service_role defaults are intentionally preserved.

-- Tables and sequences: future client access must be explicitly granted.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;

-- Functions: revoke the global PostgreSQL default PUBLIC EXECUTE as well as
-- the schema-specific Supabase grants. Per-schema REVOKE cannot cancel a
-- global default privilege, so the PUBLIC revocation is intentionally global.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
    REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;

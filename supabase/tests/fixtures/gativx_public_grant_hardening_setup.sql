-- Disposable PostgreSQL 17 fixture matching the current Supabase grant shape.
-- The migration and regression test run only against this isolated database.

CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE ROLE supabase_admin NOLOGIN;
GRANT CREATE ON SCHEMA public TO supabase_admin;

-- Supabase's current global function default does not grant EXECUTE to PUBLIC.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Reproduce the broad schema-specific defaults observed for both object owners.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL PRIVILEGES ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL PRIVILEGES ON SEQUENCES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL PRIVILEGES ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL PRIVILEGES ON SEQUENCES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;

CREATE TABLE public.profiles (id uuid PRIMARY KEY);
CREATE TABLE public.daily_logs (id uuid PRIMARY KEY);
CREATE TABLE public.walk_sessions (id uuid PRIMARY KEY);
CREATE TABLE public.activity_sessions (id uuid PRIMARY KEY);
CREATE TABLE public.motion_daily_steps (id uuid PRIMARY KEY);
CREATE TABLE public.daily_action_progress (user_id uuid PRIMARY KEY);

SET ROLE supabase_admin;
CREATE TABLE public.supabase_admin_owned_probe (id uuid PRIMARY KEY);
RESET ROLE;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.walk_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.motion_daily_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_action_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supabase_admin_owned_probe ENABLE ROW LEVEL SECURITY;

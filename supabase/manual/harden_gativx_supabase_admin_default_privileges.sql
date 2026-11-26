-- Manual Supabase administrator action.
-- Run this script only from a session authorized as supabase_admin (or a role
-- that is a member of supabase_admin). The connected project SQL session used
-- for the audit is postgres and cannot assume supabase_admin.
--
-- This hardens defaults for future objects created by supabase_admin. It does
-- not alter existing tables; the versioned migration handles the current
-- postgres-owned daily_action_progress table.

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE ALL PRIVILEGES ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;

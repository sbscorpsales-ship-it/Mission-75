-- GATIVX public-schema least-privilege hardening.
-- The current daily_action_progress table is owned by postgres. RLS remains
-- enabled and its existing authenticated-user ownership policies are unchanged.
-- RLS does not protect table-wide privileges such as TRUNCATE or MAINTAIN.

REVOKE ALL PRIVILEGES ON TABLE public.daily_action_progress FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.daily_action_progress FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.daily_action_progress
  TO authenticated;

-- New objects created by the postgres migration role must not receive broad
-- API-role privileges by default. Future migrations must grant only what each
-- table, sequence or function actually needs.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;

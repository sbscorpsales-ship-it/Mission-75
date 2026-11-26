-- GATIVX public-schema least-privilege hardening.
-- All current public tables contain private member data. RLS and its existing
-- owner-scoped policies remain enabled and unchanged.
-- RLS does not protect table-wide privileges such as TRUNCATE or MAINTAIN.

-- No anonymous role needs direct table access to the private GATIVX schema.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon;

-- Authenticated members need row-scoped CRUD only. Remove table-wide and
-- administrative privileges from every existing public table.
REVOKE MAINTAIN, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public
  FROM authenticated;

-- The daily-action table was created with an over-broad grant. Rebuild its
-- intended permission set explicitly rather than relying on inherited grants.
REVOKE ALL PRIVILEGES ON TABLE public.daily_action_progress FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.daily_action_progress FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.daily_action_progress
  TO authenticated;

-- There are currently no public sequences, but remove any existing API-role
-- access and prevent future sequences from inheriting it.
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

-- New objects created by the postgres migration role must not receive broad
-- API-role privileges by default. Future migrations must grant only what each
-- table, sequence or function actually needs.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;

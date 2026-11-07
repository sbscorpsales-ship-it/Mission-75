-- Route sync now executes with the authenticated caller's privileges.
-- Existing walk_sessions RLS policies enforce row ownership.
ALTER FUNCTION public.sync_walk_session_route(uuid,timestamptz,timestamptz,integer,numeric,jsonb) SECURITY INVOKER;

-- Harden privileged RPC execution and optimize per-row owner policy checks.
-- Trigger functions remain callable by PostgreSQL triggers, not through the Data API.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

-- The route RPC remains SECURITY DEFINER because it writes to the canonical
-- walk_sessions table on behalf of the authenticated owner. Its body enforces
-- auth.uid(), validates payload bounds, and rejects cross-account conflicts.
REVOKE ALL ON FUNCTION public.sync_walk_session_route(uuid,timestamptz,timestamptz,integer,numeric,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_walk_session_route(uuid,timestamptz,timestamptz,integer,numeric,jsonb) TO authenticated;

-- Preserve each policy's existing role and ownership semantics while ensuring
-- auth.uid() is evaluated once per statement rather than once per row.
ALTER POLICY "Users can insert their own activity sessions" ON public.activity_sessions WITH CHECK ((select auth.uid()) = user_id);
ALTER POLICY "Users can read their own activity sessions" ON public.activity_sessions USING ((select auth.uid()) = user_id);
ALTER POLICY "Users can update their own activity sessions" ON public.activity_sessions USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY daily_logs_delete_own ON public.daily_logs USING ((select auth.uid()) = user_id);
ALTER POLICY daily_logs_insert_own ON public.daily_logs WITH CHECK ((select auth.uid()) = user_id);
ALTER POLICY daily_logs_select_own ON public.daily_logs USING ((select auth.uid()) = user_id);
ALTER POLICY daily_logs_update_own ON public.daily_logs USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY "Users can insert own motion daily steps" ON public.motion_daily_steps WITH CHECK ((select auth.uid()) = user_id);
ALTER POLICY "Users can read own motion daily steps" ON public.motion_daily_steps USING ((select auth.uid()) = user_id);
ALTER POLICY "Users can update own motion daily steps" ON public.motion_daily_steps USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);

ALTER POLICY profiles_insert_own ON public.profiles WITH CHECK ((select auth.uid()) = id);
ALTER POLICY profiles_select_own ON public.profiles USING ((select auth.uid()) = id);
ALTER POLICY profiles_update_own ON public.profiles USING ((select auth.uid()) = id) WITH CHECK ((select auth.uid()) = id);

ALTER POLICY walk_sessions_delete_own ON public.walk_sessions USING ((select auth.uid()) = user_id);
ALTER POLICY walk_sessions_insert_own ON public.walk_sessions WITH CHECK ((select auth.uid()) = user_id);
ALTER POLICY walk_sessions_select_own ON public.walk_sessions USING ((select auth.uid()) = user_id);
ALTER POLICY walk_sessions_update_own ON public.walk_sessions USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);

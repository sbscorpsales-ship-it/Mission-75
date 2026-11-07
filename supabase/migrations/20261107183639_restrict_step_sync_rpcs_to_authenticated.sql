-- Restrict native step-sync RPCs to authenticated app sessions.
-- Both functions are SECURITY INVOKER and enforce auth.uid() ownership.
REVOKE ALL ON FUNCTION public.sync_healthkit_daily_steps(date, integer, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_healthkit_daily_steps(date, integer, timestamptz) TO authenticated;

REVOKE ALL ON FUNCTION public.sync_motion_daily_steps(date, integer, timestamptz, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_motion_daily_steps(date, integer, timestamptz, numeric) TO authenticated;

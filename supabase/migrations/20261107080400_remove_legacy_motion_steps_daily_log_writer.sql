-- Remove the legacy overload that wrote CoreMotion values into daily_logs.
-- All native CoreMotion clients now call the four-argument RPC that writes
-- only to motion_daily_steps.
drop function if exists public.sync_motion_daily_steps(date, integer, timestamptz);

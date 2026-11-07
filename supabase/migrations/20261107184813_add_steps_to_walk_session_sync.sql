-- Store Core Motion session steps alongside the route and distance.
ALTER TABLE public.walk_sessions
  ADD COLUMN IF NOT EXISTS steps integer NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.walk_sessions'::regclass
      AND conname = 'walk_sessions_steps_check'
  ) THEN
    ALTER TABLE public.walk_sessions
      ADD CONSTRAINT walk_sessions_steps_check
      CHECK (steps >= 0 AND steps <= 200000);
  END IF;
END
$$;

DROP FUNCTION IF EXISTS public.sync_walk_session_route(
  uuid, timestamptz, timestamptz, integer, numeric, jsonb
);

CREATE FUNCTION public.sync_walk_session_route(
  p_session_id uuid,
  p_started_at timestamptz,
  p_finished_at timestamptz,
  p_duration_seconds integer,
  p_distance_m numeric,
  p_steps integer,
  p_route_points jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_session_id IS NULL OR p_started_at IS NULL OR p_finished_at IS NULL OR p_finished_at < p_started_at THEN
    RAISE EXCEPTION 'Invalid walk session timestamps';
  END IF;
  IF p_duration_seconds IS NULL OR p_duration_seconds < 0 OR p_duration_seconds > 86400 THEN
    RAISE EXCEPTION 'Invalid walk duration';
  END IF;
  IF p_distance_m IS NULL OR p_distance_m < 0 OR p_distance_m > 1000000 THEN
    RAISE EXCEPTION 'Invalid walk distance';
  END IF;
  IF p_steps IS NULL OR p_steps < 0 OR p_steps > 200000 THEN
    RAISE EXCEPTION 'Invalid walk step count';
  END IF;
  IF p_route_points IS NULL OR jsonb_typeof(p_route_points) <> 'array' OR jsonb_array_length(p_route_points) > 20000 THEN
    RAISE EXCEPTION 'Invalid GPS route points';
  END IF;

  INSERT INTO public.walk_sessions
    (id, user_id, started_at, finished_at, duration_seconds, distance_m, steps, route_points)
  VALUES
    (p_session_id, v_user_id, p_started_at, p_finished_at, p_duration_seconds, p_distance_m, p_steps, p_route_points)
  ON CONFLICT (id) DO UPDATE SET
    started_at = EXCLUDED.started_at,
    finished_at = EXCLUDED.finished_at,
    duration_seconds = EXCLUDED.duration_seconds,
    distance_m = EXCLUDED.distance_m,
    steps = EXCLUDED.steps,
    route_points = EXCLUDED.route_points
  WHERE public.walk_sessions.user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Walk session not found for this account';
  END IF;
  RETURN p_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_walk_session_route(
  uuid, timestamptz, timestamptz, integer, numeric, integer, jsonb
) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.sync_walk_session_route(
  uuid, timestamptz, timestamptz, integer, numeric, integer, jsonb
) TO authenticated;

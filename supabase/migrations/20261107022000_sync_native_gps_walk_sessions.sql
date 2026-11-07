create or replace function public.sync_walk_session_route(
  p_session_id uuid,
  p_started_at timestamptz,
  p_finished_at timestamptz,
  p_duration_seconds integer,
  p_distance_m numeric,
  p_route_points jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_session_id is null or p_started_at is null or p_finished_at is null or p_finished_at < p_started_at then
    raise exception 'Invalid walk session timestamps';
  end if;
  if p_duration_seconds is null or p_duration_seconds < 0 or p_duration_seconds > 86400 then
    raise exception 'Invalid walk duration';
  end if;
  if p_distance_m is null or p_distance_m < 0 or p_distance_m > 1000000 then
    raise exception 'Invalid walk distance';
  end if;
  if p_route_points is null or jsonb_typeof(p_route_points) <> 'array' or jsonb_array_length(p_route_points) > 20000 then
    raise exception 'Invalid GPS route points';
  end if;
  insert into public.walk_sessions
    (id, user_id, started_at, finished_at, duration_seconds, distance_m, route_points)
  values
    (p_session_id, v_user_id, p_started_at, p_finished_at, p_duration_seconds, p_distance_m, p_route_points)
  on conflict (id) do update set
    started_at = excluded.started_at,
    finished_at = excluded.finished_at,
    duration_seconds = excluded.duration_seconds,
    distance_m = excluded.distance_m,
    route_points = excluded.route_points
  where public.walk_sessions.user_id = v_user_id;
  if not found then raise exception 'Walk session not found for this account'; end if;
  return p_session_id;
end;
$$;
revoke all on function public.sync_walk_session_route(uuid,timestamptz,timestamptz,integer,numeric,jsonb) from public;
grant execute on function public.sync_walk_session_route(uuid,timestamptz,timestamptz,integer,numeric,jsonb) to authenticated;

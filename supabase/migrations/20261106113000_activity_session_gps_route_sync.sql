alter table public.activity_sessions
  add column if not exists route_points jsonb not null default '[]'::jsonb;

create or replace function public.sync_activity_session_route(
  p_session_id uuid,
  p_route_points jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if p_session_id is null or p_route_points is null or jsonb_typeof(p_route_points) <> 'array' then
    raise exception 'A session ID and route point array are required';
  end if;
  if jsonb_array_length(p_route_points) > 20000 then
    raise exception 'Route exceeds the supported point limit';
  end if;
  update public.activity_sessions
     set route_points = p_route_points
   where user_id = v_user_id and session_id = p_session_id;
  if not found then raise exception 'Activity session not found for this account'; end if;
end;
$$;

revoke all on function public.sync_activity_session_route(uuid,jsonb) from public, anon;
grant execute on function public.sync_activity_session_route(uuid,jsonb) to authenticated;
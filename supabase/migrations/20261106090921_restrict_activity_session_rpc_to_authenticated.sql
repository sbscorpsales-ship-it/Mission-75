-- Keep activity-session RPC execution restricted to authenticated members.
revoke all on function public.sync_activity_session_steps(uuid, text, timestamptz, timestamptz, integer)
    from public, anon;
grant execute on function public.sync_activity_session_steps(uuid, text, timestamptz, timestamptz, integer)
    to authenticated, service_role;

-- Store each member's active goal and the personal reason behind it.
-- All fields are nullable so existing profiles and older app versions remain compatible.
alter table public.profiles
  add column if not exists goal_type text,
  add column if not exists goal_duration text,
  add column if not exists goal_purpose text,
  add column if not exists goal_feeling text,
  add column if not exists goal_started_at timestamptz,
  add column if not exists goal_updated_at timestamptz;

comment on column public.profiles.goal_type is 'Member-selected active GATIVX goal category.';
comment on column public.profiles.goal_duration is 'Member-selected goal duration.';
comment on column public.profiles.goal_purpose is 'Member-authored reason for pursuing the goal.';
comment on column public.profiles.goal_feeling is 'Member-authored feeling or outcome associated with the goal.';
comment on column public.profiles.goal_started_at is 'Timestamp when the member started the active goal.';
comment on column public.profiles.goal_updated_at is 'Timestamp used to reconcile goal changes across devices.';

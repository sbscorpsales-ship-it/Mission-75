-- GATIVX Universal Data Hub foundation (additive migration)
-- Does not alter or delete existing Mission-75 daily_logs, walk_sessions, profiles,
-- or browser localStorage records. Apply to staging first and verify RLS before production.

create table if not exists public.gativx_data_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  platform text not null check (platform in ('ios','android','web','cloud','manual')),
  display_name text not null,
  connection_status text not null default 'pending'
    check (connection_status in ('pending','connected','stale','error','disconnected')),
  external_account_ref text,
  connected_at timestamptz,
  last_successful_sync_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists gativx_data_sources_user_idx on public.gativx_data_sources(user_id);

create table if not exists public.gativx_connected_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  data_source_id uuid not null references public.gativx_data_sources(id) on delete cascade,
  manufacturer text,
  model text,
  device_type text,
  external_device_ref text,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(data_source_id, external_device_ref)
);
create index if not exists gativx_devices_user_idx on public.gativx_connected_devices(user_id);

create table if not exists public.gativx_source_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  data_source_id uuid not null references public.gativx_data_sources(id) on delete cascade,
  data_type text not null,
  permission_status text not null
    check (permission_status in ('unknown','granted','denied','revoked','unavailable')),
  purpose text not null,
  updated_at timestamptz not null default now(),
  unique(data_source_id, data_type)
);

-- Raw provider payloads are retained for audit/reprocessing. They are never summed directly.
create table if not exists public.gativx_raw_health_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  data_source_id uuid not null references public.gativx_data_sources(id) on delete cascade,
  provider_record_id text not null,
  data_type text not null,
  started_at timestamptz,
  ended_at timestamptz,
  recorded_at timestamptz,
  ingested_at timestamptz not null default now(),
  original_value numeric,
  original_unit text,
  payload jsonb not null default '{}'::jsonb,
  source_deleted_at timestamptz,
  unique(data_source_id, provider_record_id)
);
create index if not exists gativx_raw_user_time_idx
  on public.gativx_raw_health_records(user_id, data_type, started_at desc);

create table if not exists public.gativx_sync_state (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  data_source_id uuid not null references public.gativx_data_sources(id) on delete cascade,
  data_type text not null,
  cursor text,
  last_attempt_at timestamptz,
  last_success_at timestamptz,
  status text not null default 'idle'
    check (status in ('idle','running','success','retrying','error')),
  error_code text,
  unique(data_source_id, data_type)
);

create table if not exists public.gativx_reconciliation_decisions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  metric text not null,
  decision_type text not null
    check (decision_type in ('platform_aggregate','preferred_source','deduplicated','merged_session','manual_review','excluded')),
  rule_version text not null,
  explanation text not null,
  decided_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.gativx_canonical_daily_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  timezone text not null,
  metric text not null,
  value numeric not null,
  unit text not null,
  provenance text not null
    check (provenance in ('measured','manual','estimated','platform_aggregate')),
  confidence text not null default 'medium'
    check (confidence in ('high','medium','low')),
  reconciliation_decision_id uuid references public.gativx_reconciliation_decisions(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(user_id, local_date, metric)
);
create index if not exists gativx_daily_metrics_user_date_idx
  on public.gativx_canonical_daily_metrics(user_id, local_date desc);

create table if not exists public.gativx_metric_source_preferences (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  metric text not null,
  preferred_data_source_id uuid references public.gativx_data_sources(id) on delete set null,
  mode text not null default 'automatic'
    check (mode in ('automatic','prefer_source','review_conflicts')),
  updated_at timestamptz not null default now(),
  unique(user_id, metric)
);

-- Member-scoped row-level security. Service-role access remains server-side only.
alter table public.gativx_data_sources enable row level security;
alter table public.gativx_connected_devices enable row level security;
alter table public.gativx_source_permissions enable row level security;
alter table public.gativx_raw_health_records enable row level security;
alter table public.gativx_sync_state enable row level security;
alter table public.gativx_reconciliation_decisions enable row level security;
alter table public.gativx_canonical_daily_metrics enable row level security;
alter table public.gativx_metric_source_preferences enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'gativx_data_sources','gativx_connected_devices','gativx_source_permissions',
    'gativx_raw_health_records','gativx_sync_state','gativx_reconciliation_decisions',
    'gativx_canonical_daily_metrics','gativx_metric_source_preferences'
  ] loop
    execute format('drop policy if exists %I on public.%I', t || '_member_all', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      t || '_member_all', t
    );
  end loop;
end $$;

grant select, insert, update, delete on
  public.gativx_data_sources, public.gativx_connected_devices,
  public.gativx_source_permissions, public.gativx_raw_health_records,
  public.gativx_sync_state, public.gativx_reconciliation_decisions,
  public.gativx_canonical_daily_metrics, public.gativx_metric_source_preferences
to authenticated;

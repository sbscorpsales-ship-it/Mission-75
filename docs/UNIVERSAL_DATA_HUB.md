# GATIVX Universal Data Hub — implementation foundation

**Status:** Development branch foundation. Architecture decisions frozen: iOS + Android; all supported and consented data categories; automatic reconciliation with member override.

## Existing Mission-75 baseline (inspected 2026-11-04)

The production repository is `sbscorpsales-ship-it/Mission-75`, default branch `main`. The deployed web app remains at https://sbscorpsales-ship-it.github.io/Mission-75/.

The current web application is a single-page PWA (`index.html`) and uses these browser storage keys:
- `mission75.logs.v1` — daily logs
- `mission75.gps.sessions.v1` — locally stored GPS sessions/routes
- `mission75.settings.v1` — user targets/settings
- `mission75.habits.v1` — daily habit completion

The web app also connects to Supabase and reads/writes `daily_logs`, `profiles`, and `walk_sessions`. Device-only browser records are not automatically in Supabase. Existing JSON backup/import remains the required migration route until a separately tested import is built.

The repository already contains an iOS SwiftUI starter under `ios/GATIVX`, a read-only HealthKit step manager, a Supabase REST client, a step-sync SQL migration, and a hosted macOS build workflow. These are starter components, not a verified App Store-ready app. The first hosted build workflow run was cancelled; it is not a successful compile.

## Non-negotiable preservation rules

1. Do not rename or remove the four browser storage keys above.
2. Do not drop, truncate, or replace existing `daily_logs`, `profiles`, or `walk_sessions`.
3. Do not automatically merge local data into cloud until conflict behaviour is tested against real backups.
4. Export JSON backups before any migration; validate record counts, dates, IDs, units, GPS route points and settings.
5. Add new data tables independently. This branch migration is additive and does not alter the existing Mission-75 tables.
6. Test restore and rollback on staging before applying any migration to production.

## Hub architecture

`native iOS / HealthKit` and `native Android / Health Connect` plus approved cloud providers feed a common ingestion API. Each adapter writes source records idempotently to a raw vault. Normalisation converts units and types. Reconciliation applies metric-specific rules and writes canonical daily metrics. Dashboards read canonical values while retaining links to source records and decisions.

### Logical pipeline

1. Connector permission and source registration.
2. Initial import and incremental sync with per-data-type cursor.
3. Immutable raw record ingestion with provider ID and source/device provenance.
4. Normalisation to canonical metric names/units.
5. Duplicate detection and reconciliation with versioned rules.
6. Canonical daily rollups by member-local date and timezone.
7. Web/mobile dashboard and mission/report projections.

## Data model added by the foundation migration

- `gativx_data_sources`: connected provider/app accounts.
- `gativx_connected_devices`: physical device identity and metadata.
- `gativx_source_permissions`: per-data-type permission state and purpose.
- `gativx_raw_health_records`: provider record IDs, original payload/value/unit and source timestamps.
- `gativx_sync_state`: per-source/per-type cursor, last attempt/success and retry state.
- `gativx_reconciliation_decisions`: versioned decisions and human-readable rationale.
- `gativx_canonical_daily_metrics`: member-local daily metric values, provenance and confidence.
- `gativx_metric_source_preferences`: automatic, preferred-source or review-conflict mode per metric.

Every table has member-scoped RLS. The migration is additive and should first be applied to a staging Supabase project, then verified using two test accounts before production.

## Reconciliation v1 rules

- **Steps:** prefer HealthKit/Health Connect platform aggregate when available. Never sum device daily totals. Preserve source records and source-level samples.
- **Distance:** prefer one reconciled all-day aggregate or a validated workout/GPS session. Do not add the phone and watch record for the same walk.
- **Workouts:** match candidates using source workout ID, activity type, interval overlap, duration, distance and route similarity. Keep genuinely separate sessions separate.
- **Heart rate / HRV:** preserve timestamped source samples. Never sum. Avoid averaging devices with different sampling/quality without an explicit method.
- **Sleep:** reconcile overlapping intervals; distinguish naps from overnight sleep; retain source-specific stage data.
- **Weight/body measures:** retain each timestamped measurement; deduplicate repeat imports; never average duplicate scale entries.
- **Calories:** keep active, resting and total energy as separate metrics.
- **Nutrition/hydration:** only distinct events; no inference from activity or missing data.
- **Missing data:** represent as not recorded, never as zero.
- **Overrides:** member preference applies to a metric, not all metrics. Store rule version and rationale for every decision.

## Connector contract

Each provider adapter must implement: capability discovery; granular consent; connect/disconnect; initial sync; incremental sync; stable external ID mapping; deletion/correction handling; retry/backoff; last-sync status; and a documented list of supported metrics.

### iOS
Use native HealthKit. Request least-privilege read types only after the member selects Connect Apple Health. Use cumulative statistics for steps, observer/background delivery where allowed, anchored queries for changes/deletions, refresh on foreground, and secure upload. Background delivery is best-effort and must not be described as guaranteed real-time.

### Android
Use native Health Connect. Request granular read permissions, use aggregate queries for cumulative steps, request background-read access only when needed, track per-type sync checkpoints and handle permission revocation/history restrictions. Do not assume Health Connect deduplicates every metric.

### Cloud providers
Add Google Health API, Garmin, Oura, Polar and Zepp only after verifying official API access, consent scopes, approval/contract requirements and model-level coverage. Keep provider credentials on the server; OAuth tokens must be encrypted and never shipped in the public web bundle.

## Privacy and security
- Separate HealthKit/Health Connect OS permission from consent to upload to GATIVX cloud.
- No service-role secrets in web or native clients.
- TLS in transit, encrypted storage, least privilege, RLS, audit trail and token rotation.
- Data export, disconnect and deletion flows.
- GPS sharing private by default; community sharing must be opt-in.
- No diagnosis, treatment or advertising use of health data.

## Release gates
- Mission-75 backup and restore verified.
- Existing web dashboard unchanged on main until regression-tested.
- Migration applied to staging and RLS tested with multiple accounts.
- Duplicate step/workout/sleep fixtures pass.
- Permission revoked, source offline, retries, timezone changes and corrections tested.
- Native iOS build succeeds on hosted macOS; real iPhone HealthKit test completed.
- Android Health Connect integration built and tested on a real supported Android device.
- Only then consider production migration and store submission.

## Current implementation status

This document describes the intended architecture and the additive schema foundation. It does not claim that provider connectors, Android app, production database migration, backup import, or app-store packages are complete.

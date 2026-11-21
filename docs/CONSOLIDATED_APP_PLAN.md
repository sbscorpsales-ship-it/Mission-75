# GATIVX — Consolidated RunJeet + GATIVX Product Plan

## Decision

GATIVX is the single member-facing fitness and goal-achievement application. RunJeet is not a second product: its walking, GPS, local activity persistence, and backup/export work are treated as the tracking foundation and reference implementation to be consolidated into GATIVX.

The separate Shree Ram Weekly Fund Manager project is out of scope and must remain separate.

## Product experience

One app, one account, one activity history, one settings/profile area, and one navigation system.

- **Home:** GATIVX dashboard, daily steps, progress, today's mission, activity summary, and next recommended action.
- **Activity:** walking session lifecycle (prepare, start, pause/resume, finish, save), GPS route, duration, distance, pace, elevation when available, and recovery after interruption.
- **Missions:** daily/weekly goals and progress.
- **Gati Guru:** reconnect the member to their stated purpose and emotion, then suggest one small achievable next action.
- **Journey:** historical activities, goal progress, streaks, and milestones.
- **Community:** retain the planned community area; clearly label unavailable capabilities until implemented.
- **Profile & Settings:** account, privacy, Health permissions/status, units, appearance, export/backup, and sync status.

## Consolidated architecture

### Single source of truth

Use one canonical activity and daily-metrics data model. Do not maintain separate RunJeet and GATIVX activity stores.

- Native iOS HealthKit is the preferred source for authorized steps and health metrics.
- Core Location supplies route samples for an explicitly started walking session, subject to permission and platform limits.
- Core Motion / pedometer supplies device step deltas where available.
- A repository/data layer reconciles sources, timestamps, time zones, permissions, and duplicate events.
- Local persistence is committed before any network upload. A failed upload must never discard a completed activity.
- Sync is idempotent: retries must not create duplicate activities or double-count steps.
- Export/import remains available as a user-controlled backup and recovery path.

### Platform responsibilities

**iOS native app (release target):** HealthKit authorization and queries, Core Motion, Core Location, background capabilities where approved by Apple, durable local persistence, and cloud sync.

**PWA/web experience:** dashboard and account experience where supported, local preview/testing, and backup inspection. A browser/PWA must not be represented as equivalent to native HealthKit or guaranteed background step/GPS tracking.

## Migration and preservation

1. Preserve the RunJeet PWA source and its JSON backup/export format as a reference until the native data model and migration tests are complete.
2. Inspect the actual RunJeet source and sample backup before writing an importer; do not infer its schema from screenshots.
3. Implement a versioned importer with validation, idempotency, and a non-destructive dry run.
4. Keep existing GATIVX and RunJeet user data untouched until the user explicitly approves any migration/deletion.
5. Retire duplicate app entry points only after the consolidated GATIVX build passes device acceptance.

## Required acceptance tests

- Read authorized Apple Health step totals and show permission-denied/unavailable states accurately.
- Reconcile HealthKit steps with pedometer samples without double counting.
- Start, pause, resume, finish, and save a real walk on a physical iPhone.
- Verify a completed activity remains after app termination/relaunch and device restart.
- Verify GPS route recording under the granted permission state and document background limitations.
- Verify local-first save, offline queue, reconnect, idempotent retry, and account isolation.
- Export a backup, import it into a clean test profile, and verify record counts and totals.
- Test midnight/time-zone changes, duplicate samples, permission revocation, and interrupted sessions.

## Release guardrails

- Do not merge release PRs until automated checks pass and physical-device acceptance is recorded.
- An unsigned IPA is a build artifact only; it is not installable until signed with valid Apple provisioning.
- HealthKit/background capabilities must be validated against the actual signing profile and physical device, not inferred from source configuration or simulator success.
- No RunJeet data or backup is to be deleted as part of consolidation.

# GATIVX Tracking and Recovery Findings

Audit date: 2026-11-17
Scope: read-only inspection of the current Mission-75 main branch and RunJeet main / closed PR #4. No app code, production data, or release artifacts were changed.

## Executive finding

The current GATIVX dashboard and the RunJeet native tracker are not equivalent implementations. GATIVX `app-v2.html` currently records GPS walks in browser storage and explicitly tells the user to keep the screen open. RunJeet documents native Android/iOS sensor and GPS services, but its README also says profile/session/route data are device-local and there is no automatic cross-device sync in that repository's current documented state.

The most urgent confirmed code risk is the GATIVX browser walk Finish path: it pushes a walk into in-memory state, calls a localStorage-backed `persist()`, and on persistence failure removes the walk from state and tells the user not to refresh. There is no durable recovery journal or IndexedDB transaction in this path. A refresh/termination after a failed write can therefore lose the completed route. This is a code-level finding, not a physical-device reproduction.

## Evidence and decisions

### Current GATIVX dashboard (Mission-75 main)

- `app-v2.html` uses a version-2 state object with `entries` and `walks`, loaded from localStorage.
- Its `persist()` function serializes the complete state to localStorage.
- The GPS UI notice says: "Keep this screen open during a walk" and says browser location saves sessions on this device.
- GPS capture uses `navigator.geolocation.watchPosition`; this is browser tracking, not native background tracking.
- Finish validates at least two accurate GPS fixes and positive distance, constructs a walk record, adds it to `state.walks`, updates the daily distance, and calls `persist()`.
- If `persist()` throws, the catch removes the just-added walk and restores the prior daily entry; the user-facing message says the route remains only on screen and warns not to refresh.
- No IndexedDB or `gativx-workout-recovery-v1` recovery journal was found in this dashboard file.

Decision: keep this dashboard and its existing data model intact during integration. Do not treat its browser GPS as a replacement for native screen-off tracking. The Finish path needs a durable write-ahead/recovery mechanism and verified read-back before it can be considered robust.

### RunJeet current main

The repository README documents:
- Android hardware step counter (`TYPE_STEP_COUNTER`) with a foreground health service, daily persistence, midnight rollover and reboot-baseline recovery.
- Android Health Connect reads subject to permission.
- iOS Core Motion pedometer and HealthKit daily totals/workout reads.
- Native GPS/location services for active workouts, with local route persistence and dashboard replay.
- Local workout history and IndexedDB persistence.
- Physical-device background operation is conditional on OS permissions, scheduling and battery policy; force-quit/force-stop terminates the process.
- README explicitly states no server authentication or automatic cross-device cloud sync in this repository's documented current state.

Decision: use RunJeet native tracking modules as candidates for a GATIVX native adapter layer, not as a wholesale replacement for the GATIVX dashboard, identity, goals, or existing user records.

### RunJeet closed PR #4 (not merged)

PR #4 is closed and unmerged. Its head commit contains a stronger Finish flow:
- Write a small recovery journal to localStorage before the primary IndexedDB save.
- Deduplicate by workout ID.
- Read the saved workout back to verify persistence.
- Replay pending journal records during startup.
- Keep the completed workout visible and journaled if the primary database save fails rather than rolling it back.

Comparison against RunJeet main confirms the recovery-journal key and this flow are present in the PR head file but absent from RunJeet main's current `app.js`. The PR's iOS workflow also adds generated HealthKit entitlement checks. Its own description notes the produced IPA is unsigned and cannot provide an installable trusted HealthKit capability on a physical iPhone without correct signing/provisioning.

Decision: treat PR #4 as a candidate patch to review and adapt, not as merged or released functionality. Re-test its edge cases before porting. In particular, ensure journal writes themselves are checked, records are size-bounded, replay is idempotent, and journal removal happens only after durable read-back.

### Existing Mission-75 draft PRs

- PR #101 (Apple Health workout export), #103 (completed GPS walk minutes ring), and #104 (retry cloud backup of saved walks) are open draft PRs, not merged.
- Keep these changes separate until reviewed against one canonical activity/session schema and duplicate-write rules.

## Integration architecture recommendation

1. Canonical GATIVX activity record: stable UUID, activity type, start/end timestamps, duration excluding pauses, route points with timestamps/accuracy, distance with source, optional estimates, device/source provenance, local persistence status, cloud sync status, and Health export status.
2. Local-first transaction: write-ahead recovery record -> durable local transaction -> read-back verification -> mark local save complete -> enqueue cloud sync and Health export independently.
3. Failure isolation: cloud backup or Health export failure must never roll back a locally completed activity. Retry each external destination idempotently using the activity UUID.
4. One source of truth for each metric: native pedometer/Health platform for steps; GPS route for recorded workout distance; estimates labelled as estimates; unavailable values remain null rather than fake zero.
5. Native adapters: Android Health Connect / foreground service and iOS Core Motion / HealthKit / Core Location. Web/PWA remains a dashboard and manual GPS fallback with clearly stated foreground limitations.
6. Preserve existing GATIVX dashboard, goal/Guru experience, user identity and legacy records. WALKON remains a separate product and is not merged without its source and a reviewed mapping.

## Release gates

- Unit tests: workout UUID idempotency, repeated Finish taps, interrupted write, corrupt/partial journal, replay after restart, duplicate cloud delivery, midnight step-counter rollover and reboot baseline.
- Android: physical-device background step test, screen-off GPS test, Health Connect permission/read test, reboot/recovery test, offline-to-online sync.
- iOS: physical signed build with HealthKit capability, Core Motion, HealthKit read/write permission and export verification; unsigned CI IPA is not acceptance.
- Persistence: finish -> force close/relaunch -> activity and route still present; cloud unavailable -> activity remains; Health export unavailable -> activity remains; retries do not duplicate.
- Regression: current dashboard, existing profile, goals, rings, legacy saved records and data export/import.
- Privacy/security: explicit permissions, minimum location collection, no continuous all-day GPS, account-scoped access and backend row-level security review.

## Status

This is an evidence-based audit note only. No application code has been changed, no PR has been opened or merged, no deployment was made, and no production data was modified.

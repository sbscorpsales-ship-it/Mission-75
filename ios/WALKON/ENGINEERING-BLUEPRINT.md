# WALKON — PROJECT CONTINUITY REGISTER
> **Read this register before every continuation.** It is the operational checkpoint; the engineering sections below are the detailed evidence base. Update this register after every completed research section or verified implementation milestone. Never restart from the roadmap or repeat completed sections.

## Current project state
- **Product:** WALKON — fresh native fitness app with fresh data. Do not resume or import GATIVX/Mission-75 app implementation or data.
- **Repository:** `sbscorpsales-ship-it/Mission-75`, branch `main`.
- **Blueprint:** `ios/WALKON/ENGINEERING-BLUEPRINT.md`.
- **Phase:** Research and engineering specification only. **App building is not authorized yet.**
- **Current completed research:** Sections 1–37 exist below. Latest research section: **37 — Offline-first storage, sync, conflict handling and export**.
- **Exact next task:** **Section 38 — Maps, route display, map matching and location privacy.** Research route rendering, map providers/SDKs, offline map constraints, map matching limits, route simplification, geospatial privacy, start/end-point protection, location retention and sharing controls. Do not drift into unrelated feature design.
- **After Section 37:** update this register's latest-completed and exact-next-task fields before proceeding to Section 38 (maps, route display, map matching and location privacy).
- **No user device testing or screenshot requests** until the research/architecture blueprint is sufficiently complete and a coherent buildable test plan is ready.

## Non-negotiable working rules
1. **Research before implementation.** Do not write app code, build, deploy, or ask the user to test until the research and architecture gates are explicitly closed.
2. **One research domain at a time.** Complete the domain, document evidence, implications, unresolved questions and validation gates; then move to the next exact task.
3. **No repeated recaps.** Do not re-explain completed sections unless a new finding changes them. Refer to section numbers and continue from the exact next task.
4. **No circular instructions.** Never ask the user to repeat known context, re-run completed steps, or perform research the assistant can do.
5. **Audit before changing.** Fetch the current GitHub file and SHA before every write. Never overwrite a newer version. After each write, fetch again and verify the new section and register.
6. **Evidence discipline.** Distinguish official API guarantees, vendor descriptions, independent research, engineering proposals and untested assumptions. Cite current sources in the section.
7. **No invented verification.** A documented capability is not a tested device result. A saved blueprint is not an implemented app.
8. **Preserve continuity after each milestone.** Update this register with completed section, exact next action, open questions and latest commit/blob SHA. The next session starts by reading this register, not by generating a fresh roadmap.
9. **Keep the existing single blueprint.** Do not scatter duplicate planning documents or create a second competing source of truth.
10. **User priority:** reliability and accuracy first; design and optional features later.

## Completed research index
- **Sections 1–12:** Product objective, data rules, proposed architecture, GPS logic, recording state machine, Android direction, reference-app checklist, acceptance tests, deferred features/decisions, prototype gaps and references.
- **Sections 13–22:** WWDC25 workout research, iOS platform decision, build specification, implementation sequence, SQLite/HealthKit recovery, prototype audit, database schema, service contracts, iOS background location, reference-app architecture.
- **Section 23:** iPhone hardware-first study.
- **Section 24:** Reference-app logic and capability orchestration.
- **Section 25:** Cross-platform market study.
- **Section 26:** Deeper product/platform/customer findings.
- **Section 27:** Android sensor pipeline and cross-platform app behaviour.
- **Section 28:** GPS/location engine on iOS and Android.
- **Section 29:** Elevation, altitude and barometric measurement.
- **Section 30:** Motion sensing, pedometer and activity recognition.
- **Section 31:** Heart-rate science, PPG/ECG, HealthKit/Health Connect semantics, HRV and validation.
- **Section 32:** BLE Heart Rate Service, Core Bluetooth, Android BLE, Apple Watch and Wear OS integration boundaries.
- **Section 33:** Workout state machine, crash recovery, HealthKit route finalization, Android exercise ownership and exactly-once reconciliation.
- **Section 34:** HealthKit/Health Connect permission semantics, aggregate versus raw reads, provenance, incremental changes, deletion, source reconciliation, privacy and acceptance tests.
- **Section 35:** Active, resting/basal, gross and total energy semantics; HealthKit/Health Connect calorie records; walking-model limits; wearable error; WALKON validation policy.
- **Section 36:** iOS/Android location power efficiency, background execution, batching, thermal and Low Power Mode responses, sensor/CPU/network duty cycle, battery measurement, long-session degradation and validation gates.
- **Section 37:** Local-first durable writes, transactional outbox/inbox, idempotent sync, retries/backoff, ordering, conflict policy, tombstones/deletion propagation, HealthKit workout/route export, upload recovery and offline validation.

## Open research queue (ordered)
36. Battery, thermal management and long-session behaviour.
37. [COMPLETE] Offline-first storage, sync, conflict handling and export.
38. Maps, route display, map matching and location privacy.
39. Privacy, security, consent, retention and deletion.
40. Accessibility, gait diversity and inclusive measurement.
41. Test strategy, reference instruments, acceptance thresholds and release gates.
After these: consolidate contradictions, close architecture decisions, produce a single implementation-ready specification and explicit go/no-go checklist. Only then ask for authorization to build.

## Last verified checkpoint
- **Latest completed section:** 37.
- **Latest research update:** Section 37 — offline-first storage, sync, conflict handling and export.
- **Section-37 commit:** 7442ab2b20c86577881f93462b3f2e654e8fb298.
- **Section-37 research blob:** 6113be98f48dc77594b463c2ee8c291db4216547.
- **Next action:** research Section 38 — maps, route display, map matching and location privacy.

---

# WALKON — Engineering Blueprint (Research Draft)

Status: Research draft — NOT final architecture approval
Date: 2026-11-07
Product: WALKON (temporary six-letter product name)
Platform in first release: Native iPhone app (SwiftUI, iOS 26.0+)
Principle: Measurement accuracy and recoverability before design, social features or monetisation.

## 1. Product objective

Build a dependable walking and fitness recorder that:
- Shows the user's authoritative daily step total from Apple Health.
- Shows a separate live step count for a WALKON-recorded session.
- Records a usable GPS route while a user explicitly records an activity.
- Calculates distance and pace from validated location samples.
- Saves a completed workout and its route, with clear source provenance.
- Survives screen lock, temporary GPS loss, app suspension and recoverable interruptions.
- Never imports old app activity into the new product or silently mixes sensor totals.

This is a research blueprint. Strava's private algorithms are not publicly knowable; implement observable behaviours and documented platform APIs, then validate against real devices.

## 2. Non-negotiable data rules

### 2.1 Two separate step values
1. Daily steps: query HealthKit cumulative step statistics for the user's local calendar day. This is the dashboard number.
2. Session steps: use Core Motion CMPedometer live updates from the session start time to the end time. This is the number attributed to that WALKON session.
3. Never sum daily HealthKit steps + session Core Motion steps.
4. Do not write the same session's steps back into HealthKit as a new step sample. That would create a duplicate source.
5. Show data source and last refresh time. Treat denied access and unavailable data as distinct states, not as zero steps.

Apple documentation: HKStatisticsCollectionQuery supports cumulative daily statistics and can receive updates as HealthKit changes; CMPedometer provides cached historical data and live updates.
- https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery
- https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries
- https://developer.apple.com/documentation/coremotion/cmpedometer

### 2.2 Source provenance
Every imported/derived measurement should preserve:
- source platform / source app / device when available
- sample start and end timestamps
- unit and aggregation window
- whether it is a platform aggregate, raw sample, or WALKON session metric
- permission / availability status
- last successful query time

Do not invent a proprietary source priority algorithm on iOS. Use HealthKit's aggregate statistics for the dashboard and expose source details only where HealthKit makes them available and privacy permits.

### 2.3 One activity, one identity
Each recorded workout receives a UUID at session creation. All route points, sensor observations, pauses, summaries and HealthKit workout references are linked to that UUID. Saving must be idempotent: retrying a save must not create a second workout.

## 3. iPhone data architecture (proposed)

### A. HealthKit daily summary service
Responsibilities:
- Request read access only for data actually used.
- Query step count as a cumulative sum for local-day boundaries.
- Use long-running statistics / observer updates to refresh when HealthKit changes.
- Handle midnight, timezone changes, no samples, denied permission and HealthKit unavailable.
- Optionally read workouts, walking/running distance, heart rate and active energy only after each feature has a clear consent and UI requirement.

Important: HealthKit read permission is privacy-preserving; an app may not be able to distinguish denied read access from no available samples. UI must not assert permission was granted merely because requestAuthorization completed.

### B. Core Motion session pedometer
Responsibilities:
- Start CMPedometer at the actual activity start timestamp.
- Consume incremental updates and handle errors.
- Query the completed interval at finish to reconcile the final session count.
- Preserve the session value independently from HealthKit's daily aggregate.
- Do not fabricate zero when the device does not support step counting.

### C. Core Location route recorder
Responsibilities:
- Start location only after the user starts an activity.
- Capture timestamp, coordinate, horizontal accuracy, altitude and speed where valid.
- Use an explicit recording state and visible recording indicator.
- Filter invalid / stale / low-accuracy points and impossible jumps.
- Calculate segment distance only between accepted points.
- Retain raw accepted points separately from derived summary metrics so the route can be reprocessed if the algorithm changes.
- Handle denied/reduced accuracy, no GPS fix, temporary loss, indoor drift, background transitions and app relaunch.
- Avoid claiming that iOS guarantees uninterrupted background execution.

Apple's current background-location guidance: location updates can be queued while an app is suspended; apps must configure background location correctly and restore the relevant services after termination when appropriate.
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- https://developer.apple.com/documentation/corelocation

### D. Workout persistence
Proposed completed activity record:
- id (UUID)
- activity type
- startedAt / endedAt
- elapsed duration
- moving duration (calculated, not guessed)
- session steps and source
- distance in metres
- average pace / speed derived from moving time and distance
- route points with timestamps and accuracy metadata
- elevation gain only after a reliable altitude strategy is tested
- HealthKit workout identifier (optional)
- sync state (future; local-first in initial release)
- algorithm version

Use SQLite as the local source of truth for durable activity records, route points and the recovery journal. Use append-only route-point rows, indexed by workout/segment/time, WAL mode, foreign keys and versioned migrations. Do not use UserDefaults for route history. Initial app data namespace must be WALKON-only and must not import legacy app records.

### E. HealthKit workout and route write
After validating the activity locally:
- Create a HealthKit workout with correct activity type, start/end dates and summary quantities.
- Save the route using the HealthKit workout route APIs, associating route samples with the workout.
- Handle authorization, save errors and partial failure.
- Persist the relationship between local workout UUID and HealthKit workout UUID.
- Do not write duplicate step samples.

Official API reference to implement against:
- https://developer.apple.com/documentation/healthkit/workouts_and_activity_rings
- https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder

## 4. GPS quality and distance logic (proposed; tune only from field tests)

Each location observation should include:
- timestamp
- latitude / longitude
- horizontal accuracy
- altitude and vertical accuracy
- reported speed and speed accuracy where available

Initial acceptance policy for testing (not final thresholds):
- Reject negative / invalid horizontal accuracy.
- Reject stale or out-of-order timestamps.
- Reject samples with very poor horizontal accuracy (initial test threshold: > 35–50 m; calibrate in open sky and urban streets).
- Reject impossible displacement / speed spikes rather than adding them to distance.
- Do not bridge a long GPS gap with a straight-line segment and pretend it was travelled.
- Preserve an explicit GPS-gap marker for the map and summary diagnostics.
- Apply smoothing only to display / derived path, retaining accepted raw coordinates.
- Avoid double-counting overlapping route segments after pause/resume.

Distance:
- Calculate geodesic distance between sequential accepted points.
- Apply quality and plausibility checks before accumulating.
- Store distance in metres at full precision; round only for display.
- Compare against Strava and Apple Fitness on the same route, but treat both as comparison references rather than unquestionable ground truth.

Pace:
- Show elapsed pace and moving pace as separate metrics.
- Do not display unstable instantaneous pace from a single noisy GPS sample.
- Use a rolling window and mark pace unavailable while GPS quality is poor.

Elevation:
- Do not promise accurate elevation gain from noisy GPS altitude alone.
- Evaluate barometer / fused altitude availability and compare against known routes before release.

## 5. Recording state machine

States:
- idle
- preparing (permissions and initial GPS fix)
- recording
- paused (manual or auto-pause, with reason)
- finishing
- savingLocal
- savingHealthKit
- saved
- recoverableError

Transitions:
- Start -> preparing -> recording only when the user has confirmed the activity start. Do not block a walk indefinitely waiting for perfect GPS; show GPS quality and record the limitation.
- Pause -> stop or suspend route accumulation and pedometer session accounting consistently.
- Resume -> create a new segment; never connect across a pause as if the user travelled that gap.
- Finish -> query final pedometer interval -> finalize route -> save local transaction -> attempt HealthKit workout/route write.
- Local save succeeds but HealthKit save fails -> preserve local workout and show a retry action; do not lose the activity.
- App relaunch during active session -> recover from persisted session state and platform-delivered updates where possible; clearly report any gap.

Manual pause is mandatory. Auto-pause is optional and must be tested for walking specifically; Strava documents that slow walking can cause false pauses/resume failures, so do not blindly copy a running/cycling threshold.
- https://support.strava.com/en-us/articles/15402137-how-do-i-record-an-activity-in-strava
- https://support.strava.com/en-us/articles/15401874-how-do-i-fix-autopause-issues

## 6. Android future architecture (not part of iPhone first build)

Do not base a new Android product on Google Fit's legacy APIs. Use Health Connect as the platform health-data integration:
- Aggregate steps using Health Connect aggregate APIs.
- Respect user-managed app priority and deduplication for Activity data.
- Keep raw per-source reads separate from aggregate totals.
- Request background read permission only if a justified feature requires it.
- Store WALKON's own activity sessions with unique IDs and provenance.

Google documentation:
- https://developer.android.com/health-and-fitness/health-connect/aggregate-data
- https://support.google.com/android/answer/16786157

## 7. Product experience to study against reference apps

Reference workflow checklist for user-provided screen recordings:
1. App launch and permission onboarding.
2. Daily step total and source breakdown.
3. GPS signal / accuracy indicator before start.
4. Start, pause, resume, manual finish and discard.
5. Live stats and map/stats screen switching.
6. Background / locked-screen recording.
7. GPS loss and recovery.
8. Saved activity summary, route map, splits, pace, elevation.
9. Edit title / privacy / notes / photos.
10. Activity history and sharing.
11. Music controls / audio cues / Bluetooth heart-rate sensors.
12. Coaching videos, live trainer calls, ads, subscriptions and challenges.

Capture each app separately. Do not assume feature availability is identical across subscription tiers, regions, operating-system versions or device models.

## 8. Validation plan — acceptance gates

### Gate A: daily steps
- Compare WALKON HealthKit daily total with Apple Health at the same timestamp.
- Repeat after backgrounding, force-closing/reopening, midnight and permission changes.
- Confirm no Core Motion session count is added to the daily total.
- Confirm no duplicate step samples are written.

### Gate B: session steps
- Record a known-duration walk with phone carried consistently.
- Compare session CMPedometer count with the corresponding HealthKit interval after HealthKit has processed samples.
- Explain expected timing/source differences; do not force equality if platform samples differ.
- Test pocket, hand-held and stationary cases.

### Gate C: route
- Record the same route in WALKON, Strava and Apple Fitness.
- Compare start/end, distance, route shape, GPS gaps, pace and elevation.
- Repeat in open sky, built-up streets, tree cover and with screen locked.
- Test pause/resume, phone call interruption, app suspension and low battery.
- Inspect raw timestamps and accuracy before changing filters.

### Gate D: persistence and recovery
- Kill/relaunch app during a session where platform behaviour permits.
- Test local save failure and HealthKit save failure separately.
- Verify exactly one activity after retries.
- Verify route points are retained and associated with the correct workout.

No feature is called production-ready until all applicable gates pass on the actual target iPhone.

## 9. Features deferred until recording is reliable

- Music integrations and in-app playback controls.
- Training video library and guided plans.
- Live trainer / coaching calls.
- Ads, subscriptions and referral monetisation.
- Community feed, leaderboards, challenges and route sharing.
- Wearable integrations beyond the native health store.

These are product opportunities, not prerequisites for accurate pedometer and GPS recording. Music should use platform-supported playback controls / Now Playing integration rather than attempting to embed or copy third-party music catalogues.

## 10. Decisions intentionally deferred until reference-app review

The core engineering decisions are specified in later sections. These product choices remain open:
- Exact live-screen metric layout and map/stats presentation.
- Whether music controls, audio cues or coaching belong in the first release.
- Whether and when a future Android app is in scope.
- Final visual identity and permanent app name.
- Fine-grained activity editing and sharing controls beyond private-by-default.

## 11. Current prototype gap list

The first WALKON Swift prototype is a scaffold, not a release candidate:
- Daily steps currently use a one-shot query; continuous observer/statistics updates are still required.
- Route recorder needs robust quality filtering, gap handling, recovery and background lifecycle work.
- Workout and HealthKit route saving are not yet implemented.
- Local storage should move from a UserDefaults JSON array to a transactional store.
- No real-device acceptance tests have passed yet.
- No cloud sync should be added until local recording is proven accurate.

## 12. Primary references

- Strava recording workflow: https://support.strava.com/en-us/articles/15402137-how-do-i-record-an-activity-in-strava
- Strava auto-pause caveats: https://support.strava.com/en-us/articles/15401874-how-do-i-fix-autopause-issues
- Apple HealthKit statistics collection: https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery
- Apple HealthKit statistics query guide: https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries
- Apple Core Motion pedometer: https://developer.apple.com/documentation/coremotion/cmpedometer
- Apple Core Location background updates: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- Android Health Connect aggregation and deduplication: https://developer.android.com/health-and-fitness/health-connect/aggregate-data
- Google Health Connect step source priority: https://support.google.com/android/answer/16786157

---
This document is intentionally a research draft. User screen recordings and further product research may change the proposed architecture before implementation.


## 13. Research update — native iPhone HealthKit workout sessions (WWDC25)

Research finding added 2026-11-07:
Apple's WWDC25 session documents a full HealthKit workout-session workflow on iPhone and iPad, including a live workout builder, lock-screen data access prompt, Live Activities, Siri workout controls and crash recovery. This is a major architecture improvement over the prototype's simple Core Motion timer.

Official source:
- https://developer.apple.com/videos/play/wwdc2025/322/
- https://developer.apple.com/documentation/healthkit/hkworkoutsession
- https://developer.apple.com/documentation/healthkit/building-a-workout-app-for-iphone-and-ipad

### Updated proposed recording architecture

1. Use HKWorkoutSession + HKLiveWorkoutBuilder as the authoritative lifecycle for a user-started iPhone workout (prepare, start, pause, resume, stop, finish).
2. Use HKLiveWorkoutBuilder delegate updates for live workout statistics and final HealthKit workout persistence; do not poll HealthKit repeatedly to redraw the live workout screen.
3. Use Core Location for outdoor GPS route points. HealthKit's HKWorkoutRouteBuilder remains responsible for associating the filtered route with the saved workout.
4. Keep Core Motion as a dedicated sensor input only if field tests show it provides a session step measure not already supplied appropriately by the live workout builder. Never add overlapping step sources.
5. Implement iPhone workout crash recovery using the scene connection recovery option and HKHealthStore.recoverActiveWorkoutSession, restoring the session, builder delegate and data source.
6. Use ActivityKit Live Activities for a minimal lock-screen workout display, and App Intents / Siri intents for start, pause, resume and end only after the core lifecycle is stable.
7. Handle lock-screen health-data privacy explicitly: metrics may be unavailable while locked unless the user accepts the system's workout data access prompt. Show duration or a clear unavailable state instead of fabricated zeros.

### Platform target decision

Historical note: this paragraph was superseded by the completed iOS 26 availability audit in Section 14. The final first-release deployment target is iOS 26.0+; the iOS 17 setting remains a prototype defect to correct during implementation.

### Important sensor distinction

HKLiveWorkoutBuilder supplies workout metrics and manages the workout's HealthKit lifecycle. Core Location still supplies the route coordinates. These are complementary roles, not competing GPS providers. The route must be filtered, inserted into HKWorkoutRouteBuilder during the workout, and finalized only after the workout is saved. Apple notes that route points can be noisy and recommends filtering; its sample guidance rejects horizontal accuracy worse than 50 metres and aims for location updates about every three seconds.

### Updated acceptance gate

- Start a native HKWorkoutSession on the actual iPhone.
- Lock the device and verify workout continues and the user-facing lock-screen experience behaves correctly.
- Confirm live builder metrics update without polling loops.
- Pause/resume and verify route segments do not bridge pauses.
- Force-crash/relaunch in a controlled test and verify HealthKit session recovery.
- Save workout first, then finish and associate the route.
- Verify one workout and one route appear in Apple Health/Fitness, with no duplicate step samples.
- Verify local activity still exists if route finalization or a HealthKit write fails.

This update supersedes the earlier assumption that a Core Motion-only custom session timer should be the main workout lifecycle. It remains a research proposal pending the exact iOS API availability audit and device tests.


## 14. API availability audit — deployment decision

Audit completed 2026-11-07 against Apple's iOS 26 release notes and WWDC25 sample documentation.

**Final platform decision: the first native iPhone release targets iOS 26.0 or later and uses the new iPhone-native workout-session workflow.** Apple's iOS 26 release notes explicitly state that `HKWorkoutSession` and `HKLiveWorkoutBuilder` workout-session APIs are now available on iOS and iPadOS. This is not an iOS 17 capability. The existing iOS 17 deployment setting is therefore incompatible with the proposed single-path workout engine.

Official confirmation:
- https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes
- https://developer.apple.com/videos/play/wwdc2025/322/
- https://developer.apple.com/documentation/healthkit/building-a-workout-app-for-iphone-and-ipad

Implementation implications:
- Change the WALKON iOS deployment target to iOS 26.0 when implementation is approved; do not change it prematurely in the current research branch.
- Use the new `HKWorkoutSession(healthStore:configuration:)` and `HKLiveWorkoutBuilder` APIs for the iPhone workout lifecycle.
- Do not use iOS 27-only workout-zone APIs as a baseline. Gate any future zone features with availability checks.
- Keep Core Location route capture and HealthKit route association as distinct cooperating components.
- Keep CMPedometer as a separately validated step sensor/fallback only; do not add its count to HealthKit's daily aggregate or duplicate HealthKit workout metrics.
- The WWDC25 Apple sample is the implementation reference. It requires the latest Xcode and a physical device for meaningful live sensor tests; simulator success alone is not acceptance.

**Compatibility trade-off:** choosing iOS 26+ excludes older iPhones that cannot run iOS 26. The iPhone 12 Pro Max is included in Apple's iOS 26 compatibility list. A physical-device build and runtime test are still required; model compatibility alone does not prove the app works.

The existing iOS 17 value in `ios/project.yml` is now a known prototype configuration defect. Change it to iOS 26.0 in the implementation configuration before building the production workout engine.


### Device compatibility check

Apple's current iOS 26 compatibility list explicitly includes iPhone 12 Pro Max:
- https://support.apple.com/en-in/123705
- https://support.apple.com/en-in/guide/iphone/iphe3fa5df43/ios

Therefore the user's iPhone 12 Pro Max is eligible for the iOS 26+ native workout-session architecture. The user-reported installed iOS 27.0.1 is newer than the minimum API generation. Actual device build, entitlements, Health permissions and field behaviour still require testing; model compatibility alone does not prove runtime success.


## 15. Build specification — recording engine

This section converts the research findings into an implementation contract. It is the build plan; it is not a claim that the app has been implemented or passed device tests.

### 15.1 Authoritative ownership by subsystem

| Concern | Owner | Must not do |
|---|---|---|
| Workout lifecycle and HealthKit workout metrics | HKWorkoutSession + HKLiveWorkoutBuilder | Run a competing timer/state machine as the source of workout truth |
| GPS coordinates and route quality | Core Location route recorder | Invent coordinates across GPS gaps |
| Daily all-source steps | HealthKit cumulative statistics query | Add session pedometer values |
| Optional session-only step display | CMPedometer, only after validation | Write duplicate step samples or add to daily total |
| Durable local history | Transactional local database | Store unbounded route arrays in UserDefaults |
| HealthKit route association | HKWorkoutRouteBuilder | Treat a local polyline as a saved HealthKit route |
| Lock-screen workout summary | ActivityKit | Expose unavailable/private health values |

### 15.2 Session start sequence

1. User taps Start.
2. Validate HealthKit availability and required authorization; request only relevant types.
3. Validate Core Location permission and accuracy authorization. Explain why location is needed.
4. Create a new local workout UUID and durable draft record before sensors start.
5. Create outdoor walking HKWorkoutConfiguration, HKWorkoutSession, associated builder and HKLiveWorkoutDataSource; attach delegates.
6. Create HKWorkoutRouteBuilder and configure Core Location for workout recording.
7. Call prepare; show a short ready/countdown state. Do not wait indefinitely for a perfect GPS fix.
8. Start the workout and builder collection at the same timestamp; mark the local session recording.
9. Start ActivityKit only after the core lifecycle is running.
10. Show GPS quality separately from workout state: acquiring / good / weak / unavailable.

If HealthKit workout authorization or service is unavailable, show a clear blocker or a deliberately designed local-only fallback. Never silently claim that an Apple Health workout will be saved when it will not.

### 15.3 Live collection

- Workout state transitions come from HKWorkoutSessionDelegate, not UI button optimism.
- Live metric updates come from HKLiveWorkoutBuilderDelegate.
- Route samples come from CLLocationManager and are independently timestamped.
- Persist route points incrementally in bounded batches; retain a recoverable draft after every batch.
- Keep elapsed time distinct from moving time.
- Derive distance only from accepted route segments. A GPS gap is a gap, not a straight-line shortcut.
- Pace is unavailable until enough valid distance/time exists; suppress unstable instantaneous values.
- No heart-rate value is displayed unless a paired sensor provides it.
- No calorie or elevation estimate is labelled measured unless its source and method are clear.

### 15.4 Pause and resume

- Manual pause is mandatory and authoritative.
- On pause, pause the HealthKit workout session and close the current route segment. Keep the workout draft.
- On resume, resume the session and start a new route segment; never connect across the paused interval.
- Auto-pause is OFF by default for walking. Strava's current support guidance warns that slow walking and obscured GPS can cause false pause/resume behaviour. If added later, it must be opt-in, have conservative thresholds, and be separately field-tested.
- Pause/resume transitions must be idempotent; repeated taps cannot create duplicate transitions.

### 15.5 Finish and save transaction

1. Enter finishing state; disable duplicate finish actions.
2. Stop Core Location capture and flush accepted route points.
3. Stop the HealthKit workout session and wait for its stopped transition.
4. End builder collection and finish the HealthKit workout using the documented builder lifecycle.
5. Commit the completed local workout and route in a database transaction.
6. Finish the HealthKit route builder against the saved workout, associating exactly one route.
7. Persist HealthKit workout/route identifiers and per-stage save outcomes.
8. If HealthKit workout save fails, keep the local activity and show retry.
9. If route association fails after workout save, keep both the local route and HealthKit workout, show route-save failure, and allow an idempotent retry where supported.
10. Never repeat the workout save simply because route finalization failed.

### 15.6 Crash and interruption recovery

- Implement the iOS scene connection recovery path shown in Apple's WWDC25 sample: inspect `shouldHandleActiveWorkoutRecovery`, call `recoverActiveWorkoutSession`, restore the session and associated builder, reattach delegates and recreate the live data source.
- Restore WALKON's local draft by UUID and reconcile it with the recovered HealthKit session.
- Store a durable event journal for start, pause, resume, location batches, finish intent, HealthKit save result and route save result.
- On recovery, detect missing intervals and represent them as gaps; never fabricate elapsed route or steps.
- Handle phone calls, audio interruptions, permission revocation, low storage and location-service shutdown as explicit interruption states.
- Background location must be configured for the active workout only, with the required usage description and background mode. Explain that iOS scheduling and GPS reception cannot be guaranteed in every condition.

### 15.7 Local persistence

Use SQLite with the schema and transaction rules in Section 17. Preferred logical entities:
- Workout(id, type, state, start/end, elapsed/moving time, distance, metrics, algorithmVersion)
- RouteSegment(id, workoutId, sequence, start/end)
- RoutePoint(id, segmentId, timestamp, latitude, longitude, horizontalAccuracy, altitude, verticalAccuracy, speed)
- WorkoutEvent(id, workoutId, timestamp, eventType, payload)
- HealthKitLink(workoutId, healthKitWorkoutUUID, routeUUID, saveState)

Store route points in append-only batches and index by workout/segment/time. Keep raw accepted points and derived summaries separate. No cloud dependency in v1.

### 15.8 Daily step service

- Use HKStatisticsCollectionQuery with cumulative sum and local-day calendar boundaries for the dashboard.
- Register an HKObserverQuery and enable background delivery where available/approved; use it to trigger a refresh, not as the step total itself.
- Re-run the statistics collection query after observer notification and on foreground activation, timezone/day change and permission changes.
- Display last refreshed time and distinguish unavailable, no samples and query failure. HealthKit read denial may not be directly distinguishable from no data.
- Do not use a hard-coded offset or source-priority rule to force WALKON to match another app.

### 15.9 Security and privacy

- Request the minimum HealthKit read/share types and location permissions needed for the chosen feature.
- Provide clear purpose strings for Health and location access.
- Do not collect location outside an explicitly active recording session.
- Keep route privacy private by default. No upload, sharing or social exposure in v1.
- No advertising SDK, analytics SDK, account requirement or cloud sync in the core recorder until privacy disclosures and product need are reviewed.
- Provide user-controlled deletion of local workout history and explain separately how HealthKit records are managed.

### 15.10 Required project configuration

- Native SwiftUI iOS app; no web wrapper.
- Deployment target iOS 26.0+ for the new iPhone HealthKit workout-session API path.
- HealthKit capability and correct entitlement.
- Background Modes: Location updates only for active workout recording.
- Usage descriptions for HealthKit and location access.
- ActivityKit only for the lock-screen workout summary.
- App Intents / Siri controls are a later layer after core start/pause/resume/end reliability.
- Latest stable Xcode and SDK compatible with the target iOS.
- Signing team, bundle identifier and provisioning profile configured for device/TestFlight builds.

### 15.11 Release gates

A release candidate is not deployable until all of these pass:

**Compile and static checks**
- Clean XcodeGen generation and clean Release build.
- No missing entitlements, usage descriptions or signing warnings.
- No unhandled Swift concurrency/data-race warnings in the workout engine.

**Functional tests**
- HealthKit daily steps refresh correctly and are not combined with session steps.
- Start, pause, resume, finish, discard and retry are idempotent.
- GPS route captures timestamped accepted points and preserves gaps.
- Workout and route each appear once in Apple Health/Fitness.
- Local workout survives HealthKit failure and app relaunch.
- Recovery after controlled crash reattaches to the active HealthKit workout.
- Lock screen shows only data available under the user's privacy authorization.
- Battery, thermal and storage use are measured during a 2-hour recording.

**Field matrix**
- iPhone 12 Pro Max on the user's installed iOS version.
- Open sky, urban canyon, tree cover and indoor/no-GPS cases.
- Phone in pocket, hand-held and screen locked.
- Walk at slow, normal and brisk pace.
- Manual pause/resume, phone call interruption, app crash and low battery.
- Compare the same route with Apple Fitness and Strava; explain differences from raw GPS and source timing rather than forcing values to match.

**Distribution**
- Archive a signed Release build.
- Install and smoke-test the archive on the target iPhone.
- TestFlight internal distribution and install/update/rollback check.
- App privacy details, HealthKit disclosure and location usage reviewed before App Store submission.

No simulator-only pass can satisfy the real-device GPS, motion, HealthKit, background or crash-recovery gates.


## 16. Implementation sequence and handoff definition

The build should proceed in controlled vertical slices. Each slice must compile and have its own test evidence before the next slice is merged.

1. **Foundation and project configuration**
   - Align XcodeGen deployment target to iOS 26.0.
   - Verify HealthKit entitlement, Info.plist purpose strings, background location capability and app lifecycle delegates.
   - Establish Swift concurrency boundaries and a single WorkoutCoordinator actor/owner for session transitions.
2. **Persistence first**
   - Implement local database schema, migrations, draft journal and append-only route storage.
   - Add idempotency keys and recovery tests before enabling live recording.
3. **HealthKit workout lifecycle**
   - Port the Apple sample lifecycle into a WALKON service, adapted for outdoor walking.
   - Implement builder metrics, delegate state, pause/resume, finish and iPhone crash recovery.
4. **GPS route recorder**
   - Implement Core Location permission/accuracy states, route segment model, filtering, gap detection, distance calculation and incremental route builder insertion.
5. **Daily steps**
   - Implement HealthKit daily cumulative statistics and observer-triggered refresh.
   - Validate daily total independently from any live workout/session steps.
6. **Dashboard and recording UI**
   - Build the final user interface only against stable service contracts.
   - Clearly show recording, paused, GPS quality, save progress, failure and recovery states.
7. **HealthKit route association and history**
   - Save workout once, finalize route association, persist identifiers and render saved activity detail.
8. **Device validation**
   - Execute the full release gates on the iPhone 12 Pro Max. Capture logs and compare matching walks with Apple Fitness and Strava.
9. **Release**
   - Configure signing, archive, install, TestFlight, privacy disclosures and rollback plan.

### Files to replace or add in the current scaffold

Replace the prototype implementations rather than layering more logic into them:
- `HealthSteps.swift` → HealthKit daily summary service with statistics collection + observer.
- `WalkTracker.swift` → split into WorkoutCoordinator (HealthKit lifecycle) and RouteRecorder (Core Location).
- `ActivityStore.swift` → transactional persistence repository and recovery journal.
- `DashboardView.swift` → UI built after service state models stabilize.
- `WALKONApp.swift` → app/scene delegate integration for HealthKit crash recovery.
- Add focused test targets for state transitions, distance/filter logic, persistence idempotency and recovery reconciliation.

### Build/deploy environment requirement

The current GitHub Actions workflow uses a macOS 15 runner and the existing project spec still says iOS 17. Both are prototype-era settings and must be updated before the first implementation build. The implementation workflow must select a GitHub-hosted macOS runner that has Xcode 26 installed, verify the selected Xcode version in CI, generate the project from XcodeGen, build Debug and Release simulator targets, run unit tests, and produce a signed device archive only in a signing-enabled release job. Never assume a runner label guarantees a particular Xcode version; assert it in the workflow and fail early if the SDK is missing.

### Handoff definition: “blueprint ready to build”

The blueprint is considered ready for implementation when:
- subsystem ownership and data boundaries are fixed;
- the iOS minimum and device compatibility are explicit;
- every lifecycle transition and failure path is specified;
- persistence/recovery and HealthKit save ordering are defined;
- privacy, permissions and background execution are specified;
- implementation slices, test matrix and release gates are documented.

The blueprint does not mean the app is already built, signed, installed or validated. Those are subsequent engineering and release milestones.


## 17. Final architecture decisions — persistence and save recovery

### 17.1 Route builder construction and lifetime

- Obtain the HealthKit route builder through the workout builder's `seriesBuilder(for: HKSeriesType.workoutRoute())` API where supported by the SDK; do not directly instantiate `HKWorkoutRouteBuilder` as the primary path.
- Retain the route builder strongly for the entire recording and finalization lifecycle.
- Insert accepted Core Location samples incrementally; batch inserts to avoid excessive callback overhead.
- After the workout has been successfully saved, call `finishRoute(with:metadata:)` and await completion.
- If route finalization fails, do not attempt to associate the same route builder with a different workout. Retain the local route and report the HealthKit route failure. Retry only where the HealthKit builder lifecycle explicitly permits it; otherwise preserve local route and provide a safe retry strategy that creates a new route builder from retained points.
- Never release the route builder before finalization completes.

Apple API reference: https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder

### 17.2 Local database decision

**Decision: use SQLite as the local source of truth for the first release, not UserDefaults and not an unbounded SwiftData route array.**

Rationale:
- Route points are append-heavy time-series records and need indexed queries by workout, segment and timestamp.
- WAL transactions allow durable batched writes while the workout continues.
- The event journal and save-state transitions must commit atomically with the related workout state.
- SQLite gives explicit control over schema migrations, uniqueness constraints, foreign keys, WAL checkpoints and recovery diagnostics.
- Use Apple's system SQLite3 module directly initially; avoid adding a third-party database dependency until there is a demonstrated need.

Required database configuration and constraints:
- Enable foreign keys and WAL mode.
- Use a busy timeout and bounded write batches.
- Add unique constraints for workout UUID and event idempotency key.
- Store route points in append-only rows, with a monotonically increasing sequence per route segment.
- Commit each route batch and its last acknowledged sequence in one transaction.
- Use database migrations with a schema version table.
- Run integrity checks in diagnostics and tests; never delete a recoverable draft automatically after an error.

### 17.3 Two-phase workout finalization

Model finish as a durable state machine:
- recording → finishing → workoutSaved → routeFinalizing → completed
- any stage may transition to a recoverable failure state with a stored error code and retry eligibility.

Before external HealthKit operations, persist a finish-intent event and freeze the session's final metrics/route-point sequence. Save the HealthKit workout once and persist its identifier. Then finalise the route against that exact saved workout. The local record remains authoritative for recovery if the app terminates between stages.

Idempotency rules:
- A repeated Finish tap returns the existing finalization task/result.
- A repeated workout-save attempt first reconciles against the persisted HealthKit workout UUID/metadata and must not create a duplicate.
- Route finalization is tracked independently from workout saving.
- A route failure must never trigger a second workout save.
- A local commit failure must not be represented as success even if HealthKit has saved a workout; recovery reconciles HealthKit and local journal on next launch.

### 17.4 HealthKit metrics and step-count boundary

The live workout builder is the workout lifecycle and live statistics source, but it must not be assumed to provide every metric on every device or configuration. At runtime:
- Query the builder's available statistics by quantity type.
- Treat absent metrics as unavailable, not zero.
- Daily steps remain the HealthKit cumulative daily aggregate.
- If the live builder supplies a valid session step statistic, use it as the session step value.
- If it does not, validate CMPedometer as the session-only source on device. Do not sum both.
- Do not create or write step samples from the same walking session merely to make daily totals appear to match.
- Preserve metric provenance and unit in the local workout record.

### 17.5 Strava behaviour translated into WALKON requirements

Strava's public recording workflow supports switching between map and stats, manual pause, finish/save, activity title/privacy, GPS quality indication, and optional audio cues. Its current guidance specifically recommends disabling auto-pause for walks/hikes because slower movement can cause repeated pauses or failure to resume.

WALKON v1 therefore adopts:
- Map/stats display switch.
- Visible GPS quality indicator.
- Manual pause/resume as primary controls.
- Auto-pause disabled by default for walking.
- Explicit save/discard confirmation and recoverable local draft.
- Privacy set to private by default.
- Audio cues and Live Activity as later features, not prerequisites.

Sources:
- https://support.strava.com/en-us/articles/15402137-how-do-i-record-an-activity-in-strava
- https://support.strava.com/en-us/articles/15401874-how-do-i-fix-autopause-issues

### 17.6 Android platform decision

If/when Android is approved, use Health Connect for aggregated step reading and app-priority-aware data access. Do not begin a new integration against Google Fit APIs: Google states those APIs are supported only through the end of 2026 and recommends Health Connect for mobile step tracking.

Source: https://developer.android.com/health-and-fitness/health-connect/migration/fit

Android implementation is not part of the iPhone v1 delivery.


## 18. Existing scaffold audit — exact replacement specification

Audit date: 2026-11-07. Audited the current committed Swift files, Info.plist, entitlements and XcodeGen spec on main. The current app is a visual/functional stub only. It must not be used for a real walk or described as an accurate recorder.

### 18.1 File-by-file findings

| Current file | Defect in current implementation | Required replacement |
|---|---|---|
| `WALKONApp.swift` | No UIApplicationDelegate/scene recovery integration; no dependency composition or database bootstrap | Add app delegate adaptor and scene lifecycle recovery coordinator; open/migrate SQLite before showing dashboard; surface bootstrap failure |
| `DashboardView.swift` | UI directly owns prototype services; Start/Finish only; no pause/resume/discard; no permission/error/save states; no route map; assumes metric values exist | Make a presentation-only view observing typed app state; route all actions through WorkoutCoordinator; show explicit GPS and Health states, map/stats switch, pause/resume/finish/discard, saving/retry and recoverable draft |
| `HealthSteps.swift` | One-shot HKStatisticsQuery; no observer/background refresh/day rollover; reports authorization success as connected although read grants cannot be inferred; query errors discarded; silently shows zero | Replace with HealthKitDailyStepsService using HKStatisticsCollectionQuery + HKObserverQuery, explicit unavailable/no-data/error/refreshing states, local calendar boundaries, foreground and timezone refresh |
| `WalkTracker.swift` | Bypasses HKWorkoutSession; no pause/resume; requests When-In-Use at start then starts GPS without waiting for authorization; no Always/background recovery path; no timestamps stored; no stale/out-of-order checks; simplistic 40m filter and 100m jump rule; sums all accepted deltas; no gap markers; no final pedometer reconciliation; no error handling | Delete as the owner of workout lifecycle. Split into WorkoutCoordinator (HealthKit session state) and RouteRecorder (Core Location sampling/filtering). Optional SessionStepProvider wraps CMPedometer only if validated as the chosen session step source |
| `ActivityStore.swift` | Entire unbounded history and route arrays encoded to UserDefaults; duplicate saves insert duplicate sessions; no durable drafts, transactions, event journal, migrations or route indexing | Replace with SQLiteWorkoutRepository, versioned schema, foreign keys, WAL, unique workout IDs, append-only RoutePoint storage, transaction APIs, recovery journal and idempotent state transitions |
| `Info.plist` | Missing HealthKit write usage description for saving workouts; location Always purpose string exists but code does not request/handle authorization state; no explicit app background lifecycle configuration contract | Add `NSHealthUpdateUsageDescription`; retain minimum Health read/location purpose strings; request Always only if required by tested background design and explain the purpose; validate background location mode and runtime authorization |
| `WALKON.entitlements` | HealthKit entitlement present; no build-time check that signing profile includes it | Keep entitlement; verify signed provisioning profile contains HealthKit capability; fail release build if missing |
| `ios/project.yml` | Deployment target iOS 17 conflicts with chosen iOS 26 workout-session architecture; no unit test target or explicit generated project settings for supported orientations/privacy manifest | Set iOS 26.0; add test target and explicit bundle/build settings; add privacy manifest only if included SDKs or collected data require it; validate generated Info.plist and signing |
| `.github/workflows/walkon-ios-build.yml` | macOS-15 runner does not guarantee Xcode 26; only simulator Debug build; no unit tests, Release build, artifact retention or version assertion | Use an available runner with Xcode 26; assert `xcodebuild -version` and iOS SDK; generate project; build Debug + Release simulator; run unit tests; archive device build only in a separately configured signing job |

### 18.2 Required replacement/additional source files

- `AppEnvironment.swift`: owns shared services and bootstrapping.
- `WorkoutCoordinator.swift`: actor or main-actor-isolated state owner for HKWorkoutSession, HKLiveWorkoutBuilder, delegate callbacks, lifecycle transitions and recovery.
- `RouteRecorder.swift`: Core Location authorization, active-session updates, route point validation, segment boundaries, gap markers and incremental HealthKit route-series insertion.
- `HealthKitDailyStepsService.swift`: daily cumulative query, observer query, background delivery, day rollover and explicit query states.
- `SessionStepProvider.swift`: optional CMPedometer wrapper; used only if the builder does not provide a validated session step quantity.
- `SQLiteWorkoutRepository.swift`: migrations, transaction boundaries, append-only route batches, draft reads and idempotent finalization.
- `WorkoutRecoveryCoordinator.swift`: reconcile scene-recovered HealthKit session with local event journal and saved workout IDs.
- `WorkoutModels.swift`: typed states, metric provenance, route sample, route segment, error and save outcome models.
- `WorkoutMapView.swift`: render route points and GPS gaps without mutating source data.
- `HealthKitAuthorizationService.swift`: minimum read/share type set and request status messaging.
- `ActivityLiveStatus.swift`: optional ActivityKit surface after core recording works.
- Test target: `WorkoutStateMachineTests.swift`, `RouteRecorderTests.swift`, `SQLiteWorkoutRepositoryTests.swift`, `HealthKitMappingTests.swift`, `WorkoutRecoveryTests.swift`.

### 18.3 Required type/state contracts

Workout state must be an enum, not unrelated booleans:
- idle
- authorizing
- preparing
- recording
- paused
- finishing
- workoutSaved
- routeFinalizing
- completed
- recoverableFailure

Every transition is validated centrally. UI commands are intents; the UI must wait for the delegate/platform-confirmed transition before displaying success.

GPS quality must be a separate enum:
- permissionRequired
- servicesDisabled
- acquiring
- good
- weak
- unavailable

Save status must be separate from workout state:
- notStarted
- localDraftSaved
- workoutSavePending
- workoutSaved
- routeSavePending
- completed
- retryableFailure

A session metric must carry value, unit, source, sample interval and availability. A missing statistic is nil/unavailable, not numeric zero.

### 18.4 Required unit and integration tests

**Workout state machine**
- Start while already recording is ignored without a second HealthKit session.
- Pause while idle and resume while idle are rejected.
- Pause/resume transitions occur only after delegate confirmation.
- Repeated Finish taps create one finalization operation.
- Discard removes only the draft and never deletes an already completed HealthKit workout.
- HealthKit session error moves to recoverableFailure with the platform error preserved.

**Route validation**
- Reject negative horizontal accuracy, invalid coordinates, stale timestamps and out-of-order points.
- Reject implausible speed/displacement spikes.
- Do not add distance for a rejected point.
- A long GPS gap starts a new segment; no line/distance is fabricated across it.
- Pause/resume creates separate segments.
- Reprocessing the same raw route with the same algorithm version produces deterministic distance.
- Route point timestamp, horizontal accuracy and source are persisted.

**SQLite and idempotency**
- Appending route batches then force-terminating preserves committed batches.
- A duplicate point batch ID cannot duplicate points.
- Duplicate workout UUID insertion fails safely.
- Schema migration preserves completed sessions and drafts.
- Foreign-key violation rolls back the entire transaction.
- A crash between workout save and route finalization recovers to routeFinalizing, not a second workout save.
- A local DB failure after HealthKit save is reconciled on next launch.

**HealthKit mapping**
- Daily total uses the local calendar day and cumulative sum.
- Observer notifications trigger a fresh aggregate query.
- Midnight/timezone changes refresh the day predicate.
- Query error, no samples and unavailable HealthKit remain distinguishable.
- Builder metrics are mapped only when the matching quantity statistic exists.
- Session steps use exactly one selected source; daily total is never incremented manually.

**Device integration**
- Start/stop outdoor walk and confirm one HealthKit workout.
- Confirm one HealthKit route associated with that workout.
- Lock screen, background, phone-call interruption and controlled crash recovery.
- Health read/share permissions denied or revoked.
- Location denied, reduced accuracy, Always denied, services disabled and GPS loss.
- Low storage, low battery and app termination.
- Run on iPhone 12 Pro Max on installed iOS 27.0.1; simulator cannot replace these tests.

### 18.5 Immediate implementation blockers

1. The current project is configured for iOS 17 and cannot be the final project configuration for the chosen iOS 26+ workflow.
2. No HealthKit workout session or workout route saving exists in the current code.
3. No pause/resume or durable route persistence exists.
4. Existing route samples lose timestamps and accuracy metadata.
5. Existing step query can misrepresent access state and becomes stale.
6. No recovery integration exists.
7. No test target or signed device build evidence exists.

These are code defects and missing capabilities, not user setup problems. Do not ask the user to repair them manually.


## 19. SQLite schema — v1 normative specification

The following is the logical v1 schema. Use SQLite INTEGER for UTC epoch milliseconds, REAL for coordinates/measurements, TEXT for UUIDs/enums/JSON metadata. All writes use prepared statements and bound parameters. Enable `PRAGMA foreign_keys=ON`, `journal_mode=WAL`, `synchronous=FULL`, and a bounded `busy_timeout`. Use one serialized database writer; readers may use separate read-only connections.

```sql
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at_ms INTEGER NOT NULL
);

CREATE TABLE workouts (
  id TEXT PRIMARY KEY NOT NULL,
  activity_type TEXT NOT NULL CHECK (activity_type = 'walking'),
  state TEXT NOT NULL CHECK (state IN (
    'draft','recording','paused','finishing','workout_saved',
    'route_finalizing','completed','recoverable_failure','discarded'
  )),
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER,
  elapsed_seconds REAL,
  moving_seconds REAL,
  distance_m REAL NOT NULL DEFAULT 0 CHECK (distance_m >= 0),
  session_steps INTEGER CHECK (session_steps IS NULL OR session_steps >= 0),
  session_steps_source TEXT,
  elevation_gain_m REAL,
  algorithm_version TEXT NOT NULL,
  healthkit_workout_uuid TEXT UNIQUE,
  healthkit_route_uuid TEXT UNIQUE,
  healthkit_workout_state TEXT NOT NULL DEFAULT 'not_started',
  healthkit_route_state TEXT NOT NULL DEFAULT 'not_started',
  last_error_domain TEXT,
  last_error_code INTEGER,
  last_error_message TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE route_segments (
  id TEXT PRIMARY KEY NOT NULL,
  workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK (sequence >= 0),
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER,
  close_reason TEXT CHECK (close_reason IN (
    'pause','gps_gap','finish','interruption','recovery'
  )),
  UNIQUE(workout_id, sequence)
);

CREATE TABLE route_points (
  id TEXT PRIMARY KEY NOT NULL,
  workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  segment_id TEXT NOT NULL REFERENCES route_segments(id) ON DELETE CASCADE,
  sequence INTEGER NOT NULL CHECK (sequence >= 0),
  timestamp_ms INTEGER NOT NULL,
  latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  horizontal_accuracy_m REAL NOT NULL,
  altitude_m REAL,
  vertical_accuracy_m REAL,
  speed_mps REAL,
  course_degrees REAL,
  source TEXT NOT NULL DEFAULT 'core_location',
  accepted INTEGER NOT NULL CHECK (accepted IN (0,1)),
  rejection_reason TEXT,
  UNIQUE(segment_id, sequence)
);

CREATE TABLE workout_events (
  id TEXT PRIMARY KEY NOT NULL,
  workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  idempotency_key TEXT NOT NULL UNIQUE,
  sequence INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  UNIQUE(workout_id, sequence)
);

CREATE TABLE metric_samples (
  id TEXT PRIMARY KEY NOT NULL,
  workout_id TEXT NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  metric_type TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT NOT NULL,
  source TEXT NOT NULL,
  start_at_ms INTEGER,
  end_at_ms INTEGER,
  availability TEXT NOT NULL CHECK (availability IN ('available','estimated')),
  UNIQUE(workout_id, metric_type, source, start_at_ms, end_at_ms)
);

CREATE INDEX idx_workouts_started ON workouts(started_at_ms DESC);
CREATE INDEX idx_workouts_state ON workouts(state);
CREATE INDEX idx_route_segments_workout ON route_segments(workout_id, sequence);
CREATE INDEX idx_route_points_workout_time ON route_points(workout_id, timestamp_ms);
CREATE INDEX idx_route_points_segment_sequence ON route_points(segment_id, sequence);
CREATE INDEX idx_workout_events_workout_sequence ON workout_events(workout_id, sequence);
CREATE INDEX idx_metric_samples_workout_type ON metric_samples(workout_id, metric_type);
```

### Schema invariants

- A workout row is created before any sensors start.
- Route points are written in batches with monotonically increasing segment sequence numbers.
- The same event idempotency key can be committed only once.
- A route point belongs to exactly one segment and one workout.
- No segment is allowed to connect across pause or a declared GPS gap.
- Completed rows are immutable except for explicit metadata edits and a retryable HealthKit route-save state transition.
- Deleting a local workout cascades only local records; it never silently deletes HealthKit data.
- Persisted errors are diagnostic, user-safe summaries; never store access tokens or sensitive raw HealthKit payloads.
- Use a database transaction for workout state change + event journal insertion + final metrics update.
- Do not store an entire route as JSON in one row.

### Route batch commit contract

Input: workout UUID, segment UUID, batch UUID/idempotency key, ordered validated CLLocation-derived point records, cumulative distance delta, and algorithm version.

Transaction:
1. Check whether batch idempotency key already exists.
2. If it exists, return the prior commit result without inserting points or adding distance again.
3. Insert all route points and their source accuracy metadata.
4. Update workout distance and last committed route sequence.
5. Insert a `route_batch_committed` journal event with the batch key.
6. Commit atomically.

If any step fails, roll back all of it. The in-memory recorder must retain uncommitted points and retry; it must not acknowledge a batch before commit.

### Retention and privacy

- No server sync in v1.
- Route points are private local workout data.
- Provide an explicit delete-history operation with confirmation.
- HealthKit records are independent; local deletion must explain that it does not delete the corresponding Apple Health workout/route.
- No advertising identifiers, background location collection outside an active recording, or route upload.

## 20. Service interface contracts — v1

These are behavioural contracts; exact Swift signatures can be adjusted to match the SDK's concurrency annotations, but ownership and semantics must remain fixed.

### WorkoutCoordinator
Owns one HealthKit workout session and one associated live builder.
- `startWalking()`: async; creates local draft first, then HealthKit session/builder, then starts collection; returns only after platform start is accepted.
- `pause()`: async; requests pause and waits for delegate state confirmation before reporting paused.
- `resume()`: async; requests resume and waits for delegate state confirmation.
- `finish()`: async; single-flight operation; freezes final route sequence, stops capture, ends collection, saves workout once, then delegates route finalization.
- `discard()`: async; only for an unsaved draft; stops session, calls builder discard, closes route capture, deletes local draft transactionally.
- `recover(session:)`: async; reattaches delegates and new live data source, reconciles session state against local journal, resumes route capture only when state permits.
- Publishes typed workout state, available metric values, errors and save state. Never exposes mutable HK objects to the UI.

### RouteRecorder
- `requestAuthorizationIfNeeded()`: async; resolves authorization and accuracy state before starting location.
- `begin(workoutID:segmentID:)`: starts Core Location only for the active workout.
- `append(locations:)`: validates timestamps, accuracy, coordinates and plausibility; records accepted and rejected sample diagnostics; emits gap events when continuity is unsafe.
- `pause(reason:)`: stops accumulating route distance and closes the current segment.
- `resume()`: opens a new segment; no connection to the previous segment.
- `finish()`: stops updates, flushes pending durable batches and returns the final accepted route sequence.
- `recover(workoutID:)`: restores local segment sequence and starts a new segment; never fabricates the missing interval.
- Maintains a strong reference to the HealthKit route series builder owned by the active workout service; serializes insert calls and awaits completion.

### HealthKitDailyStepsService
- `requestReadAccess()`: requests only step-count read access.
- `refreshToday()`: executes a cumulative statistics collection query for the current local calendar day.
- `startObserving()`: registers an observer query and background delivery when supported; observer callback triggers aggregate refresh and calls the completion handler promptly.
- `stopObserving()`: stops observation when app lifecycle or authorization requires it.
- `handleCalendarChange()`: recalculates day boundaries and refreshes.
- Publishes `unavailable`, `loading`, `noSamples`, `available(value,lastUpdated)`, or `queryError`. It must not infer read authorization from the requestAuthorization completion Boolean.

### SQLiteWorkoutRepository
- `createDraft(id,start,algorithmVersion)`
- `appendRouteBatch(batch)`
- `appendEvent(event)`
- `transitionWorkout(id,expectedState,newState,event)`
- `recordWorkoutSaved(id,healthKitUUID,finalMetrics)`
- `recordRouteSaved(id,healthKitRouteUUID)`
- `loadRecoverableDrafts()`
- `loadWorkoutHistory(limit,offset)`
- `deleteLocalWorkout(id)`
All state transitions use compare-and-set semantics: update only if the stored current state matches the expected state. A failed precondition returns a typed conflict, not a silent overwrite.

### HealthKit route save ordering

1. Keep the `HKWorkoutRouteBuilder` created by `workoutBuilder.seriesBuilder(for: HKSeriesType.workoutRoute())` strongly retained.
2. Insert filtered CLLocation batches during recording and await each insertion completion before marking the corresponding route batch as delivered to HealthKit.
3. Stop route capture and flush pending local batches.
4. End workout collection and call `finishWorkout`; persist the returned workout UUID.
5. Call `finishRoute(with:metadata:completion:)` on the retained route builder using that exact workout.
6. Persist the returned route UUID and completed state.
7. If the process crashes between steps 4 and 6, recover the active or saved workout state, inspect local journal and HealthKit records, and never create a duplicate workout. A route that cannot be safely resumed from the retained builder is rebuilt only from the durable local route points using a new valid route builder associated with the already-saved workout, if HealthKit permits it; otherwise preserve local route and report HealthKit route failure.

Apple references:
- https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder
- https://developer.apple.com/videos/play/wwdc2025/322/
- https://developer.apple.com/documentation/healthkit/hkhealthstore/recoveractiveworkoutsession(completion:)


## 21. Background GPS and authorization — final iOS 26+ decision

**Decision: use the modern Core Location background activity model for an active workout, with When In Use authorization as the default. Do not request Always authorization by default.**

Apple documents that a fitness workout is a valid reason for real-time background location. For a modern implementation:
- Create a `CLServiceSession` with `.whenInUse` authorization requirement while the app is in the foreground.
- Create and retain a `CLBackgroundActivitySession` for the active user-started workout.
- Enable the Location updates background mode.
- Use the modern Core Location update stream for the route recorder, consuming every delivered update and preserving timestamps/accuracy.
- Recreate the service session immediately when the app is relaunched in the background to process queued updates, where the system delivers them.
- End both sessions immediately when the workout is paused/finished/discarded, subject to the desired pause semantics; while paused, stop route accumulation and do not collect a path.
- Display the system location indicator and an in-app active recording indicator.
- Explain before the permission prompt that location is used only while a WALKON walk is recording, including when the screen is locked.

When In Use is sufficient for continuous background updates while the active location session is running. Always authorization is only needed if WALKON later requires the system to relaunch a terminated app for certain location events; it is not the default requirement for ordinary active workout tracking. If recovery testing proves Always is essential for a specific supported recovery path, request it separately with a clear explanation and explicit user choice.

Do not promise uninterrupted GPS after force-quit, power loss, disabled location services, permission revocation, or every system termination. A missing interval must become a visible route gap.

Apple references:
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession
- https://developer.apple.com/documentation/corelocation/clservicesession
- https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services

### Background GPS acceptance cases

- Start a walk in foreground; lock screen; verify location updates continue and the system indicator appears.
- Move app to background for 30 minutes; confirm timestamp continuity and battery use.
- Pause while backgrounded using the supported UI/Live Activity path; confirm route points stop accumulating.
- Resume and confirm a new segment starts.
- Terminate/crash app in a controlled test; verify HealthKit session recovery and Core Location queued-update handling; represent any unrecoverable interval as a gap.
- Revoke permission or disable Location Services mid-workout; show a clear degraded state and retain the local workout.
- Confirm no location updates continue after finish or discard.

Important platform distinction:
- `allowsBackgroundLocationUpdates = true` with `UIBackgroundModes=location` is the established CLLocationManager approach and remains a fallback if the modern service-session implementation is not supported by the SDK/device.
- Do not run both modern and legacy location pipelines simultaneously; that would duplicate route points.
- Choose one route update API per build configuration and cover it with route recorder tests.


## 22. Reference-app architecture investigation — public evidence only

Purpose: learn the engineering patterns behind established fitness platforms and reproduce the underlying quality outcomes using documented APIs and independent WALKON implementation. This is not a reverse-engineering attempt to obtain private source code, bypass app protections, inspect private endpoints, or copy proprietary algorithms/design.

Evidence labels used below:
- **Documented:** explicitly stated in public platform/vendor documentation.
- **Observed:** behaviour visible in a user-operated app or screen recording; implementation mechanism is not thereby known.
- **Inferred:** plausible engineering explanation consistent with documented behaviour; must not be represented as fact.
- **Unknown/private:** vendor implementation details not publicly established.

### 22.1 Strava — recording product and likely system architecture

**Documented / publicly observable**
- User-facing recording flow includes activity type, GPS acquisition/quality, start, pause/resume, finish/save, route and activity summary.
- Strava support explains recording and auto-pause behaviour. Slow walking/hiking can cause false auto-pause behaviour; its support guidance recommends turning auto-pause off for those activity types.
- Strava offers public APIs for authorised access to activity summaries and streams, but those APIs are not a specification of the private mobile recorder.

**Architecture hypotheses to test (not claims about Strava internals)**
- A live recorder likely separates sensor acquisition, location-quality evaluation, activity state, metric aggregation, persistence and post-save upload.
- Route geometry and distance likely use a quality-control stage rather than blindly summing every GPS point.
- A robust app must distinguish GPS fix quality from workout state; recording can be active while GPS is weak.
- Pause/resume should create separate movement segments or otherwise exclude paused time and distance.
- Activity summary values may be recomputed after recording from retained samples, rather than relying only on the live display accumulator.

**WALKON learning plan**
- Screen-record the visible workflow: GPS wait, start, map/stats switch, pause/resume, screen lock, finish, save and activity detail.
- Compare live distance/pace with saved summary after the app has processed the activity.
- Compare Strava's route shape and timing against Apple Fitness for the same physical walk.
- Use the official Strava API only for the user's own authorised activity data, where available; do not assume API streams expose the raw private recording pipeline.

Public references:
- https://support.strava.com/en-us/articles/15402137-how-do-i-record-an-activity-in-strava
- https://support.strava.com/en-us/articles/15401874-how-do-i-fix-autopause-issues
- https://developers.strava.com/docs/reference/

### 22.2 Apple Fitness / Health — platform architecture we can actually use

**Documented**
- HealthKit is Apple's permission-controlled central health/fitness data store. It supports sharing and reading data from multiple apps and devices.
- Apple's developer guidance positions Core Motion for motion/step information, Core Location for outdoor route capture, and HealthKit for sharing workout and health records.
- Apple's WWDC25 workout session material describes the iPhone/iPad workout lifecycle using HKWorkoutSession and HKLiveWorkoutBuilder, live metric callbacks, lock-screen data access considerations and active workout recovery.
- A workout route is a separate HealthKit series associated with a saved workout.

**Important distinction**
Apple's public developer APIs describe what third-party apps can do. They do not reveal every private implementation detail of Apple's Fitness app. We must not claim to know its proprietary fusion, filtering or UI algorithms.

**WALKON learning plan**
- Inspect user-visible source attribution and daily step totals in Health.
- Compare a recorded outdoor walk's live metrics, saved workout, route and source details.
- Use HealthKit public APIs for WALKON's own implementation; don't scrape private Fitness databases or infer hidden ranking rules.

Public references:
- https://developer.apple.com/documentation/healthkit
- https://developer.apple.com/health-fitness/
- https://developer.apple.com/videos/play/wwdc2025/322/
- https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder

### 22.3 Google Fit and Health Connect — aggregation model

**Documented Google Fit behaviour**
- Google Fit's legacy platform merged step streams from multiple sources; its FAQ describes prioritising watch data over phone data and filtering activities such as cycling, driving or public transport from step totals.
- Reading a merged data type can therefore produce a different result from reading only one source.
- Google Fit APIs are deprecated in 2026; Google directs mobile-first Android step tracking toward Health Connect.

**Documented Health Connect behaviour**
- Use aggregate APIs for cumulative data such as steps rather than summing overlapping raw records.
- Health Connect manages aggregation and source priority, including the user's data-source priority choices.
- On-device step tracking uses Android's low-power TYPE_STEP_COUNTER sensor and writes step data in batches, typically no more frequently than once per minute.
- This is a platform aggregate, not a guaranteed second-by-second live pedometer feed.

**WALKON learning**
- Keep the future Android integration on Health Connect.
- Use aggregate APIs for daily totals; preserve source attribution where available.
- Never sum all raw device streams without deduplication.
- Treat delayed/batched daily totals separately from live workout session metrics.

Public references:
- https://developers.google.com/fit/faq
- https://developers.google.com/fit/rest
- https://developer.android.com/health-and-fitness/health-connect/read-data
- https://developer.android.com/health-and-fitness/health-connect/features/steps
- https://support.google.com/android/answer/16786157

### 22.4 Cross-app architecture pattern — what WALKON should learn

Across the public platform documentation, the consistent architecture pattern is separation of concerns:

1. **Sensor acquisition:** Core Motion / platform step sensor, Core Location / GNSS, optional wearable sensors.
2. **Session orchestration:** explicit workout state machine with pause/resume/finish and interruption handling.
3. **Data quality:** timestamps, accuracy metadata, deduplication, outlier rejection and explicit gaps.
4. **Metric computation:** live estimates separated from final reconciled workout summaries.
5. **Persistence:** durable local session journal and time-series route samples.
6. **Health platform integration:** read aggregate daily totals; save the app's own workout and route once.
7. **Presentation:** live metrics and route quality are visible but never treated as the source of truth.
8. **Sync/sharing:** later layer, only after local recording and HealthKit integration pass.

This separation is the architectural lesson. It is not evidence that Strava, Apple or Google use the exact same internal classes or algorithms.

### 22.5 Investigation evidence ledger

For every observation from the user's future recordings, record:
- app and version / operating system version
- activity type and permission state
- screen and action sequence
- displayed metric and timestamp
- GPS quality indicator, if shown
- whether value is live, paused, saved or post-processed
- comparison with WALKON / Apple Health / other app
- classification: documented, observed, inferred or unknown
- confidence and follow-up test

Do not infer the private mechanism from one screen. Example: a distance jump after saving may be post-processing, delayed samples or a different start/end boundary; the recording alone cannot establish which.

### 22.6 Architecture acceptance lesson

WALKON must not aim to make every number identical across apps. It must:
- expose which subsystem/source produced each metric;
- use platform aggregate totals for daily activity;
- use one selected session-step source;
- retain route timestamps and accuracy;
- make live values provisional when appropriate;
- calculate and persist a final summary deterministically;
- explain differences caused by source timing, aggregation, GPS quality and activity boundaries.

No copying of Strava/Apple/Google branding, screen layouts, private source, proprietary assets, undocumented endpoints, or proprietary algorithms.


## 23. iPhone hardware-first study — physical components, natural signals and Swift access

This is the guiding hardware-first principle for WALKON: understand the physical component, what it measures or emits, the operating-system service that interprets it, the public Swift API, its permission/background/battery limits, and only then decide whether to use it. The app must not try to recreate a capability that iOS already exposes as a reliable processed service.

### 23.1 Sensor and component inventory

| Physical component / subsystem | Natural function | Public iOS access path | Potential WALKON use | Constraints / decision |
|---|---|---|---|---|
| 3-axis accelerometer | Measures linear acceleration plus gravity along device axes | Core Motion: CMMotionManager, CMAccelerometerData, CMDeviceMotion | Understand movement patterns; research step/motion classification; detect phone movement context | Raw acceleration is not a ready-made step count. Prefer CMPedometer / HealthKit for steps; raw signal is research/validation only |
| Gyroscope | Measures angular rotation rate | Core Motion: CMGyroData, CMDeviceMotion.rotationRate | Device orientation/context, motion fusion, distinguish device rotation from translation | Rotation alone cannot measure walking distance |
| Magnetometer / compass | Measures magnetic field and supports heading/orientation | Core Motion calibrated magnetic field; Core Location heading | Compass arrow/map orientation; contextual heading | Magnetic interference near vehicles/buildings; course over ground from GPS is often better while moving |
| Motion coprocessor / pedometer pipeline | System processes motion data into pedestrian events/steps/distance where supported | Core Motion CMPedometer; HealthKit aggregates | Live session steps and retrospective step/distance values | System-derived values are preferred over a hand-written accelerometer peak counter; check availability and data latency |
| GNSS receiver (GPS and supported satellite systems) | Estimates position/time from satellite signals | Core Location CLLocation / CLLocationUpdate | Outdoor route coordinates, speed/course estimates, timestamps | Satellite visibility, multipath, urban canyon and battery affect quality; iOS may fuse other sources |
| Wi-Fi, cellular and Bluetooth radios | Provide radio observations and connectivity; can assist system location estimation | Core Location provides fused location; CoreBluetooth for BLE accessory communication | Location support through system; connect external sensors | Do not independently scan or fingerprint radios to reconstruct location; use authorized Core Location output |
| Barometer | Measures air pressure; pressure change can indicate relative altitude change | Core Motion CMAltimeter | Hill/climb context and relative elevation trend | Weather/pressure drift and device availability; calibrate and validate before elevation gain is shown |
| Camera system (wide/ultra-wide/telephoto/front, device-dependent) | Captures images/video and depth/visual data | AVFoundation capture APIs; Vision / ARKit for supported analysis | Later: walk photos, form/posture coaching only with explicit opt-in | Not needed for pedometer/GPS. Camera is privacy-sensitive and power-intensive; never capture in background for walking |
| Microphones | Convert sound pressure into audio signal | AVAudioSession, AVAudioEngine, AVAudioRecorder / AVFoundation | Voice coaching, spoken notes, trainer calls, optional audio cues input | Recording requires microphone permission and clear user action; no always-on listening |
| Speakers / receiver | Convert digital audio into sound | AVAudioSession, AVAudioPlayer / AVPlayer | Voice guidance, audio cues, calls, media playback | Audio route may switch to wired/Bluetooth/AirPlay devices; respect other apps' playback and interruptions |
| Taptic Engine / haptic actuator | Produces tactile feedback | Core Haptics; UIKit feedback generators | Start/pause/goal milestone confirmations without looking at screen | Haptic support varies; avoid excessive vibration and test with battery/thermal impact |
| Proximity sensor | Detects nearby objects, commonly to disable touch during calls | Limited UIKit proximity state via UIDevice where exposed; no general-purpose distance measurement stream | No core walking use | Not a general-purpose obstacle or distance sensor; do not rely on it for fitness measurement |
| Ambient light sensor | Measures surrounding light for automatic display brightness | No general public raw ambient-light sensor API for ordinary apps | No v1 use | Do not invent a sensor API or infer exact lux from screen brightness |
| Face ID / TrueDepth / LiDAR (model-dependent) | Secure face authentication, depth and scene sensing | LocalAuthentication; ARKit / AVFoundation depth APIs when supported | Future accessibility, form coaching or spatial features | Not required for walking recorder; biometric data must never be collected by WALKON |
| NFC controller | Short-range tag communication and secure system transactions | CoreNFC for supported tag-reading workflows | Optional future check-in at walking tracks/events or equipment | Requires capability/entitlement, user-started scan and supported tag formats; not a continuous sensor |
| Bluetooth LE | Wireless communication with accessories | CoreBluetooth | External heart-rate straps, cadence sensors, foot pods, compatible wearables | Pairing/connection lifecycle, battery and background limits; sensor provenance required |
| Battery and power state | Reports charge level and charging state | UIDevice battery monitoring | Warn before a long walk; diagnose battery drain | Battery percentage is not remaining recording time; do not promise an exact duration |
| Thermal sensors / thermal management | System monitors device temperature and performance pressure | ProcessInfo.thermalState | Reduce optional processing when thermal state is serious/critical | App cannot read raw internal temperature; respond to system thermal state, not guessed degrees |
| Barometric/GNSS/motion sensor fusion | System combines multiple sensor signals into useful estimates | Core Location and Core Motion processed outputs | Use fused location/heading and system pedestrian metrics | Apple does not expose all internal fusion weights or proprietary sensor-fusion internals |

Primary Apple references:
- Core Motion: https://developer.apple.com/documentation/coremotion/
- Device sensor overview: https://developer.apple.com/documentation/technologyoverviews/device-sensors
- Core Location: https://developer.apple.com/documentation/corelocation
- CMDeviceMotion: https://developer.apple.com/documentation/coremotion/cmdevicemotion
- CMAltimeter: https://developer.apple.com/documentation/coremotion/cmaltimeter
- AVFoundation capture: https://developer.apple.com/documentation/avfoundation/capture-setup
- AVAudioSession: https://developer.apple.com/documentation/avfaudio/avaudiosession
- Core Haptics: https://developer.apple.com/documentation/corehaptics
- Core Bluetooth: https://developer.apple.com/documentation/corebluetooth
- Core NFC: https://developer.apple.com/documentation/corenfc
- UIDevice battery: https://developer.apple.com/documentation/uikit/uidevice/batterylevel

### 23.2 What is hardware, what is a system service, and what is our code?

For every feature, keep three layers distinct:

1. **Physical hardware:** accelerometer, gyro, GNSS, barometer, microphone, speaker, camera, radio, haptic actuator, etc.
2. **iOS service/framework:** Core Motion, Core Location, HealthKit, AVFoundation, AVFAudio, CoreBluetooth, CoreHaptics, CoreNFC, UIKit, ProcessInfo.
3. **WALKON logic:** session orchestration, quality checks, metric presentation, storage, recovery and product experience.

Example — walking steps:
- Hardware senses acceleration.
- Apple's motion processing interprets pedestrian patterns.
- CMPedometer provides system-generated pedestrian metrics.
- HealthKit provides an aggregated daily step total from authorized sources.
- WALKON chooses the correct source for the screen and stores its provenance.
- WALKON must not invent a second step detector and add its count to the system total.

Example — walking distance:
- GNSS and other location sources contribute to system location estimates.
- Core Location provides timestamped locations, accuracy, speed and course.
- WALKON validates samples, segments gaps and calculates route distance.
- HealthKit route builder associates the route with the workout.
- WALKON must not confuse Core Location's reported speed with a guaranteed exact speed measurement.

### 23.3 iPhone hardware-first investigation order

1. **Motion subsystem:** accelerometer, gyroscope, magnetometer, sensor fusion, motion coprocessor, CMPedometer, activity classification.
2. **Location subsystem:** GNSS, Wi-Fi/cellular/Bluetooth assistance, Core Location fusion, horizontal/vertical accuracy, speed/course, background delivery.
3. **Altitude subsystem:** barometer, relative altitude, absolute altitude, pressure drift and elevation smoothing.
4. **Health subsystem:** HealthKit permissions, aggregate statistics, workout session, live builder, route series, source attribution.
5. **Power and thermal subsystem:** battery state, low-power behaviour, thermal state, sensor sampling rate and battery-cost tests.
6. **Audio subsystem:** speakers, microphones, AVAudioSession, audio focus/interruption, Bluetooth audio routing, spoken coaching.
7. **External sensor subsystem:** BLE heart-rate monitors, cadence/foot pods, Apple Watch and other wearable integration through supported public frameworks.
8. **Camera and vision subsystem:** camera capture, Vision/ARKit capabilities and privacy; later coaching features only.
9. **Haptics, NFC and proximity:** useful interaction/context components, not core fitness measurement sources.

### 23.4 Hardware use priority for WALKON

**Core v1**
- Motion coprocessor / CMPedometer where validated.
- HealthKit daily step aggregation and native workout lifecycle.
- GNSS + Core Location for route.
- Barometer only after elevation validation.
- Battery/thermal state for diagnostics and responsible workload management.

**Useful v1.1 / later**
- Bluetooth LE external heart-rate sensor and cadence accessories.
- AVAudioSession audio cues and spoken coaching.
- Core Haptics for non-visual status feedback.
- Apple Watch / supported wearable data through HealthKit.

**Optional future product features**
- Camera/Vision form coaching, user-captured walk photos.
- Microphone voice notes and trainer calls.
- NFC event/track check-ins.
- Accessibility and hands-free interactions.

**Not to build**
- A custom step counter from raw accelerometer data as the main source.
- A DIY GPS engine using raw radio scans.
- Background camera/microphone monitoring.
- Private API access to proximity/ambient light/raw sensor fusion.
- Any feature that consumes battery without a clear user benefit.

### 23.5 Hardware capability and API discovery at runtime

WALKON must check service availability at runtime rather than assume a sensor exists:
- Core Motion availability flags for accelerometer, gyro, magnetometer, device motion, pedometer and altimeter.
- Core Location authorization, accuracy authorization, services enabled and diagnostic update state.
- HealthKit availability and the actual returned metric statistics.
- CoreBluetooth manager state and discovered service/characteristic support for external sensors.
- AVFoundation capture device discovery and permission status only when the user invokes camera/microphone features.
- Core Haptics hardware support before attempting custom haptics.
- UIDevice battery monitoring and ProcessInfo thermal state where needed.

No feature may fail the entire app merely because an optional sensor is absent. Show capability as unsupported/unavailable and degrade gracefully.

### 23.6 Programming language mapping — Swift is the integration layer

Swift is not expected to speak directly to every chip. Apple's frameworks abstract the hardware and provide typed interfaces. WALKON's Swift code should:
- create framework managers/services;
- check hardware/service availability;
- request user authorization only when a feature is invoked;
- consume asynchronous callbacks/updates;
- normalize units and timestamps;
- attach provenance and quality;
- pass immutable samples to the domain layer;
- persist data transactionally;
- stop services when the activity ends.

Keep raw sensor processing off the main UI thread. Use actors or serial queues for sensor ownership and persistence. Use bounded sampling and batching to avoid excessive battery consumption. Record diagnostics (sampling rate, callback gaps, errors, thermal state) without collecting unnecessary personal data.

### 23.7 Hardware-first rule

Before adding a WALKON algorithm, answer:
1. Which physical component naturally produces the signal?
2. Which Apple framework exposes it?
3. Does iOS already provide a processed answer?
4. What accuracy, latency, permission, background and battery limits apply?
5. What additional calculation is genuinely missing?
6. How will we validate that calculation against real observations?

Only implement custom signal processing for the gap that remains after using Apple's native service. This is the central engineering principle for WALKON.


## 24. Reference-app logic study and WALKON capability orchestration

Research update: 2026-11-07. This section studies publicly documented behaviour and maps it to WALKON's own use of native iPhone capabilities. It does not claim access to private app source code, proprietary algorithms, or undocumented sensor-fusion logic.

### 24.1 Apple Fitness — native iPhone movement and Health ecosystem

**Publicly documented behaviour**
- iPhone motion sensors track steps, walking distance and flights climbed when the phone is carried.
- Fitness presents daily activity, trends, completed workouts and awards. With Apple Watch, additional Exercise and Stand measurements are available.
- Health stores data from iPhone, Apple Watch, compatible third-party apps and accessories. Users can inspect and reorder sources for a data type.
- Compatible third-party workouts can contribute to Fitness activity progress.

**What this tells WALKON**
- The iPhone already produces useful passive movement data without WALKON running a continuous foreground sensor loop. WALKON should read the HealthKit daily aggregate rather than try to duplicate the phone's passive step pipeline.
- HealthKit is the interoperability layer. WALKON should save its own explicitly recorded workout and route into HealthKit, then read the user's permitted daily aggregate for the dashboard.
- Source priority and aggregation belong to Apple's Health ecosystem. WALKON must not invent its own sum of overlapping iPhone, Watch and third-party step streams.
- Fitness's rings and trends are a presentation/motivation model; they are not a reason to recreate Apple's private calculation logic.

**Unknown / not to assume**
- Apple's public user guides do not reveal the exact proprietary step-detection classifier, sensor-fusion weights, calorie model or all Fitness app internals.
- The Health app's displayed total and an individual app's live session counter may differ because their sources, update cadence and aggregation windows differ.

Sources:
- https://support.apple.com/en-in/guide/iphone/iph4c34a8a95/27/ios
- https://support.apple.com/guide/iphone/iphbb8259c61/ios
- https://support.apple.com/en-in/108779
- https://developer.apple.com/documentation/healthkit

### 24.2 Strava — explicit outdoor recording and route workflow

**Publicly documented behaviour**
- User starts a recording, can pause/resume, then finishes and saves or discards the activity.
- Strava documents auto-pause behaviour using GPS movement and/or phone accelerometer for some activity modes; it also documents false pause/resume cases when GPS is obstructed.
- The recording flow exposes GPS-based activity data and a saved activity record. Public help content explains user-visible behaviour, not the complete proprietary route-quality algorithm.

**What this tells WALKON**
- A workout is an explicit user-owned session with a clear start, pause, resume, finish, save and discard lifecycle.
- Manual pause must always be available. WALKON v1 should default auto-pause off until slow-walking and GPS-obstruction cases have been validated.
- GPS quality and interruptions must be visible. A missing location interval must remain a gap, not become an invented straight-line route.
- Live metrics are provisional; final summary must be computed from the durable accepted samples and persisted session boundaries.
- Discard must be an intentional destructive action with confirmation; a saved workout must remain recoverable locally if HealthKit writing fails.

**Unknown / not to assume**
- Strava's private filtering thresholds, smoothing, server-side corrections, map matching and exact auto-pause classifier are not public.
- Matching Strava's distance exactly is not a correctness criterion. WALKON must be internally consistent, explainable and validated against repeated known routes.

Sources:
- https://support.strava.com/en-us/articles/15402137-how-do-i-record-an-activity-in-strava
- https://support.strava.com/en-us/articles/15401970-how-to-use-auto-pause-on-ios
- https://developers.strava.com/docs/reference/

### 24.3 Nike Run Club — coaching layered over a reliable recorder

**Publicly documented behaviour**
- NRC advertises GPS route, pace and distance tracking, workout history, guided audio runs, training plans and challenges.
- Nike states that NRC can sync with Apple Health and supported wearable devices, and can upload activities to Strava.
- Guided audio is an experience layered over a workout, not a substitute for the motion/location measurement system.

**What this tells WALKON**
- Keep measurement and coaching separate. A coach/audio module must consume the active workout state and approved metrics; it must not own or restart the GPS or pedometer.
- Audio cues should use AVAudioSession correctly, respect audio interruptions and Bluetooth route changes, and never compromise the recorder's state.
- Training plans and challenges should be consumers of completed, trusted workout records. They should not write competing step counts or alter route samples.
- Integrations should exchange records through supported HealthKit or documented partner APIs, not scrape another app's local data.

**Unknown / not to assume**
- Nike does not publicly disclose NRC's complete GPS smoothing, step detection, pace estimation or internal data model.
- App Store feature descriptions establish advertised capabilities, not the exact internal implementation.

Sources:
- https://apps.apple.com/in/app/nike-run-club-running-coach/id387771637
- https://about.nike.com/en/newsroom/releases/nike-run-club-app-new-features

### 24.4 WALKON's command-to-capability model

WALKON should act as a coordinator. Each native capability is a bounded service with a single responsibility, an explicit activation condition, a defined output contract and a defined stop condition. No service should silently start another service or write the same metric.

| User command / app state | Capability activated | Service output | WALKON responsibility |
|---|---|---|---|
| Open dashboard | HealthKit query/observer | Daily cumulative steps and permitted activity data | Display aggregate with source/refresh state; never add session steps |
| Start outdoor walk | HKWorkoutSession + builder, Core Location, session step provider if needed, SQLite journal | Workout lifecycle, live metrics, timestamped locations, session steps | Create one UUID, start services once, persist state and quality metadata |
| Pause | Workout session pause; stop route accumulation and pause session accounting | Explicit pause event | Persist pause timestamp; close route segment; do not bridge pause |
| Resume | Workout session resume; restart location collection and session accounting | New active segment | Persist resume event and create a new route segment |
| Lock screen | Active workout session and Live Activity | System-managed workout continuity/status surface | Keep UI as a projection of coordinator state; do not create a second recorder |
| Finish | Workout builder finalization, route finalization, SQLite transaction | Final workout metrics and route association | Save locally first; save HealthKit workout once; associate route; journal each stage |
| Connect heart-rate strap | CoreBluetooth | Validated BLE heart-rate characteristic samples | Bind accessory identity/provenance to workout; display unavailable when disconnected |
| Request spoken guidance | AVAudioSession / AVSpeechSynthesizer or approved audio player | Audio output | Read workout state; never own measurement lifecycle |
| Request haptic cue | Core Haptics / UIKit feedback | Tactile acknowledgement | Trigger only on explicit state/milestone events |
| Capture a walk photo | AVFoundation | User-initiated image | Attach photo to workout only after explicit capture; no background camera |
| Record voice note/call | AVAudioSession + AVFoundation | User-initiated audio | Require microphone permission and visible recording state |

**Orchestration invariants**
1. One WorkoutCoordinator owns the state machine. UI, Live Activity, audio and haptics observe its state; they do not own parallel state machines.
2. One RouteRecorder owns Core Location updates and route-point quality decisions.
3. One selected SessionStepProvider supplies session steps. Prefer the native workout builder's valid statistic only after confirming the required quantity is available on the target iPhone; otherwise use CMPedometer. Never add two providers.
4. HealthKit daily totals and WALKON session steps are different products with different time windows; never combine them.
5. Every callback is timestamped, tagged with source and associated with the current workout UUID before persistence.
6. A pause, finish, permission loss, service error or app recovery is an explicit event in the journal.
7. Optional capabilities (BLE, audio, camera, microphone, haptics) cannot block or corrupt the core walk recorder.
8. Every service checks availability and authorization when invoked, reports unavailable/denied/error distinctly, and stops when its job is complete.
9. No always-on camera, microphone, BLE scanning or high-frequency raw motion sampling for ordinary walking.
10. The app must remain useful if any optional hardware/service is absent.

### 24.5 Research conclusions and unresolved technical checks

**Supported conclusions**
- Use HealthKit as the daily health-data integration and workout record store.
- Use Core Motion's system pedometer rather than writing a DIY raw accelerometer step detector.
- Use Core Location for the outdoor route; preserve accuracy and timestamp metadata.
- Use the iOS 26+ iPhone workout-session workflow for session lifecycle, live builder data, lock-screen status and recovery.
- Keep coaching/audio/social functions downstream from the recorder.

**Must be verified before implementation is frozen**
- Inspect the exact iOS 26 SDK availability and Apple sample code for the iPhone workout session path; confirm the iPhone 12 Pro Max runtime behaviour.
- Determine which step and distance quantities the iPhone HKLiveWorkoutBuilder actually supplies for the selected walking workout configuration. Do not assume a metric is present merely because the builder supports live statistics.
- Confirm whether the target iPhone workout session and builder can keep the required services timely during screen lock, and document interruptions/recovery limits.
- Confirm the exact Core Location background configuration and modern API lifecycle for an explicitly active workout.
- Determine how HealthKit workout route association can be retried after a crash at each save stage; do not assume a finished route builder can be reopened.
- Establish battery impact from controlled device measurements before selecting sampling rates or adding extra sensor streams.

This section is a research map, not a claim that these behaviours have been tested on the target iPhone. The next research task is to resolve the listed unknowns from Apple's current SDK documentation and sample code, then freeze service contracts before any implementation change.


## 25. Cross-platform market study — customer evidence, product strengths and WALKON decisions

Research update: 2026-11-07. This section combines official product documentation, app-store listings and publicly visible customer-review samples. Ratings and review counts vary by country, device, version and date. Third-party review aggregators use different sampling methods; their percentages are directional signals, not population-wide defect rates. We do not infer private implementation details from user-facing behaviour.

### 25.1 Market shortlist by job-to-be-done

| App | Primary strength / customer job | Evidence-backed capabilities | WALKON lesson |
|---|---|---|---|
| Strava (iOS + Android) | Outdoor activity recording, performance, social motivation | GPS recording for many activity types, route/performance analysis, clubs/challenges/social feed | Best reference for activity lifecycle, route presentation and community; do not copy proprietary route algorithms |
| Nike Run Club (iOS + Android) | Beginner-to-advanced running coaching | Guided audio runs, training plans, pace/distance/elevation, challenges | Strong reference for coaching and audio layered on top of recording |
| Pacer (iOS + Android) | Everyday walking and habit formation | Automatic steps, distance, goals, challenges/groups, GPS walking routes, plans | Strong reference for walking-first onboarding and inclusive habit goals |
| StepsApp (iOS + Android) | Clear step counter and quick progress feedback | Passive steps, streaks, widgets, goals, leaderboards, Health integration; some GPS/analytics features paid | Strong reference for glanceable daily activity and widgets; examine feature boundaries carefully |
| Samsung Health (Android; limited cross-platform service availability) | Broad Samsung/Android health ecosystem | Phone accelerometer-based steps, Galaxy wearable integration, sleep, activity, nutrition, Together challenges and weekly reports | Best reference for Android OEM integration and a broader health dashboard; capabilities vary by device and region |
| Fitbit / Google Health (iOS + Android) | Everyday activity, sleep, health trends and wearable ecosystem | Step/activity tracking, wearable-derived sleep/heart metrics, daily summaries and device ecosystem | Reference for passive tracking and health insights; do not imply phone-only hardware can measure wearable-only vitals |
| Garmin Connect (iOS + Android) | Deep training/device data and athlete analytics | Garmin device sync, activity records, training/health metrics and ecosystem integrations | Reference for device interoperability and detailed history; pairing/sync reliability is a major product quality dependency |
| adidas Running (iOS + Android) | Broad activity tracking, plans and challenges | GPS for 90+ sports, pace/distance/time, voice coaching, goals and community challenges | Reference for broad activity taxonomy and guided plans; keep WALKON's first release narrower |
| Hevy (iOS + Android) | Strength-training logging and progression | Exercise library/videos, routines, sets/reps/weights, timers, graphs, HealthKit export on iOS | Reference for a future strength module; strength logs are structured user input, not phone motion-sensor measurements |
| Walkmeter (iOS + Android) | Detailed walking/hiking stats and local data control | Configurable stats, route/pace/splits, export formats and barometric elevation features (platform/device dependent) | Reference for advanced walking metrics and user-owned data/export; validate barometer claims per device |

### 25.2 Customer review signals — what people reward and what breaks trust

**Positive themes repeatedly visible**
- A simple, fast start to recording and a clear activity summary.
- Reliable saved history; users value being able to look back over months and years.
- Progress feedback, streaks, challenges, friends and encouragement.
- Useful coaching that makes the next workout easier to understand.
- A free/basic tier that is genuinely useful before asking for payment.
- Good integration with watches, health platforms and accessories.

**Negative themes repeatedly visible**
- Lost workouts, missing history or an activity that does not count toward a plan.
- GPS distance/route anomalies and auto-pause false positives.
- Broken Bluetooth pairing, wearable sync delays, duplicate or inconsistent health records.
- Crashes, regressions after updates and slow customer support.
- Important everyday controls hidden behind a paywall or subscription changes that frustrate existing users.
- Battery drain, confusing permissions and unclear background tracking behaviour.

**Review evidence examples**
- Strava's India App Store listing surfaced 4.8/5 from approximately 14k ratings. A separate 2026 third-party sample of 246 recent reviews identified subscription issues, GPS tracking, support, paywalls and bugs among the common negative themes. The sample is small relative to the total installed base and should be treated as qualitative evidence, not a global defect rate.
- Nike Run Club's India App Store listing surfaced 4.8/5 from approximately 33k ratings and advertises 300+ guided runs/workouts. A third-party review reading highlighted strong audio coaching and plans, but also complaints about GPS loss and watch/plan sync in some cases.
- Pacer's India App Store listing surfaced 4.9/5 from approximately 36k ratings; its Google Play listing surfaced 4.8/5 from approximately 968k reviews. Public review examples praise ease of use and long-term activity history, while some complain about paywall restrictions on changing goals.
- StepsApp's India App Store listing surfaced 4.8/5 from approximately 41k ratings. Its listing emphasises passive steps, streaks, challenges, widgets and Health integration, while GPS tracking and advanced analytics are described as Pro features.
- Samsung's official India product page says its phone step counter uses the built-in acceleration sensor and that distance is estimated using step count and stride length. It also documents Together challenges, sleep coaching, Energy Score and weekly reports, with some features requiring Galaxy wearables or supported devices.
- Garmin Connect's 2026 review analyses show that users value detailed metrics and device integration, but Bluetooth pairing, crashes and sync/data loss appear in negative feedback. This demonstrates that accessory/device sync is part of the product's core reliability, not a minor add-on.
- Hevy's India App Store listing surfaced 4.9/5 from approximately 8.7k ratings; reviews praise the clean workout logging, exercise demonstrations and progress graphs. Reviewers also request missing exercise notes and more history in the free tier.

Sources:
- Strava India App Store: https://apps.apple.com/in/app/strava-run-bike-walk/id426826309
- Strava recent-review analysis: https://glotier.com/apps/strava-run-bike-walk
- Nike Run Club India App Store: https://apps.apple.com/in/app/nike-run-club-running-coach/id387771637
- Nike review analysis: https://inapp.pro/en/rating/run-tracking/nike-run-club-running-coach
- Pacer India App Store: https://apps.apple.com/in/app/pacer-pedometer-step-counter/id600446812
- Pacer Google Play: https://play.google.com/store/apps/details?id=cc.pacer.androidapp
- StepsApp India App Store: https://apps.apple.com/in/app/stepsapp-pedometer/id1037595083
- Samsung Health India: https://www.samsung.com/in/apps/samsung-health/
- Garmin review analysis: https://unstar.app/blog/garmin-connect-not-syncing-watch-disconnecting-reviews-2026
- Hevy India App Store: https://apps.apple.com/in/app/hevy-gym-tracker-workout-log/id1458862350

### 25.3 Platform hardware and API strategy — do not pretend iOS and Android are identical

**iPhone**
- Daily steps and health summaries: HealthKit queries/observers, subject to user permissions.
- Passive/session motion: Core Motion CMPedometer; raw accelerometer/gyro only for justified advanced processing or diagnostics.
- Explicit workout lifecycle: iOS 26+ HKWorkoutSession + HKLiveWorkoutBuilder where available and verified.
- Outdoor route: Core Location; use documented background location and active-workout lifecycle.
- Workout and route persistence: HealthKit plus WALKON local durable journal.
- BLE accessories: CoreBluetooth; validate profiles, permissions and reconnect behaviour.
- Audio/haptics/camera: AVFAudio/AVFoundation/CoreHaptics only when the user invokes the relevant feature.

**Android**
- Daily totals and cross-app health exchange: Health Connect aggregate APIs; Android 14+ device step tracking is available through Health Connect when enabled and permitted.
- On-device step recording: Android's platform step sensor (TYPE_STEP_COUNTER / TYPE_STEP_DETECTOR) where supported; check SensorManager availability and ACTIVITY_RECOGNITION permission. Do not assume all OEMs expose identical behaviour or background guarantees.
- Google Play services alternative for battery-efficient on-device step/distance/calorie recording: Recording API, but choose one authoritative pipeline and avoid reading/writing the same measurements twice.
- Outdoor route: Fused Location Provider / platform location APIs with an explicitly active foreground service and visible notification when background location recording is required; obey Android background-location and foreground-service rules for the target OS.
- Wear OS: Health Services for exercise and sensor capabilities on supported watches; phone and watch data must be deduplicated/attributed.
- BLE accessories: Android Bluetooth APIs; handle runtime permissions, reconnects and vendor differences.
- Audio/haptics/camera: Android platform media, audio, vibration and CameraX APIs with explicit user-facing permission and lifecycle.

Official Android sources:
- https://developer.android.com/health-and-fitness/health-connect
- https://support.google.com/android/answer/16786157
- https://developer.android.com/health-and-fitness/recording-api
- https://developer.android.com/develop/sensors-and-location/sensors/sensors_overview
- https://developer.android.com/develop/sensors-and-location/location/permissions
- https://developer.android.com/health-and-fitness/health-services

### 25.4 Product blueprint — what WALKON should take, improve and avoid

**Adopt for WALKON**
1. Strava's explicit record/pause/resume/save lifecycle and activity history.
2. Nike Run Club's audio-guided coaching and progressive plans, but keep them separate from the recorder.
3. Pacer's walking-first goals, streaks, challenges and approachable onboarding.
4. StepsApp's quick daily step glance, widgets, streaks and simple charts.
5. Samsung Health/Fitbit's daily and weekly summaries, but only show metrics supported by the actual connected hardware/source.
6. Garmin's device/source history and accessory integration discipline.
7. Hevy's structured exercise logging, history, exercise demonstrations and progressive strength tracking when strength training is introduced.
8. Walkmeter's detailed stats and data export for users who want control of their records.

**Improve beyond common customer complaints**
- Local-first activity persistence before network sync; an internet outage must not lose a walk.
- A recovery journal with idempotent save stages; never silently lose or duplicate a completed activity.
- Clear source labels and timestamps for every metric; show unavailable/permission denied/stale separately from zero.
- Visible GPS quality and route gaps; no fake straight-line bridges or unexplained distance jumps.
- Manual pause always available; auto-pause opt-in and disabled until walking-specific validation passes.
- Sync diagnostics for Health Connect/HealthKit/BLE/wearables, including last successful sync and actionable error state.
- Permission requests just in time, with a useful explanation and graceful degraded mode.
- Battery-aware sampling and a visible recording state; never claim uninterrupted tracking after force-quit, power loss or permission revocation.
- Useful free core: daily steps, reliable recording, history and basic progress should not be held hostage to subscription.
- Simple navigation and low cognitive load; advanced analytics remain optional.

**Do not copy**
- Another app's proprietary algorithms, private APIs, design assets, brand identity or undocumented endpoints.
- A social feed before core activity data is dependable.
- Continuous raw sensor polling when a platform service already supplies the needed measurement.
- A single cross-platform sensor implementation; use native platform adapters behind shared domain contracts.
- Health or performance scores that imply medical certainty or cannot be explained from available data.

### 25.5 Proposed WALKON cross-platform architecture boundary

Keep the product/domain layer shared in concept, not necessarily the low-level sensor code:

- WorkoutDomain: activity identity, state machine, pause/resume, metrics, goals and provenance.
- PlatformHealthAdapter: HealthKit on iOS; Health Connect on Android.
- PlatformMotionAdapter: Core Motion on iOS; SensorManager / supported Recording API on Android.
- PlatformWorkoutAdapter: HKWorkoutSession on iOS 26+; platform-appropriate foreground workout/service lifecycle on Android.
- PlatformLocationAdapter: Core Location on iOS; Fused Location Provider/platform location on Android.
- PlatformAccessoryAdapter: CoreBluetooth on iOS; Android Bluetooth APIs on Android.
- LocalActivityRepository: transactional database and recovery journal on both platforms.
- CoachingExperience: plans, audio, cues and progression consuming trusted workout records.
- CommunityExperience: groups, challenges and sharing consuming validated records only.

The shared contract must not erase platform differences. Each adapter declares capabilities, permissions, availability, update cadence, background constraints, source and quality. The domain layer consumes normalized events and measurements, never direct hardware callbacks.

### 25.6 Scope decision — sequence, not feature accumulation

**Phase 0 — research and architecture freeze**
- Finish hardware/API availability research on both platforms.
- Resolve open questions from Sections 23 and 24.
- Define native adapters, domain contracts, error states, privacy and acceptance tests.
- No new feature implementation while architecture is unsettled.

**Phase 1 — dependable walking engine**
- Passive daily steps from platform health aggregate.
- Explicit walking session with one step source.
- GPS route, timestamps, quality and gap handling.
- Pause/resume/finish/discard.
- Local durable history and recovery.
- Health platform workout/route save.
- Battery/background and device compatibility verification.

**Phase 2 — walking habit and coaching**
- Goals, streaks, weekly progress and adaptive walking plans.
- Optional audio coaching and haptics.
- Widgets and lock-screen/live status where supported.

**Phase 3 — broader fitness**
- Strength logging inspired by Hevy.
- Wearable/BLE integrations and richer training insights.
- Community groups and challenges.

**Phase 4 — optional ecosystem**
- User photos, voice notes, trainer sessions, integrations and monetisation only after privacy, reliability and customer value are proven.

### 25.7 Acceptance principles from market evidence

WALKON is not market-ready because it has many features or resembles a highly rated app. It is ready only when:
- a walk can be started, paused, resumed, finished, recovered and saved without losing or duplicating data;
- daily steps and session steps remain separate and traceable;
- route and distance behaviour is explainable across repeatable tests;
- background operation and battery impact are measured on representative iPhone and Android devices;
- permissions and missing hardware degrade gracefully;
- wearable and health-platform sync is observable and recoverable;
- core functionality remains useful without a paid subscription or network connection.

Research status: market shortlist and product lessons documented. Not a final feature specification and not evidence that WALKON has been implemented or field-tested.


## 26. Deeper product and platform findings — second research pass

Research update: 2026-11-07. This pass focuses on verified workflows, data-source rules, hands-free use, export/privacy, subscription boundaries and failure patterns. It extends the app shortlist rather than treating store ratings as technical proof.

### 26.1 Pacer — phone-first walking and source selection

**Verified from Pacer's own documentation**
- Pacer's default step-counting method uses the phone's built-in motion sensors.
- It can also integrate with Apple Health on iOS, and with Samsung Health / Google Fit integrations on Android as documented in its support article.
- Its product combines steps, distance, active time, goals, plans, outdoor GPS routes and group challenges.

**WALKON implications**
- Phone-only tracking must be a complete first-class experience; a watch must not be required.
- An integration must explicitly define whether WALKON reads a health hub, writes to it, or uses the phone sensor directly. A single metric must not be counted through two paths.
- Give the user a visible source explanation and a way to diagnose why a wearable or health hub is not contributing.
- Walking plans and groups consume the validated daily/session records; they do not create new sensor data.

Source:
- https://support.mypacer.com/hc/en-us/articles/41658925082253-Which-wearables-3rd-party-app-integration-does-Pacer-support
- https://apps.apple.com/in/app/pacer-pedometer-step-counter/id600446812

### 26.2 StepsApp — simple passive tracking, widgets and explicit free/paid boundary

**Verified from official listing and support**
- Automatic step tracking, daily goals, streaks, challenges, leaderboards, Apple Health integration, Apple Watch support, trends, awards, Home Screen/Lock Screen widgets and data export are advertised.
- Its support page says basic step tracking, step/distance analysis and calorie counting are free; GPS workouts/map tracking, insights/trends, some goals and ad-free use are in Pro.
- Google Play listing advertises Google Fit integration, notifications, charts and monthly/yearly views.

**WALKON implications**
- The daily dashboard must be useful in seconds: today's steps, goal progress, weekly pattern and last update.
- Widgets/lock-screen surfaces are valuable because passive tracking is often checked briefly.
- Export and user access to history should be a trust feature, not a premium hostage.
- Do not put the fundamental ability to record and retain a walk behind a subscription. Premium can add advanced coaching, analytics and customisation after the core remains dependable.

Sources:
- https://apps.apple.com/in/app/stepsapp-pedometer/id1037595083
- https://steps.app/support/pedometer/ios/purchase/which-extra-features-are-included-in-the-pro-version
- https://play.google.com/store/apps/details?id=com.stepsappgmbh.stepsapp

### 26.3 Walkmeter — hands-free, data-rich and privacy-oriented design

**Verified from developer documentation**
- Records walking, hiking, running, cycling and other activity types; offers over 250 statistics, maps, graphs, splits, intervals and zones.
- Supports Bluetooth heart-rate sensors and Apple Watch heart-rate data; uses the built-in accelerometer for step cadence.
- On iPhone, it can use barometric altimeter data for ascent/descent.
- Provides Siri voice commands for start, stop, lap and spoken statistics.
- Supports spoken announcements, live tracking, route navigation and export/import formats including GPX, TCX, FIT, KML and CSV.
- Its developer says workouts are stored on-device by default until the user chooses to share.

**WALKON implications**
- Hands-free interaction is a real fitness use case: voice commands and spoken progress can reduce the need to look at a phone while walking.
- Advanced statistics should be configurable and derived from a traceable set of base measurements.
- Export should be planned into the data model from the beginning; use documented interchange formats where practical.
- Barometric elevation is a candidate signal, not a universal guarantee. Check sensor availability and calibrate/filter before displaying ascent.
- Privacy-first local recording is a competitive advantage. Cloud/community sharing should be opt-in and separate from recording.

Sources:
- https://walkmeter.com/features/
- https://walkmeter.com/documentation/
- https://walkmeter.org/features/

### 26.4 Apple Health — source priority and aggregation are user-controlled

**Verified from Apple Support**
- iPhone automatically counts steps and walking/running distance; Apple Watch contributes additional activity and health data.
- Health organises similar measurements from different sources.
- The user can inspect and reorder sources for a data type; the top source has priority when multiple sources contribute.
- Newly added sources appear above existing ones by default.

**WALKON implications**
- HealthKit daily steps are not equivalent to adding all raw step samples from every device. Use HealthKit statistics for the dashboard.
- Do not build a competing hidden source-priority system.
- If showing source details, explain what HealthKit exposes and respect read-permission privacy.
- WALKON's own recorded workout remains a separately identified activity; don't inject a second copy of its steps into the daily total.

Source:
- https://support.apple.com/en-in/108779

### 26.5 Google Fit retirement — avoid a new integration dependency

**Verified from Google**
- Google Fit APIs are supported only until the end of 2026.
- Google's migration guide recommends Health Connect for mobile-first step-tracking applications and the Google Health API for certain cloud/web companion integrations.
- The migration guide says some old Fit APIs, including goals and BLE-specific services, have no direct replacement and should use Android platform APIs where appropriate.

**WALKON implications**
- Do not build a new Android architecture on Google Fit APIs.
- Health Connect is the default Android health-data interchange/aggregation layer for mobile.
- Use Android Sensors / Recording API / location and Bluetooth platform APIs for live on-device functionality according to the specific job.
- Keep the adapter boundary so a future Google health service integration does not require rewriting workout-domain logic.

Sources:
- https://developers.google.com/fit/rest
- https://developer.android.com/health-and-fitness/health-connect/migration/fit

### 26.6 Customer failure evidence — synchronisation is a core feature

**Nike Run Club public App Store review sample**
- Reviews include reports of watch/phone sync failures, lost workouts, repeated log-outs, GPS distance loss and completed activities not registering in plans.
- Other users praise guided runs and training plans; the app's value proposition is strong but only when recorded activities flow correctly into the plan/history.

**Garmin Connect third-party review analysis**
- A 2026 review study sampled 3,000 US Google Play reviews and identified 131 substantial complaints about watch-to-phone transfer across multiple app builds.
- This is a specific review sample, not a population-wide failure rate, but it highlights the structural importance of reliable Bluetooth pairing and data transfer.

**WALKON implications**
- Every external source needs connection state, last successful sync, last received sample time, source identity and a retry/recovery state.
- A watch disconnect must not erase the phone's local workout.
- A completed workout must not be marked fully synced until the receiving platform confirms the write.
- Sync operations must be idempotent and use stable IDs to avoid duplicates after retry.
- Plans/challenges should reconcile from the durable workout record rather than depend on a fragile one-time callback.

Sources:
- https://apps.apple.com/us/app/nike-run-club-running-coach/id387771637?see-all=reviews
- https://inapp.pro/en/rating/run-tracking/nike-run-club-running-coach
- https://unstar.app/blog/garmin-connect-not-syncing-watch-disconnecting-reviews-2026

### 26.7 Product architecture consequences — requirements now made explicit

The following requirements are promoted from market observations into WALKON design constraints:

1. **Phone-first operation:** daily steps and a recorded walk must work without a wearable.
2. **Single metric authority:** one selected source for each displayed metric/time window; no silent addition of overlapping sources.
3. **Source diagnostics:** record source, sample timestamps, last update, permission, availability and sync status.
4. **Local-first recording:** durable local activity journal before optional cloud sync.
5. **Recoverable sync:** stable workout IDs, retryable writes and duplicate protection.
6. **Hands-free path:** voice/audio controls are a separate consumer of workout state, not another recorder.
7. **Configurable detail:** simple default dashboard; advanced stats, splits, intervals and zones available without cluttering the primary flow.
8. **Privacy/export:** local storage, explicit sharing, and exportable user history.
9. **Free core:** passive daily steps, recording, completed workout history and basic progress remain usable without subscription.
10. **Native platform adapters:** HealthKit/Core Motion/Core Location on iOS; Health Connect/SensorManager/Android location APIs on Android. Do not use Google Fit as the new Android foundation.

### 26.8 Evidence quality and remaining work

- Official Apple, Google, Samsung and app-developer support pages are used for platform behaviour and advertised capabilities.
- App Store / Google Play listings are used for currently advertised features, compatibility and surfaced rating snapshots.
- Customer reviews and third-party review studies are qualitative evidence of pain points. They do not establish the internal cause of a GPS or sync failure.
- No competitor's private algorithm, source code, undocumented endpoint or hidden sensor-fusion pipeline has been inspected.
- Remaining research: obtain a broader, reproducible cross-platform review sample for Strava, Pacer, StepsApp, Samsung Health, Fitbit/Google Health, adidas Running and Hevy; compare recent release regressions and accessibility/offline/privacy details; complete Android device/OEM variation research; verify all proposed iOS/Android API capabilities against current SDK documentation.

Research status: deeper second pass documented. This is a durable design reference, not a claim of exhaustive market coverage or successful WALKON field implementation.


## 27. Android sensor pipeline and cross-platform app behaviour — detailed research

Research update: 2026-11-07. This section records Android's documented motion sensor semantics and the lessons from Fitbit/Google Health, Samsung Health, adidas Running and Hevy. It defines platform-specific behaviour WALKON must respect.

### 27.1 Android step sensors — exact semantics

Android exposes two distinct step sensor types through SensorManager:
- TYPE_STEP_COUNTER: cumulative number of steps since the last reboot while the sensor has been activated. It is a hardware-implemented, low-power sensor where supported. It reports an aggregate count, not one callback per footfall.
- TYPE_STEP_DETECTOR: emits an event for each detected step; the event value is 1.0. It is intended for individual step events / dead reckoning, not as the preferred aggregate counter.
- Android documentation says the counter may have latency up to 10 seconds, while the detector's expected latency is below 2 seconds.
- Both require ACTIVITY_RECOGNITION permission on Android 10 / API 29 and later.
- The step counter only counts while an app has registered/activated the sensor. Android recommends keeping it registered for continuous tracking and retrieving values in a battery-conscious way.

WALKON implementation rules:
1. Check getDefaultSensor(TYPE_STEP_COUNTER) at runtime. If absent, report unsupported; do not silently substitute a raw accelerometer peak counter.
2. Request ACTIVITY_RECOGNITION just in time and explain the purpose.
3. Treat counter values as a monotonic device counter within one boot epoch, not as today's count. Persist the last observed counter and timestamp; detect reboot/reset (counter drops) and begin a new epoch.
4. Derive an interval delta only when the same boot epoch is established and values are monotonic. Never subtract across reboot, missing baseline or corrupted timestamps.
5. The step detector can support a low-latency session display if required, but it is a separate stream; never add its event count to the step-counter delta.
6. Health Connect's on-device step data is aggregated/batched, generally no more frequently than once per minute. It is appropriate for daily totals and history, not a guaranteed live session display.
7. The Android session adapter must document latency and distinguish provisional live values from final reconciled interval values.

Sources:
- https://developer.android.com/reference/android/hardware/Sensor
- https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion
- https://developer.android.com/health-and-fitness/health-connect/features/steps

### 27.2 Android daily step architecture — Health Connect vs direct sensor

Health Connect:
- Supplies an aggregate health-data integration and supports on-device step tracking.
- On-device step tracking uses TYPE_STEP_COUNTER and writes records in batches; its activation is tied to an app having Health Connect READ_STEPS permission.
- Its source attribution changed in June 2026 to a device-specific source package name (SPN), so source identifiers must not be hard-coded as a fixed Android package.
- For daily totals, prefer Health Connect aggregate reads and preserve returned source metadata.

Direct SensorManager:
- Can support a live WALKON session step stream with a device counter baseline, subject to permission, sensor availability and registration lifecycle.
- Must not be added to Health Connect's daily aggregate as a second copy.
- If WALKON writes its own exercise records to Health Connect, use stable record identity / deduplication strategy and do not write overlapping step samples unless there is a deliberate, tested reason.

WALKON source-of-truth policy:
- Daily dashboard: Health Connect aggregate, if available and authorized.
- Live recorded session: one selected session provider, such as direct TYPE_STEP_COUNTER delta or TYPE_STEP_DETECTOR event stream where device tests justify it.
- Final workout: persist the session's own step result and provenance; do not sum it with Health Connect's daily total.
- A delayed Health Connect update must not freeze the live session display or cause the same steps to be counted twice.

### 27.3 Samsung Health — phone and wearable aggregation caveats

Samsung's official support documentation says:
- The phone's built-in acceleration sensor is used for step tracking.
- Distance is estimated using step count and stride length; stride length is estimated from profile/height and cadence.
- Phone position and movement context can affect estimates.
- Connected phone and Galaxy Watch data can be shown together; users can choose an all-steps view, and device-specific views may not always be available.
- Supported Galaxy wearables expose additional metrics depending on model and sensor set.

WALKON implications:
- Distance derived from steps is an estimate, not a GPS route distance. Keep estimated_stride_distance distinct from gps_route_distance.
- A watch and phone can both detect the same walk. Use Health Connect/HealthKit aggregation and source metadata rather than summing both raw streams.
- Never promise heart rate, sleep, SpO2 or other wearable-only measurements from a phone that lacks the required sensor.
- Device capability discovery must be per device/model and per connected accessory, not a single Android-supports-this flag.

Sources:
- https://www.samsung.com/in/support/mobile-devices/view-your-step-count-in-samsung-health/
- https://www.samsung.com/in/apps/samsung-health/

### 27.4 Fitbit / Google Health — phone GPS, wearable GPS and activity recognition

Google's current help documentation describes several distinct GPS paths:
- A wearable with built-in GPS can record its own route.
- A wearable without GPS can use the connected phone's GPS through a connected-GPS path.
- The Google Health app requires appropriate background/location permissions for phone GPS capture and background connectivity.
- Some Fitbit/Pixel Watch devices automatically detect and save activities; users can review, confirm, edit or delete detected activities. Detection support differs by model.

WALKON implications:
- Distinguish phone-GPS recording from watch-GPS recording; store the actual location source on each activity.
- If the watch has no GPS, the phone is the route provider; if the phone is left behind, route continuity cannot be assumed.
- Auto-detected activity is not equivalent to an explicitly started WALKON workout. Keep passive recognition as a separate optional feature after the core recorder.
- User confirmation/edit/delete is important when activity recognition guesses the wrong activity.
- Do not claim every Fitbit feature is available on every wearable or region.

Sources:
- https://support.google.com/googlehealth/answer/14225688
- https://support.google.com/googlehealth/answer/14237206
- https://support.google.com/googlehealth/answer/14236510

### 27.5 adidas Running — guided plans, voice coach and challenge loop

The official adidas Running listing describes GPS tracking across walking, running, cycling, swimming and 90+ activities; live pace/distance/time/calorie metrics; wearable sync; personalised training plans; voice coaching; global challenges and rewards.

WALKON implications:
- Activity taxonomy and coaching plans should be metadata-driven, not hard-coded into the GPS recorder.
- Voice coaching consumes the current workout metrics and plan milestones; it must not create another location or step pipeline.
- Challenges and rewards should consume completed validated workouts with clear eligibility rules, not raw live callbacks.
- Reward systems must be transparent and not encourage unsafe exercise or fabricated activity.
- Broad sports support is a later product layer; first make walking reliable.

Sources:
- https://apps.apple.com/in/app/adidas-running-gps-tracker/id336599882
- https://www.adidas.com/us/running-app

### 27.6 Hevy — structured strength-training domain, not a sensor-counting shortcut

Hevy's current App Store and Google Play listings describe:
- Routines and exercise library with instructional videos.
- Sets, reps, weights, warm-up/drop/failure/superset classifications.
- Rest timers, one-rep-max and volume/progression graphs.
- Friend activity and shared routines.
- Wear OS workout tracking with live sync to the phone and reconnect save behaviour.
- HealthKit export on iOS.
- User export of workout and measurement history.

WALKON implications:
- Strength sessions need their own domain entities: exercise, set, rep, load, rest, routine, and personal record.
- Do not attempt to infer every strength repetition or load from the phone accelerometer; user input and compatible equipment/wearables are the authoritative sources unless a validated sensor workflow exists.
- A watch-to-phone live session must survive temporary disconnect and reconcile after reconnect without duplicate sets/workouts.
- Exercise video/coaching is a separate media capability; the workout log remains durable and usable offline.
- Data export should be supported from the start of the strength module.

Sources:
- https://apps.apple.com/in/app/hevy-gym-tracker-workout-log/id1458862350
- https://play.google.com/store/apps/details?id=com.hevy
- https://help.hevyapp.com/hc/en-us/articles/43708290987415-Exporting-Your-Data-from-Hevy

### 27.7 Revised cross-platform metric contract

Every metric event consumed by the domain layer must carry:
- metric_type (steps, distance, pace, elevation, heart_rate, active_energy, cadence, etc.)
- value and canonical unit
- sample_start / sample_end or event timestamp
- source_platform and source_identifier where available
- source_device / accessory identifier where available
- measurement_kind (platform_aggregate, sensor_counter, sensor_event, GPS-derived, wearable sample, user-entered)
- activity_id and segment ID when session-scoped
- quality_state and quality metadata
- permission_state / availability state
- received_at and last-successful-sync time
- algorithm_version for WALKON-derived metrics

Do not normalize away important distinctions. In particular:
- GPS route distance is not step-derived stride distance.
- A counter delta is not the same as a per-step event stream.
- Health Connect/HealthKit daily aggregate is not a live workout metric.
- Phone GPS is not watch GPS.
- User-entered strength reps are not motion-sensor rep detections.

### 27.8 Updated Android implementation gates (for later build)

Before Android code is approved:
1. Build a device capability matrix across at least two OEM families and representative Android API levels.
2. Verify TYPE_STEP_COUNTER and TYPE_STEP_DETECTOR presence, permission, latency, reboot reset and background registration.
3. Confirm Health Connect read/write permissions, aggregate behaviour, on-device step activation and source attribution.
4. Verify location foreground-service requirements and OEM battery restrictions on screen lock.
5. Verify phone-GPS vs wearable-GPS ownership and reconnect recovery.
6. Verify duplicate prevention when both phone and watch provide steps/workouts.
7. Measure battery impact under passive steps, active GPS recording and optional BLE sensor connection.
8. Verify local save, export and retry after offline periods.

Research status: detailed Android step semantics and four additional app/product workflows documented. No Android implementation has been written or device-tested.


## 28. Location and GPS engine — iOS, Android and smartphone GNSS limitations

Research update: 2026-11-07. This section defines what phone location systems actually provide, why routes drift, and how WALKON should consume native location services. It deliberately separates public platform behaviour from research algorithms and competitor internals.

### 28.1 The phone does not expose a raw, perfect GPS track

A smartphone location fix is a system estimate. Satellite GNSS is one input, but the OS can also use Wi-Fi, cellular, Bluetooth and device sensors to estimate position, altitude, heading and movement. Apple's Core Location documentation explicitly describes this multi-source approach. Android's Fused Location Provider likewise combines available location signals and lets the app request a quality/power trade-off.

Consequences:
- `CLLocation` / Android `Location` is a platform estimate, not a raw satellite measurement.
- An app generally cannot command the phone to use only one physical positioning chip and assume that produces the best route.
- Location accuracy is a reported estimate, not a guarantee that the true point lies inside a perfect circle.
- GPS may take time to improve after start; buildings, roofs, trees, terrain and reflected/non-line-of-sight signals can degrade it.
- WALKON should preserve native metadata and avoid claiming metre-perfect accuracy.

Sources:
- https://developer.apple.com/documentation/corelocation
- https://developers.google.com/location-context/fused-location-provider
- https://support.apple.com/en-us/102515

### 28.2 iOS location acquisition

**Public system interface**
- Core Location provides location, altitude, course/heading and diagnostics through `CLLocationManager`, `CLLocationUpdate` and related APIs.
- The framework can combine GPS, Wi-Fi, Bluetooth, magnetometer, barometer and cellular hardware.
- `CLLocation` supplies coordinate, timestamp, horizontal accuracy, altitude, vertical accuracy, speed and course; speed/course validity must be checked rather than assumed.
- Users can grant precise or reduced accuracy and can change authorization while the app is running.

**Background operation**
- iOS suspends most apps shortly after they move to the background.
- In a suspended state, an app does not execute and does not receive live location callbacks; the system may queue updates and deliver them later.
- For an explicitly active fitness workout, Apple documents the Location Updates background mode and modern `CLBackgroundActivitySession` / `CLServiceSession` approach. The app must communicate the active location use and recreate required service sessions appropriately after relaunch.
- This is not a promise of uninterrupted execution after force-quit, device shutdown, permission revocation or system resource failure.

**WALKON iOS design**
- Location begins only after the user explicitly starts an outdoor recording.
- Request When In Use access for the active workout flow; request Always only if a separately justified feature truly requires it.
- Use one chosen Core Location pipeline per app version. Do not run parallel legacy and modern streams and merge their duplicate locations.
- Persist timestamp, coordinate, horizontal accuracy, altitude, vertical accuracy, speed, course, source information where exposed, and receipt time.
- Surface reduced accuracy, denied permission, location services off, no fix and temporarily stale data as distinct states.
- Treat the background recording status and Live Activity as a view of the same workout coordinator, not separate recording engines.

Sources:
- https://developer.apple.com/documentation/corelocation
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background

### 28.3 Android location acquisition

**Public system interface**
- Google Play services Fused Location Provider combines GPS and Wi-Fi and other available signals behind a single API.
- `FusedLocationProviderClient` supports one-shot current location and repeated updates.
- Fine location provides more precise data; coarse location is obfuscated/throttled. Android 12+ allows users to force approximate location even when an app requests fine location.
- A request can return older cached locations; timestamp validation is required.

**Background operation**
- Ordinary coarse/fine location permission does not by itself grant unrestricted background delivery.
- A user-initiated active workout should use the appropriate location foreground service with a visible notification and correct foreground-service type/permissions for the target Android version.
- `ACCESS_BACKGROUND_LOCATION` has separate restrictions and should not be requested by default if the active-workout foreground-service pattern is sufficient.
- Google Play policy expects background location to be core, user-beneficial, clearly disclosed and policy-compliant.
- OEM battery managers can add device-specific restrictions; verify Samsung, Pixel and at least one additional OEM family.

**WALKON Android design**
- Start location only as part of a user-started outdoor workout.
- Prefer the Fused Location Provider for the standard route path; use platform GNSS APIs only if a later proven requirement justifies the complexity.
- Use a foreground location service for a visible active workout, following current Android API-level requirements.
- Check permission precision, location settings, provider availability and timestamps at runtime.
- Keep one authoritative location stream; do not combine duplicate Fused Location and raw GNSS streams into distance.

Sources:
- https://developers.google.com/android/reference/com/google/android/gms/location/FusedLocationProviderClient
- https://developers.google.com/location-context/fused-location-provider
- https://developer.android.com/develop/sensors-and-location/location/permissions
- https://support.google.com/googleplay/android-developer/answer/9799150

### 28.4 Why smartphone routes drift — GNSS and urban canyons

GNSS errors are not just random noise. Buildings and other obstacles can block direct satellite signals or reflect them, creating non-line-of-sight (NLOS) and multipath errors. A 2023 smartphone study of urban GNSS found NLOS was the dominant source of its observed code outliers in the studied environment. Research on pedestrian positioning shows that GNSS combined with inertial measurements can improve continuity in challenging environments, but the results depend on the specific algorithm, hardware, calibration and test environment.

WALKON implications:
- A single bad fix can jump a route across a road or around a block.
- Averaging every point blindly can smooth away real corners and still retain systematic multipath error.
- A low reported accuracy value is not proof that the location is correct; use temporal continuity, speed/course plausibility and signal diagnostics where available.
- Do not snap routes to roads/sidewalks in v1 unless the map-matching source, licence, confidence and failure behaviour are explicitly designed.
- Preserve raw accepted observations and quality metadata so a future algorithm can be compared without losing evidence.

Research sources:
- https://www.sciencedirect.com/science/article/pii/S0263224123013301
- https://doi.org/10.1109/ACCESS.2021.3055485
- https://doi.org/10.1109/ACCESS.2021.3052733

### 28.5 WALKON route point and quality contract

Every received location observation should be normalized into a record with:
- workout UUID and route-segment UUID;
- source platform and provider (Core Location / Fused Location Provider / accessory if ever supported);
- latitude/longitude in WGS84;
- monotonic event timestamp and wall-clock timestamp where available;
- horizontal accuracy in metres;
- altitude and vertical accuracy;
- speed and speed accuracy where supported;
- course/heading and course accuracy where supported;
- source/mock indicator where exposed;
- callback receipt timestamp;
- authorization precision and service state;
- acceptance/rejection decision and reason;
- algorithm version.

Do not discard a sample without recording a diagnostic reason in a bounded diagnostic stream. Avoid retaining excessive raw diagnostics beyond the user's workout history and privacy policy.

### 28.6 Distance, speed, pace and route segmentation

**Distance**
- Calculate route distance only from sequential accepted points within the same active segment.
- Reject invalid coordinates, negative accuracy, stale/out-of-order timestamps and implausible displacement/speed spikes.
- Use both the platform-reported accuracy and temporal plausibility; never rely on one hard-coded threshold as a universal truth.
- Preserve a GPS gap when no reliable points arrive. Never draw a straight line through a long gap and count it as travelled distance.
- Store raw accepted coordinates separately from derived/smoothed display geometry.
- Use double precision/metres internally; round only for presentation.

**Speed and pace**
- Treat system speed as a sensor estimate with its own accuracy and validity.
- Do not derive pace from one noisy point interval.
- Use a rolling time/distance window with a minimum valid movement interval; display unavailable or unstable when quality is poor.
- Keep elapsed time, paused time and moving time separate.
- Define average pace from validated distance divided by the appropriate duration; name the duration (elapsed vs moving).

**Segments**
- Manual pause closes the active segment.
- Resume starts a new segment.
- Long GPS gaps remain explicit gap events within a segment or split the geometry, depending on the final route model; they are never bridged as real travel.
- A finish event closes all open segments exactly once.

### 28.7 GPS acquisition and quality UX

Before start:
- Explain location permission in the context of recording an outdoor route.
- Display location readiness/quality as acquiring, usable, weak or unavailable, based on actual diagnostics and sample age.
- Do not force the user to wait forever for a perfect fix; allow recording with a clear warning and retain the lower-quality state.

During recording:
- Show an unobtrusive quality indicator and last-fix age.
- Do not animate the route as if it were exact when the location is stale or poor.
- Show a gap warning only when actionable; avoid alert fatigue.
- Provide a clear active recording indicator and stop control.

After recording:
- Show the route with uncertain/gap regions visually distinguishable.
- Report distance and pace as estimates derived from accepted data.
- If route quality was poor, explain why and avoid presenting false precision.

### 28.8 Battery and update cadence

- Request a location quality/accuracy level appropriate for outdoor walking; do not run maximum-frequency raw sensor loops without evidence they improve the final route.
- Batch persistence writes where safe, but never leave the only copy of recent route points in memory for long periods.
- Measure battery drain on real devices for screen-on, screen-locked, weak-GNSS and BLE-connected walks.
- Use system thermal state and battery state to reduce optional work, not to silently reduce essential recording quality.
- Do not hard-code one universal update interval before controlled field measurements. Platform batching and callback cadence are OS-controlled and may vary.

### 28.9 Route engine implementation gates

Before the route engine is frozen:
1. Confirm the exact modern Core Location API and availability annotations in the Xcode SDK used for the iOS 26+ build.
2. Confirm the selected iOS background location session lifecycle and recovery after process termination.
3. Confirm Android foreground location service type/permission requirements across supported API levels and Play policy.
4. Test approximate vs precise location, location disabled, stale cache, no fix, indoor start, urban canyon, tree cover and open sky.
5. Test screen lock, incoming call, audio interruption, app suspension, low battery, thermal pressure and OEM battery saver.
6. Compare repeated routes against known-distance reference and independent track, recording raw samples and accuracy metadata.
7. Verify pause/resume, route gaps, duplicate callbacks, out-of-order callbacks and save/recovery.
8. Measure battery consumption and establish evidence-based sampling/flush cadence.

Research status: public platform background/location behaviour and GNSS failure modes documented. Route thresholds, update cadence and production algorithm remain intentionally unfinalized until controlled field evidence is available.


## 29. Elevation, altitude and barometric measurement — hardware-first research

Research update: 2026-11-07. This section distinguishes absolute altitude, relative altitude, pressure-derived height and accumulated ascent. These are different quantities and must not be conflated in WALKON.

### 29.1 Four different elevation concepts

- **Absolute altitude/elevation:** height relative to a defined vertical datum (for example, mean sea level/geoid or a reference ellipsoid). Values from different datums are not directly interchangeable without conversion.
- **Relative altitude change:** change from a chosen baseline. This is often more useful for a single walk than a perfectly accurate sea-level elevation.
- **Cumulative ascent (elevation gain):** sum of accepted positive changes along a route after noise filtering. It is not simply final altitude minus starting altitude.
- **Cumulative descent:** corresponding sum of accepted negative changes. It must be computed separately from ascent.

A route that climbs 30 m and descends 30 m can finish near its starting altitude while still having approximately 30 m of ascent and 30 m of descent. Conversely, summing every tiny noisy upward fluctuation can greatly exaggerate ascent.

### 29.2 Physical barometer: what it measures

A barometer measures atmospheric pressure, not height. Pressure generally falls as altitude increases, but it also changes with weather systems, temperature and local atmospheric conditions. Therefore:
- Short-term pressure change can be a useful indicator of relative vertical movement.
- Absolute altitude requires a reference sea-level pressure or another calibration source.
- Weather-related pressure drift can look like climbing or descending if treated as terrain movement.
- Android's public sensor documentation identifies the pressure sensor as a continuous, non-wake-up sensor reporting hPa, with temperature and factory bias/scale compensation; it explicitly notes that sea-level pressure is needed for absolute elevation.

Sources:
- https://source.android.com/docs/core/interaction/sensors/sensor-types
- https://developer.android.com/reference/android/hardware/SensorManager#getAltitude(float,float)

### 29.3 iPhone altimeter access

Apple exposes altitude-related changes through Core Motion `CMAltimeter`:
- Check `isRelativeAltitudeAvailable()` and `isAbsoluteAltitudeAvailable()` at runtime; never assume every device supports both.
- Relative altitude updates are the likely primary barometric input for ascent tracking during a workout.
- Absolute altitude is a separate capability and must not be assumed equivalent to Core Location's altitude.
- Motion usage description (`NSMotionUsageDescription`) is required before accessing these motion services; missing it can crash the app.
- Start updates only when needed and stop them when the workout ends or the feature is no longer required.

Core Location altitude is separately documented as orthometric height approximating mean sea level using a geoid model; it is valid only when `verticalAccuracy` is positive. Apple describes vertical accuracy as an estimated uncertainty of roughly one standard deviation (about 68% coverage), not a guarantee.

Sources:
- https://developer.apple.com/documentation/coremotion/cmaltimeter
- https://developer.apple.com/documentation/corelocation/cllocation/altitude
- https://developer.apple.com/documentation/corelocation/cllocation/verticalaccuracy
- https://developer.apple.com/documentation/corelocation/cllocation/ellipsoidalaltitude

### 29.4 Android barometer and GNSS altitude

- Android's optional `Sensor.TYPE_PRESSURE` reports pressure in hectopascals. The sensor may be absent; check `getDefaultSensor(TYPE_PRESSURE)` and record capability.
- `SensorManager.getAltitude()` estimates altitude from measured pressure and a supplied sea-level pressure. Standard-atmosphere pressure is only an approximation for absolute height; Android notes that pressure differences can still be used for altitude differences.
- Android `Location.getAltitude()` is height above the WGS84 reference ellipsoid. `getVerticalAccuracyMeters()` is a separate estimate and is only valid when `hasVerticalAccuracy()` is true (API 26+).
- Do not compare Android ellipsoidal altitude directly with iOS mean-sea-level altitude without a geoid/datum transformation.
- Sensor availability and quality differ by handset; barometer must remain an optional capability, not a core app dependency.

Sources:
- https://source.android.com/docs/core/interaction/sensors/sensor-types
- https://developer.android.com/reference/android/hardware/SensorManager
- https://developer.android.com/reference/android/location/Location

### 29.5 GNSS vertical error versus barometer drift

GNSS altitude is typically less stable than horizontal positioning, particularly in obstructed environments. A barometer can resolve short-term vertical changes more smoothly, but it is vulnerable to atmospheric pressure changes and sensor/environment effects. Neither source alone is a universally correct elevation truth.

A comparative study of 202 mountain efforts found substantial elevation-gain errors across GPS watches, barometric watches and smartphones; in that study the barometric device tended to overestimate and GPS devices tended to underestimate. Post-processing using secondary information materially improved the estimates. This is evidence against choosing a sensor label as a substitute for validation; it is not a universal error rate for all phones or routes.

Source:
- https://journals.sagepub.com/doi/10.1177/1754337120918975

### 29.6 WALKON elevation-source hierarchy — proposed, pending device tests

Do not hard-code one source for all devices. Record capabilities and select a documented policy per platform/device:
1. If a supported barometer is available and validated, use its relative pressure-derived changes as the primary short-term vertical-change stream during an outdoor workout.
2. Use GNSS/location altitude and its vertical accuracy as a secondary consistency signal and for geospatial context, not as an unquestioned source of ascent.
3. Use a trusted elevation model or map-derived terrain height only as an optional post-processing/reference layer if data coverage, licence, resolution, datum and offline behaviour are acceptable.
4. If barometer is unavailable, use a conservative GNSS-only ascent estimate with stricter quality gating, or show elevation gain as unavailable/low-confidence rather than inventing precision.
5. Never fuse two altitude streams by simply adding their changes. A fusion algorithm must be explicitly specified, versioned, testable and evaluated against known routes.

This hierarchy is a research proposal, not yet a frozen implementation decision. Device tests must decide whether barometric data is available and useful on the target iPhone and representative Android models.

### 29.7 Ascent calculation: proposed processing stages

1. **Capability and permission check:** record whether barometer/relative altitude is available and authorized; do not infer hardware from device name alone.
2. **Baseline:** establish a workout-relative baseline after sensor startup stabilizes; retain the baseline event and source.
3. **Timestamp alignment:** preserve source timestamps and monotonic ordering; align pressure and location observations without pretending their delivery cadence is identical.
4. **Noise control:** use a documented low-pass/robust filter and a minimum meaningful vertical-change threshold derived from validation data, not an arbitrary universal number.
5. **Movement confirmation:** use route context and motion state to distinguish sustained vertical movement from stationary pressure drift where possible.
6. **Ascent/descent accumulation:** accumulate accepted positive/negative changes separately; ignore oscillations inside the validated noise band.
7. **Drift handling:** identify slow baseline drift and recalibrate only under a documented rule. Do not silently subtract drift in a way that erases real long gradual climbs.
8. **Quality and provenance:** retain raw samples, filtered values, source, calibration events, rejection reasons and algorithm version.
9. **Presentation:** round conservatively and expose low-confidence/unavailable states; avoid decimal-place precision unsupported by the sensors.

### 29.8 Data model additions

Each altitude observation should carry:
- workout UUID and timestamp (event + received);
- source type: Core Motion relative, Core Motion absolute, Core Location orthometric, Core Location ellipsoidal, Android pressure, Android GNSS, or external accessory;
- raw value and unit (hPa, metres, or other explicitly identified unit);
- vertical accuracy/uncertainty when provided;
- altitude datum/reference (MSL/geoid, WGS84 ellipsoid, workout-relative, unknown);
- baseline/calibration identifier and event;
- device capability and permission state;
- raw/filtered/derived classification;
- quality state, rejection reason and algorithm version.

Workout summary should distinguish `ascent_m`, `descent_m`, `start_altitude_m`, `end_altitude_m`, `altitude_source`, `altitude_quality` and whether the figure is measured, fused or terrain-model-derived.

### 29.9 Field-validation protocol before implementation freeze

Test the target iPhone and representative Android devices on:
- a stationary 30–60 minute session to quantify pressure drift/noise;
- repeated known stair flights with known floor/height reference;
- a measured hill route with sustained ascent and descent;
- a flat loop to quantify false positive elevation gain;
- indoor/outdoor transitions and temperature changes;
- phone in hand, pocket, arm band and bag where sensor exposure differs;
- barometer absent/disabled and GNSS weak/no-fix conditions;
- screen locked and background workout operation;
- repeated same-route trials at different times/weather conditions.

Compare against a surveyed/known vertical reference where possible. Record error distribution, bias, repeatability, false ascent on flat routes, missed ascent on climbs, drift per hour, battery cost and recovery after interruption. A single successful walk is not sufficient validation.

### 29.10 Open decisions — do not guess

- Is CMAltimeter relative altitude available and stable on the exact target iPhone model/OS combination used by WALKON?
- What is the actual pressure sensor hardware and availability across target Android models?
- Which filter and minimum-change threshold minimize false ascent without erasing real short climbs?
- How should pressure drift be corrected during long walks with changing weather?
- Is an elevation-model correction worth the network, licensing, privacy and offline complexity?
- What confidence threshold is required before displaying ascent/descent?

Research status: physical measurement principles and public iOS/Android APIs documented. WALKON fusion algorithm, thresholds, calibration policy and device capability matrix remain open pending controlled field validation. No app implementation is authorized by this section.


## 30. Motion sensing, pedometer and activity recognition — hardware-first research

Research update: 2026-11-07. This section defines the roles of accelerometer, gyroscope, sensor fusion, system pedometer and activity recognition. The core principle is that WALKON should consume the highest-level reliable system service for a task and use raw sensors only when a measured requirement cannot be met by that service.

### 30.1 Physical sensors and what they actually measure

- **Accelerometer:** measures specific force along three device axes, including gravity. It does not directly measure steps, walking distance or calories.
- **Gyroscope:** measures angular velocity around device axes. It detects rotation, not translation or distance.
- **Magnetometer:** measures local magnetic field. It can help estimate heading but is disturbed by steel structures, magnets and electrical equipment.
- **Sensor-fusion output:** combines accelerometer, gyroscope and sometimes magnetometer data to estimate device attitude, gravity direction and user acceleration. It is still an estimate and can drift or be disturbed.
- **Pedometer / step counter:** a higher-level system service that classifies walking steps, often using a low-power motion processor or system algorithms. Its exact classifier and hardware path are proprietary and should not be reverse-engineered or assumed.
- **Activity recognition:** estimates a broad activity class such as walking, running, cycling, still or in vehicle. It is probabilistic classification, not proof that a workout is active.

### 30.2 iOS public APIs and constraints

**Core Motion** provides raw accelerometer and gyroscope values as well as processed `CMDeviceMotion` output. Apple's documentation explains that device-motion processing can separate gravity from user acceleration and provide attitude/rotation estimates. Apple also advises creating only one `CMMotionManager` instance per app because multiple instances can affect sensor delivery rates.

**CMPedometer** is the preferred first candidate for walking metrics on iPhone. It provides system-generated step counts, estimated distance, floors, pace and cadence where each capability is available. It supports historical queries and live updates; availability must be checked independently for each metric. It requires `NSMotionUsageDescription` and user authorization. Its outputs are system estimates, not a promise of exact ground-truth steps or distance.

WALKON iOS rules:
- Use `CMPedometer` for session steps/cadence/distance where available and validated; do not simultaneously add HealthKit aggregate steps.
- If CMPedometer is unavailable, show a clear unsupported/unavailable state until a separately validated fallback is designed. Do not silently invent steps from GPS.
- Use Core Motion raw accelerometer/gyroscope only for a defined feature that system APIs do not provide and only after accuracy, battery, background and device-placement tests.
- Check each capability at runtime. A device may support step counting but not all other pedometer metrics.
- Keep one app-level motion manager and stop each stream when no longer needed.

Sources:
- https://developer.apple.com/documentation/coremotion
- https://developer.apple.com/documentation/coremotion/cmpedometer
- https://developer.apple.com/documentation/coremotion/cmmotionmanager
- https://developer.apple.com/documentation/coremotion/cmdevicemotion

### 30.3 Android public APIs and constraints

Android exposes standard sensor types through `SensorManager`. The two important step sensors are distinct:
- `TYPE_STEP_COUNTER` reports a cumulative count since reboot while the sensor is activated. It is hardware-implemented and expected to be low power. The app must remain registered for counting to continue; the event may be delivered after the device wakes.
- `TYPE_STEP_DETECTOR` emits one event per detected step and is intended for per-step events/dead reckoning. It requires `ACTIVITY_RECOGNITION` on supported Android versions.

Android activity recognition in Google Play services has Transition and Sampling APIs. Google's documentation recommends the Transition API for common use because it is more power efficient and reports activity changes; Sampling is for cases requiring finer-grained control and requires the app to manage more power and filtering complexity.

WALKON Android rules:
- Query sensor availability at runtime; hardware implementation is not guaranteed on every phone.
- Prefer the cumulative hardware step counter for continuous step totals where available, persisting boot epoch, last count and event timestamp.
- Use detector events only when event-level timing is genuinely required and the device's behaviour is validated.
- Never add counter and detector totals together.
- Treat activity recognition as contextual evidence, not as the source of workout steps or an automatic substitute for explicit user start.
- Handle missing permission, absent sensor, process death, reboot/reset, stale events and OEM-specific behaviour distinctly.

Sources:
- https://developer.android.com/reference/android/hardware/Sensor
- https://developers.google.com/android/reference/com/google/android/gms/location/ActivityRecognitionClient

### 30.4 Why phone position changes step detection

A phone can be in a trouser pocket, hand, jacket, handbag, backpack, arm band or mounted holder. Each placement changes the acceleration/rotation pattern and signal-to-noise ratio. A phone can be stationary while a user walks (for example, phone left in a bag on a moving trolley), or move while the user is not walking (vehicle vibration, hand gestures, shaking). Therefore raw acceleration magnitude is not a universal step counter.

WALKON must not claim that a single raw accelerometer threshold works across all placements, gait speeds, ages, mobility patterns and devices. Use OS pedometer output as the baseline, then validate placement-specific behaviour on real devices. If the user carries a watch, phone and external tracker, source reconciliation must prevent duplicate steps.

### 30.5 Sensor fusion: what is and is not knowable

Apple publicly documents processed device-motion values and says Core Motion performs sensor fusion. Android exposes sensor events and rotation/linear-acceleration sensor types where implemented. However, platform and OEM fusion weights, classifier models, motion-coprocessor firmware and vendor calibration are not public contracts.

Implications:
- WALKON can consume processed outputs but cannot assume access to the exact internal Apple/Google/Samsung step algorithm.
- Do not fuse accelerometer, gyro, pedometer, HealthKit and GPS counts by summing them. They are overlapping observations of the same physical movement.
- Build a source-selection/reconciliation layer that selects one authoritative source per metric and interval, preserving other sources as comparison/diagnostic observations only.
- Record provider, device, time interval, metric semantics, quality and algorithm version so disagreements can be explained.

### 30.6 Walking, running, vehicle and stillness classification

Activity recognition is useful for context: detecting a likely transition from still to walking, suppressing obviously implausible GPS movement, or suggesting that a user may have forgotten to stop. It should not silently start/stop or rewrite a workout without a clear product policy.

Proposed WALKON policy:
- Explicit user start remains the authority for a workout.
- Recognition may label segments as likely walking/running/vehicle/still with confidence and timestamp.
- Low confidence remains `unknown`; do not force a classification.
- A likely vehicle segment may trigger a gentle warning, but must not delete distance or pause automatically in v1.
- Manual pause/resume always wins over inferred activity.
- Auto-pause/auto-resume is deferred until false-positive/false-negative rates are measured across devices and user populations.

### 30.7 Battery, sampling and background behaviour

- Prefer system pedometer and activity-transition APIs for low-power classification rather than continuous high-rate raw sensor streams.
- Avoid polling sensors on a tight timer; use callbacks/events and the lowest sampling rate that meets a validated requirement.
- Do not create duplicate motion managers/listeners or leave sensors active after workout completion.
- Android step counter can continue counting in hardware while the application processor sleeps only while the app remains registered; validate process lifecycle and reboot recovery on target OEMs.
- Measure power for phone idle/passive step tracking separately from active GPS workout tracking. Do not assume the battery cost of one represents the other.

### 30.8 Data contract and deduplication

Every motion observation should include source API/sensor type, device identifier, event timestamp, receipt timestamp, units, interval semantics, permission state, capability state, quality/confidence if supplied, boot/session epoch where relevant, raw-vs-derived designation and algorithm version.

Step values must be typed distinctly:
- cumulative hardware counter since boot;
- per-step detector event;
- interval pedometer count;
- HealthKit/Health Connect aggregate;
- workout-session total.

These types cannot be interchanged or summed without an explicit interval and reconciliation rule. Persist counter reset/reboot boundaries and avoid subtracting values across epochs.

### 30.9 Validation matrix before sensor architecture freeze

On target iPhone and a representative Android matrix, test:
- phone held, front/back trouser pocket, jacket, handbag/backpack and arm band;
- slow walk, normal walk, brisk walk, running, stairs, uneven ground and stop/start;
- walking while pushing a trolley/stroller and carrying objects;
- vehicle, bus/train, bicycle and stationary phone movement;
- phone screen locked, app backgrounded, app suspended, process killed and device rebooted;
- low-power mode, battery saver and thermal pressure;
- motion permission denied/revoked and sensor unavailable;
- simultaneous phone + watch + Health platform data to detect duplicate sources.

Use manually counted video/observer counts and a validated reference device for repeated trials. Measure step-count bias, missed/false steps, cadence latency, interval delay, placement sensitivity, background continuity, reboot recovery and battery cost. Do not tune an algorithm on one person's walk and generalize it to all users.

### 30.10 Open decisions

- Confirm actual CMPedometer behaviour and metric availability on the target iPhone/iOS build.
- Confirm the iPhone's passive motion-coprocessor behaviour and delivery during locked/background conditions through field tests; public API documentation does not promise every lifecycle case.
- Build an Android OEM/API-level matrix for step counter/detector presence, registration lifecycle and accuracy.
- Decide whether WALKON needs any raw sensor processing beyond system pedometer and activity recognition.
- Establish validated thresholds and acceptance limits from a multi-placement test corpus.

Research status: physical sensor roles and public APIs documented. Internal fusion algorithms remain proprietary; device-specific accuracy, background behaviour and battery performance require controlled testing. No app implementation is authorized by this section.


## 31. Heart-rate science and metrics — hardware-first research

Research update: 2026-11-07. This section defines what heart-rate sensors measure, platform access, data semantics, limitations and validation requirements. It does not turn WALKON into a medical diagnostic product.

### 31.1 Heart rate is not the same as electrical rhythm

- **Heart rate (HR):** beats per minute (bpm), usually estimated from pulse timing or electrical cardiac events.
- **Pulse rate:** peripheral pressure/volume pulses detected at the wrist or another site. It usually tracks heart rate but can differ when pulse transmission is weak or irregular.
- **ECG:** measures electrical potential differences associated with cardiac depolarization/repolarization. Consumer single-lead ECG is not equivalent to a clinical multi-lead ECG.
- **PPG:** photoplethysmography measures changes in light absorption/reflection associated with blood-volume changes in tissue. Wrist wearables infer pulse timing and calculate bpm; they do not directly record the heart's electrical signal.
- **HRV:** variation in intervals between successive normal heartbeats, not the same as average HR and not a direct stress score.
- **Heart-rate recovery (HRR):** decline in HR after exercise stops, defined only with a documented protocol and measurement window.

### 31.2 Sensor technologies and what WALKON can access

**Wrist optical PPG**
- Green LEDs and photodiodes detect pulsatile blood-volume changes at the wrist; some devices also use infrared or other wavelengths.
- Continuous or periodic sampling is performed by the wearable firmware. A phone app generally receives processed HR samples, not raw optical waveforms or proprietary filtering internals.
- Fit, contact pressure, wrist placement, skin perfusion, cold, tattoos, motion and activity type affect signal quality.
- Rhythmic walking/running can be easier than irregular arm motion or resistance exercise.

**Electrical ECG / electrode-based sensors**
- A chest strap commonly detects electrical cardiac activity and can provide beat-to-beat timing. It is a stronger practical reference for field validation than wrist PPG, though not a replacement for clinical ECG.
- Apple Watch's electrical sensor is used for user-initiated ECG/heart-rate measurement through the Digital Crown circuit; it is not the same as its continuous optical workout stream.
- iPhone has no built-in optical wrist sensor or ECG electrodes. For live HR during an iPhone workout, an external compatible heart-rate sensor is required.

Sources:
- https://support.apple.com/en-us/120277
- https://developer.apple.com/documentation/healthkit/hkworkoutsession
- https://pubmed.ncbi.nlm.nih.gov/32552580/
- https://pubmed.ncbi.nlm.nih.gov/28709155/

### 31.3 Evidence on accuracy — activity matters

A systematic review/meta-analysis of 44 studies, 738 effect sizes and 15 brands found small average wrist-PPG differences versus ECG/chest-strap criterion during rest and treadmill walking-to-running, but larger average differences during resistance exercise and cycling. Group-average bias does not guarantee individual accuracy or absence of outliers.

A separate controlled comparison found chest strap agreement with ECG was highest in its tested set; wrist devices varied substantially by model and activity, with some activities producing poor agreement. Apple's own support guidance identifies low skin perfusion/cold, tattoos and motion as factors that can reduce optical readings, and suggests compatible external monitors where wrist readings are inconsistent.

WALKON consequences:
- Never label consumer wearable HR as clinical-grade or guaranteed accurate.
- Preserve source and activity context.
- Do not interpolate long missing intervals as if measured.
- A plausible bpm value is not proof of a valid pulse signal.
- Validate walking separately from cycling, strength training and irregular movement.
- Use an external electrical chest strap as a reference instrument in controlled validation.

### 31.4 iOS and HealthKit access

- HealthKit exposes heart-rate samples using `HKQuantityTypeIdentifier.heartRate`; sample units are count/time and samples may be condensed or coalesced.
- Apple documents related data types including resting HR, walking HR average, HRV SDNN and one-minute HR recovery. They have different meanings and should remain separate metrics.
- Heart-rate samples may include motion-context metadata (for example sedentary or active), but not every sample contains it. Missing context must be represented as unknown, not guessed.
- HealthKit requires fine-grained per-type authorization. Critically, an app cannot reliably distinguish a denied read permission from an empty result; the UI must not claim that the user explicitly denied access based only on no returned samples.
- An iPhone workout session does not create an optical HR sensor: Apple's HealthKit documentation says iPhone/iPad need a paired external HR sensor for HR collection. Apple Watch workout sessions can generate high-frequency HR samples.
- iPhone locked-state health-data access has privacy restrictions; workout collection and later HealthKit reading/writing must be designed according to Apple's documented session lifecycle and protected-data behaviour.

Sources:
- https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartrate
- https://developer.apple.com/documentation/healthkit/hkworkoutsession
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data

### 31.5 Android and Health Connect access

- Health Connect represents HR as a series record (`HeartRateRecord`) containing timestamped bpm samples and start/end times.
- Read/write permissions are distinct: `READ_HEART_RATE` and `WRITE_HEART_RATE`.
- Health Connect exposes aggregate average, minimum, maximum and measurement count, but aggregates do not replace the underlying sample timeline when workout analysis needs temporal detail.
- HRV is a separate RMSSD record in milliseconds and uses its own permission; it is not interchangeable with Apple's SDNN HRV value.
- Health Connect metadata identifies recording method (manual, automatic, actively recorded, unknown) and device/source information. WALKON must retain this provenance and avoid assuming every sample came from a watch or from the current workout.
- Background and historical access have additional permission requirements. Ask only for the access the current feature needs.

Sources:
- https://developer.android.com/health-and-fitness/health-connect/data-types
- https://developer.android.com/health-and-fitness/health-connect/metadata
- https://developer.android.com/health-and-fitness/health-connect/write-data

### 31.6 HR sampling, timestamps and missing data

- HR samples are observations at times, not a continuous waveform. Do not imply continuous coverage between samples.
- Preserve the original event timestamp, ingestion/receipt timestamp, sample interval semantics, source device, recording method and workout association.
- Sampling frequency is controlled by the sensor, wearable firmware, platform and power policy; it may change with activity or device state. Do not promise a fixed one-second stream unless a specific sensor/API contract and field test support it.
- Keep gaps visible in charts and summaries. Never fill long gaps with a flat line or synthetic values.
- Detect stale samples, out-of-order delivery, duplicate records and overlapping sources.
- For live display, show the sample age and an unavailable/stale state when the last reading is too old; choose threshold from sensor/API behaviour and testing rather than inventing a universal value.
- Distinguish session HR samples from all-day background HR samples and from historical HealthKit/Health Connect records.

### 31.7 Metric definitions — keep separate

- **Live HR:** most recent valid sample with sample age and source.
- **Average HR:** time-weighted or sample-weighted only under a documented calculation policy; do not silently mix different methods.
- **Maximum HR:** highest accepted sample within the session, with quality checks.
- **Resting HR:** platform-provided resting metric or a separately validated baseline algorithm; not simply the lowest value seen during a workout.
- **Walking HR average:** distinct HealthKit metric where available; do not rename it as resting HR.
- **HR zones:** require a chosen zone model and user-specific inputs. Age-predicted maximum HR is an estimate, not an individual's measured maximum. Avoid presenting zone boundaries as medical advice.
- **HRV:** preserve the measurement method (e.g. SDNN vs RMSSD), units, context and source. Values from different algorithms/windows are not directly comparable.
- **HR recovery:** requires a standardized post-exercise protocol (peak/finish reference, recovery posture, exact elapsed time and measurement source). Do not calculate it from arbitrary missing or sparse samples.
- **Calories:** HR may contribute to an energy model but does not independently determine energy expenditure. Defer calorie model design to Section 35.

### 31.8 WALKON source-of-truth and wearable priority proposal

- For iPhone-only recording, WALKON cannot measure HR with the phone itself. Display HR as unavailable unless a compatible external sensor is connected or authorized HealthKit data is available for historical/context views.
- For Apple Watch, consume workout HR through the supported HealthKit/watch workout data path; do not create a second competing HR recorder on iPhone.
- For Android, consume a live compatible wearable/sensor stream only through a defined supported adapter; Health Connect is the durable health-data exchange layer, not a guaranteed low-latency live telemetry transport.
- When multiple devices provide overlapping HR, select one authoritative source for the active workout according to explicit user/device priority and connection state. Retain other observations for diagnostics, not for averaging or summing.
- If the selected source disconnects, mark the gap and optionally switch source only under an explicit, logged handover policy. Never silently splice sources without preserving the boundary.
- WALKON is not a medical monitor and must not diagnose arrhythmia, prescribe HR zones or tell users that an anomalous reading is safe.

### 31.9 Proposed heart-rate data contract

Each sample/series should include:
- workout UUID or explicit null for non-workout/background sample;
- event timestamp, receipt timestamp, and source interval where applicable;
- bpm value and unit;
- sensor modality (PPG, electrical chest strap, ECG-derived, unknown);
- provider/platform/API and source device identity;
- recording method (manual, automatic, actively recorded, unknown);
- sample quality/confidence if supplied by source; never fabricate it;
- motion/activity context if supplied, otherwise unknown;
- permission/authorization state as observable (do not infer hidden HealthKit read denial);
- live/historical/background/session classification;
- source-selection epoch and handover boundary;
- raw imported vs transformed/derived designation and algorithm version.

Derived summaries must store the source sample set or query window, aggregation method, gaps, excluded samples and algorithm version.

### 31.10 Battery and privacy requirements

- Do not attempt continuous camera-flash PPG using the iPhone camera as a substitute for a wearable. It is a different, unvalidated product feature with usability, heat, battery, privacy and motion limitations.
- Prefer a paired wearable's native sensor and low-power Bluetooth protocol for live HR.
- Avoid repeated broad HealthKit/Health Connect history queries; request incremental or bounded windows according to platform capabilities.
- Health data is sensitive. Request read access only when the user activates a feature that needs it; explain why; do not upload HR by default.
- Do not store raw ECG waveforms unless a separately justified, consented feature and security design exists.

### 31.11 Validation protocol before architecture freeze

Use a reference ECG/chest strap and repeated paired trials. Validate:
- seated rest, standing, slow/normal/brisk walk, uphill walk, jog/run, cycling and resistance/arm-motion activity;
- cold/warm conditions, different wrist fit/tightness and sensor placement;
- phone-only (must correctly report no native HR sensor), Apple Watch, at least two Android wearable/sensor paths and a BLE chest strap;
- connection loss/reconnect, Bluetooth disabled, wearable battery low, phone screen locked and app backgrounded;
- timestamp delay, missing samples, duplicate/overlapping sources and post-workout sync;
- HR error (bias and absolute error), outlier rate, valid-sample coverage, latency, gap duration, reconnect time and battery impact.

Acceptance thresholds must be defined per use case from a test protocol before implementation. Do not infer universal pass limits from a study's mean error.

### 31.12 Open decisions — do not guess

- Which live HR path is supported and reliable for Apple Watch with the intended iPhone app architecture?
- Which BLE heart-rate profile/devices are in the first supported Android/iOS interoperability matrix?
- How will WALKON distinguish unavailable sensor, disconnected sensor, no recent sample and HealthKit empty/unknown authorization state?
- Which HR zone model, if any, is appropriate for a general walking companion, and how will it be presented without medical claims?
- Will HRV and HR recovery be deferred until sufficient device provenance and repeatability are demonstrated?
- What are the field-tested latency, coverage, accuracy and battery acceptance thresholds?

Research status: physical PPG/ECG distinctions, platform data types, permissions, known limitations and validation design documented. Target-device interoperability, live latency, sampling behaviour and acceptance thresholds remain untested. No app implementation is authorized by this section.

## 32. Wearables and Bluetooth interoperability — hardware-first research

Research update: 2026-11-07. This section separates generic BLE accessories from Apple Watch and Wear OS. A watch is not automatically a generic Bluetooth sensor; each ecosystem has its own supported data path.

### 32.1 Three integration paths

1. **Standard BLE accessory:** chest strap, optical armband or cadence sensor exposing documented GATT services. WALKON can connect directly through Core Bluetooth on iOS or Android BLE APIs.
2. **Apple Watch:** native watchOS workout and HealthKit ecosystem. Do not assume the iPhone can treat Apple Watch as a generic BLE Heart Rate Service peripheral. A full live experience needs a native watchOS companion and coordinated workout ownership.
3. **Wear OS:** use Health Services on the watch for exercise metrics and Wearable Data Layer for paired Android phone communication. Google's Data Layer is unavailable when the Wear OS watch is paired to an iPhone; cross-phone use needs a separate network/cloud design.

Sources:
- https://developer.apple.com/documentation/corebluetooth
- https://developer.apple.com/documentation/healthkit/running-workout-sessions
- https://developer.android.com/health-and-fitness/health-services
- https://developer.android.com/training/wearables/data/overview

### 32.2 Bluetooth SIG Heart Rate Service (HRS)

The Bluetooth SIG Heart Rate Service 1.0 is a standard GATT service for fitness heart-rate sensors:
- Heart Rate Service UUID: 0x180D.
- Heart Rate Measurement characteristic: 0x2A37, mandatory and delivered through notifications.
- Client Characteristic Configuration descriptor: 0x2902, used by the client to enable notifications.
- Body Sensor Location: 0x2A38, optional read-only description.
- Heart Rate Control Point: 0x2A39, optional control for resetting Energy Expended when supported.
- Measurement flags specify UINT8 or UINT16 HR encoding and whether Energy Expended and RR-Interval fields are present.
- RR-Interval values use 1/1024-second units. They are beat interval observations, not an ECG waveform.
- Typical notifications are approximately once per second, but the sensor controls the interval. A client cannot demand a guaranteed fixed cadence.
- The standard notification has no measurement timestamp. WALKON must record local receipt time and mark acquisition time as unknown/estimated, not fabricate a precise sensor timestamp.
- Notifications lost during link loss are not guaranteed to be replayed. Gaps must remain gaps.

The parser must be flag-driven, tolerate both HR integer widths and optional/variable fields, and reject malformed packets safely.

Sources:
- https://www.bluetooth.com/specifications/specs/heart-rate-service-1-0/
- https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html
- https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRP_v1.0/out/en/index-en.html

### 32.3 BLE connection lifecycle

A robust adapter needs explicit states: unavailable, permission required/denied, scanning, discovered, selected, connecting, service discovery, subscribing, streaming, disconnected, reconnecting and forgotten.

Requirements:
- Scan only during a user connection flow or an explicitly authorized workout reconnect window.
- Filter by service UUID where possible; avoid continuous broad scanning.
- Ask the user to select the intended sensor when multiple candidates appear.
- Discover services and characteristics after every connection; never rely on fixed handles.
- Enable notifications and confirm subscription before marking the sensor live.
- Validate packet length, flags, units and plausible values.
- Stop scanning after selection, cancellation, permission loss or workout completion.
- Do not assume public HRS characteristics always require BLE bonding; follow the peripheral's actual security requirements and system pairing prompts.
- Record disconnect cause, last notification time and reconnect attempts.

### 32.4 iOS Core Bluetooth background behaviour

- Core Bluetooth provides BLE central/peripheral APIs; WALKON is a central when connecting to a chest strap.
- Handle manager state changes, authorization, radio-off state, connection failures, discovery, subscription and disconnect callbacks.
- iOS background BLE operation is constrained. The bluetooth-central background mode allows certain event-driven work; it does not grant unlimited execution or guarantee a permanently running process.
- Apple's state preservation/restoration can preserve scans, pending/active connections and notification subscriptions and relaunch the app for events. WALKON must opt in, recreate managers with restoration identifiers and restore state in the delegate callback.
- Background scans are coalesced/restricted and discovery may take longer than in foreground.
- Current Core Bluetooth documentation describes additional iOS 26+ background privileges under specific Live Activity conditions. This is not a blanket guarantee for every scan or lifecycle; use only documented conditions and verify on target OS versions.
- Persist important events promptly; the app can still be terminated.
- Avoid scanning when no active workout or explicit connection task exists.

Sources:
- https://developer.apple.com/documentation/CoreBluetooth
- https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/

### 32.5 Android BLE permissions and background operation

For Android 12/API 31+:
- BLUETOOTH_SCAN is required to discover nearby devices.
- BLUETOOTH_CONNECT is required to communicate with connected devices.
- BLUETOOTH_ADVERTISE is only needed if WALKON makes the phone discoverable as a peripheral.
- These are runtime Nearby devices permissions. Request only those needed for the selected action.
- If scan results are not used to derive physical location, Android permits a neverForLocation assertion; manifest declarations must match actual behaviour.
- Older Android versions have legacy Bluetooth and location permission rules, requiring API-level handling.

For persistent notification streams:
- Companion Device Manager provides a system pairing flow and can avoid location permission for that pairing scan, but does not itself provide a continuous data connection.
- Android documents CompanionDeviceService/presence observation or a foreground service using the connectedDevice type for ongoing BLE notifications while backgrounded.
- A foreground service has start restrictions and user-visible notification requirements.
- Reconnect after process termination must be designed explicitly; do not assume a GATT connection survives process death.
- Handle Bluetooth off, permission revocation, force-stop and OEM battery restrictions distinctly.

Sources:
- https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
- https://developer.android.com/develop/connectivity/bluetooth/ble/background
- https://developer.android.com/develop/connectivity/bluetooth/companion-device-pairing

### 32.6 Apple Watch integration boundary

Apple documents workout sessions running on Apple Watch. During an active watch workout, the system can provide high-frequency HR samples and keep the watch workout app running in the background. The iPhone companion must coordinate start/stop and avoid saving a second inconsistent workout.

WALKON requirements:
- A robust live Apple Watch experience requires a native watchOS companion; it is not generic BLE pairing.
- The watch app owns or coordinates the watch workout session and HealthKit builder. Phone and watch share a stable logical workout ID and explicit state transitions.
- If the watch starts a workout, the iPhone must not independently finish/save a duplicate. If the phone starts it, the watch companion joins the same logical workout under a defined protocol.
- The watch must be able to continue recording locally during phone disconnection and synchronize later.
- Define one authoritative workout owner at a time, idempotent save and explicit handover rules.
- Apple Watch support is a separate development scope and should follow proof of the iPhone recorder.

Sources:
- https://developer.apple.com/documentation/healthkit/running-workout-sessions
- https://developer.apple.com/documentation/healthkit/hkworkoutsession
- https://support.apple.com/en-in/108779

### 32.7 Wear OS integration boundary

- Wear OS 3+ Health Services mediates device sensors and algorithms and can provide HR, distance, calories, elevation, floors, speed and pace.
- Use Health Services for watch exercise metrics instead of independently reimplementing the watch sensor pipeline without a validated need.
- Wearable Data Layer supports app-to-app messages and synchronization between Wear OS and paired Android phones. DataItems are synchronization primitives, not the watch's permanent database.
- Google states the Data Layer is unavailable when a Wear OS watch is paired with an iPhone.
- A Wear OS watch may have independent Wi-Fi/cellular connectivity; WALKON must not assume a direct BLE path to the phone.
- Keep durable workout storage on watch and phone independently; reconcile with stable workout IDs and event sequence numbers.

Sources:
- https://developer.android.com/health-and-fitness/health-services
- https://developer.android.com/training/wearables/data/overview
- https://developer.android.com/training/wearables/data/sync
- https://developer.android.com/training/wearables/data/network-communication

### 32.8 Multiple sensors and source handover

A user may have a chest strap, optical armband, smartwatch and phone producing overlapping observations. Never merge overlapping HR readings by indiscriminate averaging.

Proposed policy:
1. User selects preferred workout sensor.
2. WALKON selects one authoritative live HR source per interval.
3. Other sources remain diagnostics or separate historical observations.
4. On disconnect, mark the gap and reconnect. If user enabled fallback, switch source with a logged handover event and new source epoch.
5. Do not silently splice optical and electrical sources into one uninterrupted trace.
6. On reconnect, reject stale buffered notifications when measurement time cannot be established; standard HRS has no embedded timestamp.
7. Preserve source identity, connection state and priority.

### 32.9 Security and privacy

- Use platform BLE security and pairing; do not invent custom cryptography over BLE.
- Do not scan continuously for analytics or retain unnecessary device identifiers.
- Treat sensor samples and workouts as sensitive health data; no default upload.
- A nearby BLE advertisement alone is not proof of device identity.
- Wear OS Data Layer access is restricted by matching app package/signature; cloud-routed traffic may pass through Google infrastructure, so it is not necessarily a purely local channel.
- Provide disconnect, forget-device and data deletion controls.

### 32.10 WALKON wearable adapter contract

Each adapter should expose: app-scoped logical device ID, display name/class, supported services/capabilities, platform/transport/protocol, permission state, connection state and timestamps, selected source priority, workout ownership, parsed HR/RR/Energy Expended only when present, local receipt timestamp, timestamp quality, disconnect reason, reconnect attempts and battery only if exposed by the accessory.

Optional fields must remain optional. Do not require battery percentage, RR intervals, Body Sensor Location or sensor-quality metadata from every compatible device.

### 32.11 Compatibility and field-validation matrix

Test before claiming support:
- At least two BLE chest straps from different vendors.
- One BLE optical armband if included in scope.
- One sensor with RR intervals and one without.
- Optional Body Sensor Location/Energy Expended present and absent.
- Multiple nearby sensors with similar names.
- iPhone foreground, locked/background, suspension, termination and restoration.
- Android minimum/latest supported API levels on Pixel, Samsung and another OEM.
- Permission denial/revocation, Bluetooth off, battery saver, Companion Device pairing and connectedDevice service lifecycle.
- Apple Watch start/stop/handover/delayed sync as a separate watchOS test track.
- Wear OS Health Services/Data Layer on paired Android and confirm iPhone-pairing limitation.

Measure discovery time, connection success, time to first valid sample, sample cadence, parser correctness, notification loss, reconnect time, background continuity, battery impact, duplicates and source handover correctness.

### 32.12 Open decisions

- Which BLE HRS accessories are on the supported list?
- Is direct BLE chest-strap support in the first iPhone release or deferred until the core recorder is proven?
- Is Apple Watch a later native watchOS companion phase, or does first release only read historical HealthKit data?
- Which Wear OS devices and Health Services data types are supported?
- What are acceptable connection latency, coverage, reconnect and battery thresholds?
- What minimum device identity can be retained without collecting unnecessary persistent hardware identifiers?

Research status: BLE Heart Rate Service, iOS Core Bluetooth lifecycle, Android permissions/background paths, Apple Watch and Wear OS boundaries documented. Accessory compatibility, target-device background reliability and latency/battery thresholds remain untested. No app implementation is authorized by this section.

## 33. Workout lifecycle, interruptions and crash recovery — reliability research

Research update: 2026-11-07. A workout is a durable user-owned transaction spanning sensors, operating-system sessions, local storage and optional health-platform writes. The screen is only a view; it is never the owner of the workout.

### 33.1 Durable lifecycle and state ownership

Persist explicit states: created/preparing, recording, paused, resuming, stopping/finalizing, locally committed, health-export-pending, partially exported, exported, interrupted/recoverable and explicitly discarded. Allocate a stable workout UUID and commit the local record before starting sensors.

Button taps are commands, not proof that a platform transition succeeded. Render state from the workout coordinator and durable event journal, and wait for platform callbacks/state confirmation. Duplicate finish requests must resolve to one logical finish.

### 33.2 Event journal and deterministic transitions

Persist append-only events for workout creation, prepare/start, pause/resume requests and confirmations, segment boundaries, sensor connection/disconnection, source handover, permission loss, platform termination, interruption/recovery, finish, local commit, external export and discard.

Each event needs a stable event UUID, workout UUID, monotonically increasing per-workout sequence, event time, receipt time, source and schema version. Replay must be idempotent. Duplicate events must not double-apply steps, distance, duration or samples. Reject impossible transitions and preserve actual platform callbacks when they disagree with user commands.

### 33.3 Time and pause semantics

- Use monotonic time for elapsed intervals and wall-clock timestamps for history. Clock/timezone changes must not alter elapsed duration.
- Keep elapsed, paused and active duration separate.
- Do not depend on callback frequency to advance a timer; derive duration from timestamps and monotonic anchors.
- Pause closes the current route/movement segment; resume opens a new segment.
- Sensor availability and workout state are separate. A disconnected HR strap does not necessarily mean the workout is paused.
- Finish is one logical transition even if button taps or OS callbacks repeat.

### 33.4 iOS HealthKit session lifecycle and recovery

HealthKit workout sessions expose prepare, start activity, pause, resume, stop activity and end operations. The associated live workout builder collects and saves workout data. The app must observe session/delegate transitions rather than assuming a method call means the transition completed.

Apple documents active-workout recovery for a watchOS workout: after relaunch, the extension's recovery handler calls HealthKit's recover-active-workout-session method, then reattaches the builder data source and delegates. This is a platform-specific recovery path; it is not proof that every arbitrary iPhone process death restores every Core Location callback or route-builder object.

WALKON iOS requirements:
- Persist local workout UUID and event journal independently of HealthKit object instances.
- Persist enough state to identify the active workout before calling platform start APIs.
- On relaunch, inspect local state and recover the HealthKit active session only where the selected platform lifecycle supports it.
- Recreate delegates/data sources and verify session state before accepting new samples.
- Reconcile local journal with platform state; preserve both facts when they conflict.
- Never create a second HealthKit workout just because the app relaunched.
- Distinguish a recovered active workout from a local partial workout whose platform session cannot be recovered.
- Verify exact iPhone versus watchOS recovery APIs and availability against the chosen iOS 26+ SDK and target hardware.

Sources:
- https://developer.apple.com/documentation/healthkit/hkworkoutsession
- https://developer.apple.com/documentation/healthkit/running-workout-sessions
- https://developer.apple.com/documentation/healthkit/hkhealthstore/recoveractiveworkoutsession(completion:)
- https://developer.apple.com/documentation/healthkit/hkworkoutbuilder

### 33.5 HealthKit workout save and route finalization are separate operations

Apple documents that the route builder's finish-route operation creates, saves and associates a route with a workout that must already be saved. The builder must be finalized before deallocation; otherwise route data added to it is lost. Finalization invalidates the builder. Workout save and route save are therefore not one atomic transaction.

Required two-phase export:
1. Commit workout summary, route observations and samples locally first.
2. Save the HealthKit workout and immediately persist its external identifier.
3. Mark export state workout-saved / route-pending.
4. Finalize the route against that saved workout and persist route success/failure.
5. If route export fails, retain local route data. Never create a second workout to repair the route.
6. After an uncertain completion, query HealthKit for an existing workout/route association before retrying.
7. Never claim a deallocated or invalidated route builder can be resumed after arbitrary process death.

Open risk: a crash after route-builder insertion but before route finalization may leave no recoverable HealthKit route builder. The local route remains authoritative. Exact retry behaviour needs a controlled prototype and API confirmation.

Sources:
- https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder/finishroute(with:metadata:completion:)
- https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder
- https://developer.apple.com/documentation/healthkit/creating-a-workout-route

### 33.6 Android Health Services lifecycle and recovery

Google's exercise guidance recommends:
- A foreground service with ExerciseClient to manage workout state, sensors and ongoing activity when the screen turns off or the user navigates away.
- Room for workout data and WorkManager for upload.
- Runtime exercise capability and permission checks before prepare/start.
- Query getCurrentExerciseInfoAsync on startup. It can identify an exercise owned by this app, no active exercise, or an exercise owned by another app.
- If the process was killed but the exercise remains active and owned by the app, register a new callback and resume receiving updates; Health Services caches updates generated while no callback was active.
- Another app can take over the single active Health Services exercise. Save partial progress and explain that tracking ended.
- Permission loss can end the exercise; preserve partial data and record the end reason.
- Screen-off updates may be batched; never drive a chronometer from callback frequency.

WALKON Android requirements:
- Persist local workout state before requesting Health Services start.
- Use foreground service with correct health/location service types and current API-level permissions.
- Reconnect to the owned exercise and re-register callbacks after process recreation.
- Treat other-app takeover, permission loss, service stop, Bluetooth loss and location loss as distinct interruption causes.
- Keep uploads separate from recording; network failure must not stop or corrupt an active workout.
- Test OEM restrictions. A foreground service is not immunity from force-stop, reboot or user termination.

Sources:
- https://developer.android.com/health-and-fitness/health-services/active-data
- https://developer.android.com/health-and-fitness/health-services
- https://developer.android.com/develop/background-work/services/fgs/service-types

### 33.7 Local-first persistence and crash consistency

The local database is authoritative until external export is verified:
- Commit workout UUID and initial state before sensor activation.
- Persist route points and metric batches frequently enough to bound loss; never keep the only copy in memory.
- Use transactions for logical batches and state transitions, foreign keys, versioned migrations and a write-ahead log with appropriate durability.
- Keep the event journal append-only; summaries are rebuildable derived views.
- Each external export has an outbox record, idempotency key, attempt count, last error and retry eligibility.
- Never perform network calls inside the local database transaction.
- On restart, replay unapplied journal events, validate open segments and reconcile state against platform session evidence.
- If storage is full or a write fails, surface a critical recording warning; do not claim the workout is safely recording.

This is a design requirement, not a claim that SQLite protects against every power-loss or filesystem failure. Fault injection is required.

### 33.8 Exactly-once semantics across independent stores

There is no atomic transaction spanning SQLite, HealthKit/Health Connect, route builder and cloud backend. WALKON must use at-least-once attempts with idempotent effects and reconciliation, not pretend to have a distributed exactly-once transaction.

- Stable local workout UUID is canonical.
- Keep a unique export job per platform/object type.
- Persist external identifiers after successful creation.
- Before retrying an uncertain operation, query for a matching external record using available metadata/time/device/workout identity; do not blindly recreate.
- If the external API lacks idempotency keys or reliable lookup, mark outcome uncertain and reconcile rather than claiming automatic retry is safe.
- Test crash-before-request, request-in-flight, external-success-before-local-ack and local-ack-before-next-step.

### 33.9 Phone/watch ownership and handover

- Assign one logical workout UUID and one owner epoch (phone or watch).
- Only current owner advances authoritative lifecycle state; companion devices send sequenced commands/events.
- Handover protocol: request, acknowledge, record last committed sequence, increment owner epoch, confirm new owner, then close old owner.
- During disconnection, the active recording device continues locally if supported; later sync merges by stable event IDs, not by summing overlapping summaries.
- If both devices recorded the same interval, preserve both raw streams and select one authoritative interval; never double count.
- If ownership cannot be resolved, preserve candidates and flag a reconciliation conflict.

### 33.10 Interruption taxonomy and recovery UX

Distinguish app background/suspension, process death, user force-quit, OS/platform termination, permission revocation, location disabled, Bluetooth disconnection, phone/watch link loss, reboot, low storage/database error, health-platform export failure and network outage.

Recovery UI must state whether recording is active, paused, ended, or locally saved but not exported. Never show a live timer when the underlying platform workout ended. Preserve partial work and offer recovery/save/discard where appropriate.

### 33.11 Fault-injection acceptance matrix

Test failures at each durable boundary:
1. Kill app before/after local workout creation.
2. Kill during sensor startup, immediately after platform start and during recording.
3. Lock screen, background app, switch apps and receive calls/audio interruptions.
4. Terminate process while HealthKit/Health Services session is active; relaunch and verify ownership/recovery.
5. Trigger another workout app takeover on Android.
6. Revoke motion, health, location and Bluetooth permissions mid-session.
7. Disable GPS/Bluetooth; disconnect and reconnect sensors.
8. Pause/resume repeatedly; deliver duplicate/out-of-order callbacks.
9. Crash during route batch commit, HealthKit workout save, route finalization and local export acknowledgement.
10. Simulate offline mode, backend outage, retry, duplicate sync and reboot.
11. Fill storage and simulate database write errors.
12. Start on watch, disconnect phone, finish on watch, reconnect and verify one logical workout.

Acceptance evidence: no duplicate workouts, no fabricated route bridging, bounded loss no greater than the last uncommitted local batch, recovery where platform supports it, correct partial workout on platform termination, idempotent retries and auditable event/export journal. Set numeric loss, battery and latency limits from tests, not guesses.

### 33.12 Open decisions

- Which recovery APIs apply to the iPhone-only iOS 26+ release versus a later watchOS companion?
- Can the chosen Core Location background session be re-established after each relevant process termination, and which events are queued/delivered?
- What route-builder recovery is guaranteed after a crash before route finalization?
- Which Android devices/API versions cache and replay Health Services updates after process death, and for what window?
- How resolve platform-active/local-finishing state conflicts?
- What is the maximum acceptable uncommitted data-loss window under power loss/storage failure?
- What metadata/query strategy safely reconciles an external save whose completion callback was lost?

Research status: platform lifecycle, HealthKit route-finalization constraints, Android exercise ownership/recovery and local-first transaction design documented. Arbitrary iOS route-builder recovery, device-specific Android retention and crash-loss bounds remain open for targeted prototype/fault-injection tests. No app implementation is authorized by this section.


## 34. HealthKit and Health Connect semantics, permissions, sync and reconciliation

Status: platform documentation reviewed; WALKON policies below are engineering proposals pending implementation and device validation.

### 34.1 Scope and governing rule

HealthKit and Health Connect are user-controlled health-data stores, not interchangeable sensor APIs and not a guarantee of a single globally correct value. WALKON must distinguish live session measurements owned by the active WALKON recording pipeline; daily or historical aggregates calculated by the health platform; raw samples imported for detail, provenance or reconciliation; and records WALKON itself exported to the platform.

Never add a platform aggregate to raw records that contributed to it. Never combine overlapping provider streams merely because they have different source names. Store provenance and the aggregation method alongside every imported value.

### 34.2 Apple HealthKit: permission semantics

HealthKit uses per-type read and share authorization. Request only the data types required by a feature, at the moment the user invokes that feature; explain the purpose before the system prompt. Read and write/share permissions are separate.

Critical privacy limitation: an app cannot determine whether a user denied read access to a type. A query may return only records the app itself saved, making denied access indistinguishable from no external samples. HealthKit can also restrict the earliest date available for reading. The app must not infer “permission denied” or “zero activity” from an empty result.

WALKON states should therefore include: HealthKit unavailable on device; permission request not yet made / share authorization state where queryable; data available; no matching data returned (reason may be unknown); database temporarily inaccessible (for example, while the device is locked); query failed / retryable; and data access window limited, where the earliest permitted sample date is exposed.

Do not display a false “Connected” or “Permission denied” assertion for read access. Provide a route to Health settings and a neutral explanation that no readable records were returned.

Sources: Apple authorization and query guidance [A1, A2].

### 34.3 HealthKit: aggregate versus raw data

For daily step totals and other cumulative quantity dashboards, use the HealthKit statistics APIs with the correct cumulative-sum option and a local-calendar interval. A statistics query calculates a value over matching samples; a statistics collection query partitions samples into intervals and can return updates. By default, HealthKit merges matching sources before calculating statistics. HKStatisticsOptionSeparateBySource is available when source-level statistics are required.

For raw provenance, audit, workouts, route detail or sample-level reconciliation, use sample queries or anchored object queries as appropriate. Do not recreate the Health app's merged total by summing source totals: sources can overlap and HealthKit's default aggregation is already merged. Statistics collection queries apply to quantity samples; workouts and correlations require their appropriate query types and app-side processing.

Local day boundaries must be calculated from the user's calendar and time zone, including daylight-saving transitions where applicable. Do not assume a day is always a fixed 86,400 seconds. Persist the exact interval boundaries and time-zone/calendar context used for each derived daily result.

Sources: [A3, A4, A5].

### 34.4 HealthKit: incremental updates, background delivery and deletion

Use an anchored object query as the durable incremental mechanism for sample-level imports. The initial query returns the matching snapshot; subsequent queries with the saved anchor return new and deleted objects since that anchor. Persist the returned objects and the new anchor atomically in WALKON's local database: commit imported changes and anchor advancement in one local transaction, or replay safely after a crash.

Observer queries can notify the app that matching HealthKit data changed and may be registered for background delivery. The observer notification is a wake-up signal, not a complete change feed. On notification, run the anchored query to obtain additions and deletions, then call the observer completion handler after processing. Background delivery is opportunistic and must not be treated as a real-time guarantee.

Deleted objects are temporary. Apple states they may be purged to reclaim storage. Register for observer background delivery and promptly drain anchored deletions. A deleted object provides the deleted sample UUID; only sync identifier/version metadata is retained in its metadata. Use UUID to remove the corresponding imported copy. If WALKON misses the deletion window or loses its anchor, perform a bounded resnapshot/reconciliation rather than assuming the old local cache is authoritative.

HealthKit allows an app to delete only objects it previously saved, and only while the relevant share authorization permits it. Users can delete any data in Health. Never delete or rewrite third-party samples as part of WALKON cleanup.

Sources: [A6, A7, A8].

### 34.5 HealthKit: provenance and stable identity

For each imported HealthKit sample, preserve its HealthKit UUID, sample type, start/end dates, value/unit, source revision (originating app and version), device metadata when present, and relevant metadata keys. Preserve the distinction between the app that wrote a sample and the hardware device that generated it; either may be absent or different.

For WALKON-created exports, assign stable sync identifiers and monotonically increasing sync versions where supported. Keep a local mapping from WALKON's canonical workout/session UUID to every external HealthKit object UUID. Do not assume timestamps and values form a unique key. Do not infer source priority from app names or device models.

### 34.6 Android Health Connect: permissions and access windows

Health Connect permissions are granular by record type and read/write direction. Declare required permissions in the manifest, request only those the user-facing feature needs, and re-check current grants before each operation because users can revoke them at any time.

Background reads require the additional READ_HEALTH_DATA_IN_BACKGROUND permission and supported feature availability. Historical reads beyond the default 30-day window require READ_HEALTH_DATA_HISTORY and feature availability. Without history permission, reads older than 30 days before the first grant can fail; uninstalling the app revokes permissions, and reinstalling resets the default access window. Android version and Health Connect feature availability affect behaviour.

The permission model is not equivalent to HealthKit's privacy model. WALKON must expose platform-specific permission states and never map them into a falsely identical cross-platform “all health permissions granted” flag.

Sources: [G1, G2, G3].

### 34.7 Health Connect: raw records versus aggregate API

Use readRecords for record-level detail, provenance, workout sessions and incremental reconciliation. For cumulative quantities such as steps, use the Aggregate API rather than summing raw records from all sources. Google explicitly recommends aggregation for cumulative types to avoid duplicate counting.

Health Connect aggregate results apply user-selected app priorities for supported Activity and Sleep data types; duplicate step or distance records can be deduplicated according to user priorities. This deduplication is not universal across all record types: for other types, aggregate results may combine records from all writing apps. Never assume every aggregate is globally deduplicated. Keep aggregate values separate from raw imported rows and retain the query interval and metric identity.

Health Connect records carry metadata including a Health Connect-assigned ID, last-modified time, data origin (package name), device information where supplied, client record ID/version where supplied, and recording method. Recording method distinguishes actively recorded, automatically recorded and manual-entry data. Preserve these fields in the normalized provenance record.

Sources: [G4, G5, G6].

### 34.8 Health Connect: differential changes and deletion

Use the Changes API for incremental synchronization. Obtain a changes token for the specific record types, persist it, then retrieve upsertion and deletion changes and continue through all pages until no more changes remain. Google documents that changes tokens are valid for 30 days; if a token expires, rebuild the relevant local view using a fresh token and a full/bounded read, then resume incremental changes.

Changes API deletion entries expose the record ID but not its type. Either request changes separately per record type or maintain a durable ID-to-type mapping. This mapping is required to correctly remove the corresponding local object.

The documented differential-changes flow is foreground-only; do not assume background reads permission makes the Changes API a background sync channel. Background record reads and foreground differential change tracking are distinct capabilities. Use a foreground reconciliation when the app becomes active, and use background reads only when explicitly authorized and supported for a justified feature.

Sources: [G7, G8].

### 34.9 Cross-platform normalized model

Keep platform-specific raw identity and semantics intact. A normalized observation should contain at least: canonical local row ID and canonical workout/session ID when applicable; platform (HealthKit / Health Connect / WALKON sensor); external record ID and external record type; source app/package or HealthKit source revision; device identity/type where available; measurement type, numeric value, canonical unit and original unit; sample start/end instants and any supplied zone offsets; recording method (manual, active, automatic, unknown); raw versus aggregate designation and aggregate metric/window; created/modified timestamps where available; permission/access state and import timestamp; sync cursor/anchor or token checkpoint separately from the observation; and deletion/tombstone status and reconciliation status.

Keep native source payloads or a lossless representation for fields needed later. Never discard source timestamps, offsets, original units, IDs or recording method during normalization.

### 34.10 Deduplication and source reconciliation policy

1. Session ownership wins for live WALKON recording. The active WALKON sensor/provider selected for the session is the sole live authority for that metric. Platform daily totals remain a separate dashboard value.
2. Platform aggregate wins for platform daily dashboard. Display HealthKit cumulative statistics or Health Connect aggregate results for the selected day. Do not add imported raw samples to that result.
3. Stable external IDs first. Deduplicate imported records by platform + record type + platform external ID. For WALKON exports, use stable app-generated client/sync identifiers where supported.
4. No timestamp-only dedupe. Two valid records may share timestamps and values; timestamp/value similarity is a candidate conflict, not proof of identity.
5. No cross-platform auto-merge by default. A HealthKit sample and a Health Connect record are not assumed to be the same event. If later linking is needed, retain both source identities and record the matching rationale.
6. Overlapping activity records. Preserve both records and their origins. For aggregate display, defer to the platform's documented aggregation/deduplication behaviour. For WALKON session metrics, use the session owner and explicit workout interval, not a sum of platform records.
7. Manual records remain visible as manual. Do not silently promote user-entered steps, distance or workouts to sensor-verified data.
8. Deletion is a first-class change. Apply tombstones to imported copies; never resurrect a deleted record from a stale cache during retry.
9. Idempotent import/export. Each import batch and external write has a durable operation ID. Retry safely only where the platform's IDs/sync identifiers make the effect idempotent; otherwise mark uncertain and reconcile before retrying.
10. Permission revocation stops access. Stop future reads/writes for revoked types, preserve only data WALKON is entitled to retain under its privacy policy, and offer deletion controls.

These are WALKON policy proposals, not platform guarantees.

### 34.11 Time, units and day-boundary rules

Use absolute instants internally for ordering and interval intersection. Retain original zone offsets where the platform provides them. For daily views, derive boundaries using the user's current local calendar/time zone, and recompute the displayed day when the time zone or calendar changes. A workout crossing midnight remains one workout with a time interval spanning two local days; daily aggregates may allocate its samples across days according to the platform's own rules.

Convert to canonical units only while preserving the original unit/value and conversion version. Do not assume all records of a metric have identical sampling cadence or interval semantics. Point measurements, interval samples, cumulative counters and aggregate totals are different data shapes.

### 34.12 Privacy, retention and user control

- Request the minimum types and minimum access window needed for a clearly described feature.
- Keep health data local by default; do not upload raw health records or routes merely because they can be read.
- If cloud backup/sync is later introduced, separately explain purpose, fields, retention, access, deletion and cross-device implications and obtain appropriate consent.
- Provide disconnect/revoke guidance and an in-app way to delete WALKON's local copy and WALKON-authored platform records where authorized.
- Deleting WALKON's local data does not automatically delete platform data, and deleting platform data does not automatically erase WALKON's own copy. Explain these boundaries.
- Never collect unrelated medical categories for a walking tracker. Do not use health data for advertising or unrelated profiling.
- Keep audit logs free of sensitive sample values; log IDs/status/error classes where possible.
- Document retention periods and implement deletion propagation to local caches and any future server copy.

### 34.13 Proposed WALKON synchronization architecture

- Maintain a platform adapter per OS; do not hide important differences behind a lowest-common-denominator interface.
- Maintain separate pipelines for (a) daily aggregates, (b) raw historical import, (c) incremental change feed, and (d) WALKON-originated export.
- Persist per-type permission state, access window, last successful query, last anchor/token, and last full reconciliation time.
- For HealthKit: observer wake-up → anchored query → transactional upsert/tombstone + anchor commit → observer completion.
- For Health Connect: foreground Changes API token drain → transactional upsert/tombstone + next token commit; full/bounded read on first sync or expired token. Background reads only under separately granted permission and supported feature.
- After permission changes, app reinstall, anchor/token invalidation, database restore or detected inconsistency, run a scoped reconciliation.
- Do not block the live workout recording pipeline on health-store availability. Save locally first; platform export remains an independent, retryable outbox operation.
- Keep daily aggregate refresh independent from workout session export.

### 34.14 Acceptance and fault-injection tests

1. HealthKit read permission denied, limited history, no data, and app-owned-only data all produce truthful non-zero/unknown states, never fabricated zero or false denial.
2. HealthKit cumulative statistics match Health app daily totals for controlled datasets with overlapping sources; verify source-separated statistics are not summed.
3. HealthKit observer wake-up followed by anchored additions/deletions is idempotent across process termination before and after local commit.
4. Delete an imported sample in Health; confirm local tombstone and no resurrection after retry. Test delayed observer delivery and missing anchor recovery.
5. Device locked/database inaccessible; app retries later without corrupting cursor state.
6. Health Connect permission revoked between check and read/write; handle failure and update UI state.
7. Test history reads at and beyond the 30-day boundary, including reinstall and Android/Health Connect feature unavailability.
8. Health Connect Changes API multi-page response, expired token, deleted record with unknown type, and token persistence across crash.
9. Verify aggregate step totals with two overlapping source apps and changed user priority; compare aggregate versus raw read to prove no double counting.
10. Verify manual, active and automatic recording methods remain distinguishable.
11. Time-zone change, daylight-saving transition, travel across midnight and workout crossing local midnight.
12. Repeated export, callback loss, retry and local database restore produce no duplicate WALKON-originated platform records.
13. Delete local WALKON data, delete WALKON-authored platform records where permitted, and confirm third-party records are untouched.
14. Confirm live session recording continues and local commits succeed while HealthKit/Health Connect is unavailable.

No numeric acceptance thresholds are invented here; define them in Section 41 using controlled datasets and target-device testing.

### 34.15 Open decisions and evidence gaps

- Exact iOS deployment/API availability and query descriptor choice must be frozen against the selected Xcode/SDK during implementation.
- Verify current Health Connect SDK stable version, feature flags and API-level behaviour at implementation time; the Android Codelab illustrates flows but may lag SDK changes.
- Determine whether WALKON needs any raw historical import beyond daily aggregates and workout-session reconciliation; default is minimum necessary access.
- Define exact HealthKit background-delivery frequency/latency expectations only after device testing; no real-time wake guarantee is assumed.
- Define whether a later cloud service stores any health data; default is no raw health-data upload.
- Validate source-overlap scenarios with real Apple Health and Health Connect datasets, especially user priority changes and mixed manual/automatic records.
- Confirm HealthKit anchor invalidation/recovery behaviour and Health Connect token expiry recovery in fault-injection tests.

### 34.16 Section conclusion

Official documentation establishes the core query, permission, aggregation, metadata and change-feed semantics. The platforms differ materially: HealthKit intentionally hides read-denial state and provides anchored queries with deletion objects; Health Connect exposes granular permission types, a 30-day default history window, aggregate deduplication for selected categories, and a foreground Changes API with expiring tokens. WALKON must preserve those differences, use platform aggregates for daily totals, keep session-owned metrics separate, and reconcile changes with durable IDs and tombstones.

Research complete for Section 34 at documentation level. Implementation, SDK-version freeze, permission UX and device-level validation remain outstanding. No app code/build is authorized by this section.

#### Section 34 references

- [A1] Apple, Authorizing access to health data: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- [A2] Apple, Reading data from HealthKit: https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit
- [A3] Apple, Executing Statistics Collection Queries: https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries
- [A4] Apple, HKStatistics: https://developer.apple.com/documentation/healthkit/hkstatistics
- [A5] Apple, HKStatisticsCollectionQuery: https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquery
- [A6] Apple, HKAnchoredObjectQuery: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
- [A7] Apple, HKDeletedObject: https://developer.apple.com/documentation/healthkit/hkdeletedobject
- [A8] Apple, HealthKit framework object/source metadata: https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework
- [G1] Android, Health Connect data types and permissions: https://developer.android.com/health-and-fitness/health-connect/data-types
- [G2] Android, Read raw data and history limits: https://developer.android.com/health-and-fitness/health-connect/read-data
- [G3] Android, Health Connect data format and metadata: https://developer.android.com/health-and-fitness/health-connect/data-format
- [G4] Android, Get started and aggregate cumulative data: https://developer.android.com/health-and-fitness/health-connect/get-started
- [G5] Android, Read aggregated data and source priorities: https://developer.android.com/health-and-fitness/health-connect/aggregate-data
- [G6] Android, Metadata API reference: https://developer.android.com/reference/androidx/health/connect/client/records/metadata/Metadata
- [G7] Android, Health Connect integration Codelab — differential changes: https://developer.android.com/codelabs/health-connect
- [G8] Android, Changes API example and token-expiry handling: https://developer.android.com/codelabs/health-connect?authuser=00



## 35. Calories and energy expenditure validity

Status: physiological and platform semantics researched; all WALKON estimates remain unvalidated until compared with indirect calorimetry or another defensible reference method.

### 35.1 Define the quantity before displaying it

“Calories burned” is ambiguous. WALKON must distinguish:
- **Resting/basal energy:** energy used to sustain normal physiological function at rest. Basal metabolic rate (BMR) and resting metabolic rate (RMR) are related but not identical measurement protocols; do not label an estimate of one as a measured value of the other.
- **Active energy:** energy attributable to physical activity above rest, under the platform's definition.
- **Gross exercise energy:** total energy expended during the workout interval, including the resting energy that would have been expended during that same time.
- **Total daily energy:** resting/basal plus active and other components as defined by the source. Do not add active energy to a total that already includes it.
- **Food energy intake:** energy consumed, a different data domain and never inferred from exercise output.

Use kilocalories (kcal) in user-facing fitness UI, while preserving source units and conversion metadata. In nutrition contexts “Calories” commonly means kcal; label units clearly.

### 35.2 Apple HealthKit semantics

HealthKit exposes distinct quantity types for activeEnergyBurned and basalEnergyBurned. Apple defines active energy as energy burned due to physical activity and says it should not include resting energy during the same interval. Basal energy represents resting energy used for normal body function. Apple Watch automatically records active-energy samples.

For workouts, Apple documents splitTotalEnergy to divide a workout's total energy into active and resting portions and save each separately. WALKON must not write the same gross workout energy into both active and basal streams, or add an already-gross workout value to daily active energy.

HealthKit samples are cumulative quantity samples and can be condensed/coalesced. Query daily totals with the appropriate cumulative statistics option and interval. Preserve source/device attribution; do not assume an iPhone-only WALKON estimate has Apple Watch's measurement inputs or provenance.

Sources: [A1, A2, A3].

### 35.3 Android Health Connect semantics

Health Connect has distinct interval record types for ActiveCaloriesBurnedRecord and TotalCaloriesBurnedRecord, and an instantaneous BasalMetabolicRateRecord. Its Aggregate API exposes ACTIVE_CALORIES_TOTAL, ENERGY_TOTAL and BASAL_CALORIES_TOTAL for the corresponding records.

These are different records/metrics, not interchangeable names for one “calories” number. Use aggregate reads for daily totals and raw interval records for provenance/workout details. Follow Section 34 source-priority and deduplication rules. Do not sum total energy and active energy together; do not infer total daily energy by adding independently sourced totals without checking interval overlap and record semantics.

Sources: [G4, G5].

### 35.4 Physiological estimation inputs and uncertainty

Energy expenditure is not directly measured by a phone's step counter or GPS. Laboratory reference methods include indirect calorimetry (oxygen uptake and carbon dioxide production) and doubly labelled water for longer-term free-living energy expenditure. Consumer trackers infer energy from proxy signals and model assumptions.

Potential predictors for walking include:
- body mass at or near the activity date;
- height/leg length and gait characteristics;
- walking speed and duration;
- grade/elevation and terrain;
- carried load;
- age and sex variables where a selected validated model requires them;
- heart rate, when a reliable sensor is actually connected;
- fitness/metabolic calibration data, if legitimately available.

No single input set removes individual variation. Heart rate is not a direct calorie meter: heat, stress, hydration, medication, illness, sensor fit and cardiovascular drift can change heart rate independently of mechanical work. Phone-only GPS and accelerometer data cannot measure oxygen consumption.

A systematic review reports that energy-expenditure estimates remain among the least accurate common wearable metrics; a recent review reports substantial errors even in modern devices. Reported ranges vary by device, activity and validation method. Treat any consumer-device calorie value as an estimate, not a precise physiological measurement.

Sources: [R1, R2].

### 35.5 Walking equations: useful but bounded

The ACSM walking metabolic equation estimates oxygen uptake from speed and grade under defined steady-state walking conditions:
VO2 (mL/kg/min) = 3.5 + 0.1 × speed(m/min) + 1.8 × speed(m/min) × grade(decimal).

The equation is a population model, not a personal measurement. It assumes walking conditions compatible with the model and should not be applied blindly to stop-start urban walking, very slow/fast speeds outside its validated domain, irregular trails, stairs, load carriage, or steep grades. Grade input is especially sensitive to noisy elevation; do not feed raw GPS altitude noise into a calorie calculation.

Research has proposed alternative models incorporating height, speed, body mass and grade. One level-walking model found prediction error materially improved when a two-component model was used rather than a single-component speed relationship. A separate meta-regression model has been validated across a broader set of standing/walking conditions in healthy military-age adults, but that population and protocol do not automatically generalize to all WALKON users.

A study in Asian adults developed and cross-validated a body-weight- and sex-based walking/running energy equation, but its own scope and standard error limit universal use. WALKON should not select an equation solely because it was published or fits a demographic label; it must validate the model against the intended user population, device sensors and real-world walking conditions.

Sources: [R3, R4, R5, R6].

### 35.6 Gross versus net energy: avoid double counting

An exercise estimate can represent gross energy during the session or net/active energy above rest. The distinction must be explicit.

If a model returns gross energy, the resting component for the same interval must be separated before writing an active-energy record. If it returns net/active energy, do not subtract resting energy a second time. If the app reads platform daily active energy, do not add the session estimate again when the platform has already incorporated the same workout.

Canonical internal record fields:
- estimate kind: active/net, gross exercise, resting/basal, or total daily;
- value and unit;
- interval start/end;
- model name/version and parameter set;
- body-mass/height input values and their effective dates;
- sensor inputs and data quality;
- source/provenance and whether imported or WALKON-estimated;
- uncertainty band or quality label;
- platform export state and external ID.

### 35.7 WALKON product policy

1. Never display a calorie number as exact or medically authoritative.
2. Separate active session energy from daily total energy.
3. Prefer a platform-provided aggregate for a platform daily dashboard; retain its source identity and definition.
4. For WALKON session estimates, use one documented model version and clearly identify the value as an estimate.
5. Use a fresh, user-confirmed body mass when available; never silently rely on stale profile weight. Missing required inputs should lower confidence or suppress the estimate.
6. Do not invent calorie burn from steps alone. Steps may support activity classification but are not sufficient to determine energy expenditure reliably.
7. Treat HR as an optional model input only when sensor source, quality, sampling coverage and time alignment are adequate. Do not infer HR from a watch pairing state or from sparse historical averages.
8. Do not claim GPS elevation makes calories accurate. Grade estimation uncertainty propagates into the energy estimate.
9. Show “not available” rather than a fabricated zero when required inputs are absent.
10. Never use calorie estimates to make a food allowance, weight-loss promise or health diagnosis.

### 35.8 Calibration and validation plan

Before shipping any WALKON-generated calorie estimate:
- Compare walking estimates with indirect calorimetry under controlled treadmill conditions across several speeds and grades.
- Include flat outdoor routes, inclines, declines, stairs, stop-start walking, varied phone placement and different walking aids/gaits.
- Include diverse age, sex, body-size and fitness groups; avoid tuning only to one developer or one phone.
- Test with phone-only inputs separately from phone plus external HR and wearable-derived energy.
- Validate gross and net energy separately; confirm resting-energy subtraction and daily aggregation.
- Evaluate bias, mean absolute error, percentage error, limits of agreement and individual error distribution, not correlation alone.
- Use held-out participants/devices/routes; prevent model leakage from repeated samples of the same person.
- Set product acceptance thresholds before looking at final test results; suppress or label estimates that fail.
- Re-test after model changes, OS updates, sensor changes and major platform-source changes.

A user-specific calibration feature is a later option, not an assumption for v1.

### 35.9 Acceptance and fault-injection tests

1. HealthKit active and basal energy are shown separately; active excludes resting energy by definition.
2. A HealthKit workout split into active and resting samples does not create duplicate energy totals.
3. Health Connect ActiveCaloriesBurnedRecord and TotalCaloriesBurnedRecord remain separate in reads, aggregates and UI.
4. A day with overlapping watch, phone and third-party sources is not double-counted by WALKON.
5. A workout spanning midnight is attributed to the correct interval and local calendar days.
6. Missing, stale or changed body mass is surfaced and cannot silently reuse an unqualified input.
7. Missing GPS grade, unreliable elevation, sparse HR and sensor disconnection reduce confidence or suppress affected model inputs.
8. Gross energy is never written as active energy without subtracting the rest component.
9. Platform daily aggregate and WALKON session estimate are never added together if they overlap.
10. Test low walking speed, high speed, incline, decline, stairs, stops and unusual gait against reference measurements.
11. Verify kcal/kJ conversion, rounding, zero/negative/overflow validation and unit display.
12. Ensure retrying HealthKit/Health Connect export cannot create duplicate energy samples.

### 35.10 Open decisions and evidence gaps

- Select the v1 WALKON calorie experience: platform-only daily totals, or platform totals plus a clearly labelled WALKON session estimate. Safest default is platform daily totals and no app-generated calorie claim until validated.
- Choose the model only after deciding the supported activity/speed/grade envelope and testing the target population.
- Define how profile mass changes are timestamped and which value applies to each workout.
- Define how uncertainty is communicated without implying unsupported statistical confidence.
- Confirm exact platform write requirements and source-priority behaviour for any future calorie export.
- Determine whether the first release should omit calories entirely until validation; omission is preferable to false precision.

### 35.11 Section conclusion

Energy expenditure is a model estimate unless obtained by a suitable physiological reference method. HealthKit and Health Connect distinguish active, resting/basal and total energy, and WALKON must preserve those distinctions. A phone's steps, GPS and optional heart rate are predictors, not direct calorimetry. The recommended v1 default is to display platform-provided daily energy aggregates with provenance and to defer WALKON-generated calorie estimates until they pass controlled validation.

Research complete for Section 35 at documentation level. No calorie algorithm is selected or implemented; model choice and acceptance thresholds remain open. No app code/build is authorized by this section.

#### Section 35 references

- [A1] Apple, activeEnergyBurned: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned
- [A2] Apple, basalEnergyBurned: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/basalenergyburned
- [A3] Apple, HealthKit workout energy and splitting guidance: https://developer.apple.com/documentation/healthkit/running-workout-sessions
- [G4] Android, Health Connect aggregate data types: https://developer.android.com/health-and-fitness/health-connect/aggregate-data
- [G5] Android, Health Connect data types and calorie records: https://developer.android.com/health-and-fitness/health-connect/data-types
- [R1] Systematic review, wrist-worn tracker measurement accuracy: https://pubmed.ncbi.nlm.nih.gov/42698643/
- [R2] Living umbrella review of consumer wearable accuracy: https://pubmed.ncbi.nlm.nih.gov/39080098/
- [R3] ACSM walking equation and predictive-model review: https://journals.physiology.org/doi/full/10.1152/japplphysiol.00864.2015
- [R4] Looney et al., walking metabolic-rate meta-regression: https://doi.org/10.1249/mss.0000000000001779
- [R5] Prediction and cross-validation of an energy expenditure equation in Asian adults: https://pmc.ncbi.nlm.nih.gov/articles/PMC8439706/
- [R6] Cadence-based metabolic equation for walking: https://pmc.ncbi.nlm.nih.gov/articles/PMC7896743/



## 36. Battery, thermal management and long-session behaviour

Status: platform behaviour and energy-management APIs researched; WALKON has no measured battery baseline yet. All thresholds below are proposed engineering policies, not claims of measured device performance.

### 36.1 The core engineering trade-off

A route recorder must continue collecting enough location data to produce a useful track while the screen is locked, but continuous high-accuracy location, frequent CPU wakeups, radios and a bright always-on display can consume substantial energy. There is no universal “battery percentage per hour” figure: consumption varies with handset, battery age, ambient temperature, cellular signal, GPS visibility, screen brightness, OS version, sensor use, route environment and other running apps.

WALKON must therefore optimize for **minimum work that preserves route quality**, not simply minimize location samples or maximize update frequency. A low-power route with large unobserved gaps is not a successful fitness recording. Conversely, an app that records every raw sensor event, redraws the map continuously and uploads every point immediately wastes energy without necessarily improving the saved route.

### 36.2 iOS: background execution and location

Apple documents that most iOS apps are suspended shortly after entering the background. While suspended, they do not execute ordinary code or receive live location callbacks; Core Location may queue updates and deliver them when the app runs again. A fitness route that requires timely background points must use the supported location background capability and the appropriate Core Location background session/authorization model. This is a specific, user-visible activity, not permission for indefinite background tracking.

Apple's current location-efficiency guidance recommends minimizing location update frequency, stopping location services when no longer needed, and using the newer location update APIs where appropriate. High desired accuracy can engage multiple subsystems (GPS, Wi-Fi, Bluetooth, cellular and other hardware). Use a distance filter suited to walking and the system's stationary indication where supported; do not poll GPS on a fixed tight timer when the system already manages location delivery.

**WALKON policy:**
- Start high-quality location only after the user explicitly starts a walk; stop it promptly on finish/discard.
- Keep a clear recording indicator and persistent session state. Do not use silent audio, fake activity, repeated notifications or unrelated background modes to keep the process alive.
- Use the supported background-location mode only for an active recording. Request only the authorization level needed for the promised locked-screen route experience and explain why.
- Prefer modern Core Location update streams/session APIs when the selected deployment target and SDK support them; retain a tested compatibility path if required.
- Treat queued/delayed location callbacks as possible. Every point carries its original timestamp; sort and validate by event time, not callback arrival time.
- If location accuracy is not improving or the device reports a stationary condition, avoid repeated aggressive requests. Show GPS quality honestly and preserve a gap marker rather than fabricating a straight line.
- A background session is not a guarantee against force-quit, device shutdown, exhausted battery, permission revocation or all system interruptions.

Sources: [A1, A2, A3].

### 36.3 iOS: Low Power Mode and thermal states

Apple exposes Low Power Mode through ProcessInfo and power-state notifications. Apple advises pausing optional work, reducing display updates/animations and reducing network activity when Low Power Mode is enabled. Apple also exposes thermal-state notifications and four broad states: nominal, fair, serious and critical. Apple's guidance is to defer non-urgent work at fair, reduce networking/location/display activity at serious, and reduce or stop power-intensive work at critical.

WALKON must not silently change a user's recorded route into a low-quality route without disclosure. Apply a priority hierarchy:
1. Preserve the active workout's durable local journal and accepted location samples.
2. Keep the minimum location service required for an explicitly active route, subject to OS thermal safety and user-visible status.
3. Defer map rendering, animations, nonessential analytics, cloud uploads, thumbnails and other optional work.
4. Reduce UI refresh cadence and avoid per-point full-screen redraws.
5. At serious/critical thermal conditions, display a clear degraded/paused recording status and follow platform safety constraints; never claim uninterrupted capture if the OS or hardware prevents it.

Low Power Mode is a constraint signal, not a reason to discard the session or assert that GPS is disabled. Test the actual location behaviour on target devices with Low Power Mode enabled. Record the state transition and any observed route gap for diagnostics.

Sources: [A4, A5].

### 36.4 Android: foreground tracking, batching and thermal response

For a user-visible walk that continues when the screen is off or another app is in front, Android's location guidance recommends a foreground service with a persistent notification. High-accuracy updates at a few-second interval can be appropriate for an actively recorded route, but Android explicitly cautions against sustained high-accuracy background requests where they are not needed. Fused Location Provider supports priority, requested interval and maximum update delay. A sufficiently large batching window may let the system deliver several timestamped locations together, reducing app wakeups; batching is device-dependent and not guaranteed.

A route recorder has a different latency need from passive background location. WALKON should use a foreground service for an active workout, request an interval/priority calibrated for walking, and enable batching only when the accepted route-quality envelope remains satisfied. Persist each delivered batch promptly; process timestamps in event-time order. Do not hold a continuous partial wake lock just to wait for GPS callbacks. Android's current battery guidance specifically recommends avoiding redundant wake locks for location callbacks and using local persistence plus WorkManager for deferred processing/upload.

Android exposes thermal status APIs on supported versions. Thermal status ranges from none/light/moderate through severe/critical/emergency/shutdown; device support and implementation vary. WALKON should observe status changes and reduce nonessential CPU/GPU/network work as thermal severity increases. Do not assume thermal headroom is universally available or poll it too frequently.

Sources: [G1, G2, G3, G4].

### 36.5 Sensor and compute duty cycle

- **Steps:** Prefer platform-pedometer summaries or event APIs over continuously sampling raw accelerometer/gyroscope data in the app when raw signals are not required. Core Motion and Android sensor frameworks provide processed motion/pedometer capabilities; do not build an always-on high-rate sensor loop merely to duplicate OS step counting.
- **GPS:** Use one authoritative location pipeline per active session. Avoid parallel CLLocationManager/FusedLocation requests for the same purpose, repeated start/stop thrashing, and multiple independent timers.
- **Heart rate/Bluetooth:** Scan/connect only when the user has selected a compatible sensor or a feature genuinely needs it. Avoid continuous BLE scanning when already connected; use the sensor's supported connection lifecycle.
- **Map/UI:** Keep the route model append-only and update the visible polyline at a throttled cadence. Do not redraw the full map or recompute every historical segment for every new point. Preserve raw accepted points and derive simplified display geometry separately.
- **Persistence:** Batch database transactions in modest bounded groups, but commit often enough that process termination cannot lose a long interval of route data. Avoid per-point synchronous disk flushes and avoid holding a large uncommitted in-memory buffer.
- **Networking:** Do not upload each GPS point individually. Persist locally and upload in bounded batches after a session milestone or when connectivity is suitable. Network retries use exponential backoff with jitter and a cap; no tight retry loop.
- **Timers/wakeups:** No one-second background timer for metrics that can be derived from timestamps or updated when an event arrives. A foreground display timer may update elapsed time while visible; the persisted clock remains based on monotonic/absolute timestamps, not timer tick count.

These are design recommendations. Exact sampling, batching, commit and UI intervals must be tuned against route error and measured energy on representative hardware.

### 36.6 Long-session reliability and degradation

A two-hour walk exposes failures that a short demo does not: memory growth, route-buffer accumulation, SQLite transaction contention, stale timers, duplicate callbacks, clock changes, network reconnect storms, OS suspension, thermal throttling and partial saves.

Required behaviour:
- Persist a recoverable session header and append-only route-point journal; route data must not live only in RAM or UserDefaults.
- Store timestamps, accuracy and sequence/segment identifiers. Make duplicate callbacks harmless through stable event identity or deterministic de-duplication.
- Use bounded in-memory queues and bounded batch sizes. Memory use should remain approximately flat as route duration grows.
- Separate the route capture path from cloud sync, map rendering and analytics. A failed upload must never block local capture.
- Maintain a monotonic elapsed-time basis during a session; retain wall-clock timestamps for display and external interoperability. Detect clock/time-zone changes without changing elapsed duration.
- On pause/resume, create distinct segments and do not bridge the gap. On thermal or OS interruption, record the interruption and resume only through supported lifecycle recovery.
- Finish must atomically commit the local session summary and route journal before optional platform/cloud exports.
- Battery exhaustion or process death must leave the last committed route recoverable. A partially recorded route is better than a lost entire walk, but the UI must mark it incomplete.
- Avoid expensive route simplification, elevation analysis, calorie calculation, map tile prefetch and cloud sync during the active capture critical path.

### 36.7 Battery and thermal measurement methodology

No source supplies a universally valid battery-per-hour acceptance threshold for WALKON. Establish a reproducible baseline rather than selecting an arbitrary percentage.

**Test matrix (minimum):**
- At least three representative iPhone generations and three Android device tiers, including an older supported device; record OS/build, battery health/capacity where available and device temperature context.
- Matched routes and durations: 30 minutes, 60 minutes and a 2-hour endurance session; include open sky, urban canyon/tree cover, intermittent GPS and indoor/no-fix control.
- Screen off/locked after starting, screen continuously on, and screen intermittently checked.
- Normal power and Low Power/Battery Saver modes.
- Strong cellular signal versus weak/no service; Wi-Fi on/off; Bluetooth sensor connected/disconnected.
- WALKON active recording versus a matched baseline with no recording; where useful, compare GPS-only and GPS-plus-sensor variants.
- Repeat each condition at least three times after similar starting battery levels and thermal conditions; randomize order where practical and allow the device to cool between runs.

**Measure and retain:**
- Battery percentage before/after and elapsed wall time; report percentage points per hour, not a universal mAh claim when actual battery capacity/telemetry is unavailable.
- OS per-app battery attribution (iOS Settings > Battery app activity; Android system battery statistics) as supporting evidence, not the sole measure.
- Thermal state transitions and, where available, device temperature/headroom diagnostics.
- Route completeness, accepted point count, timestamp gaps, horizontal accuracy distribution, distance deviation against a measured reference, and session save/recovery success.
- CPU time, wakeups, memory high-water mark, disk writes and network bytes using platform profiling/diagnostics.
- Battery health, ambient temperature, cellular signal and background app load as confounders.
- On iOS, use Instruments/Energy Log during controlled development tests and MetricKit's current metric-reporting APIs for aggregated field diagnostics; MetricKit reports are delayed/aggregated and are not a live per-session battery meter.
- On Android, use Android Studio Profiler/system tracing and Battery Historian or equivalent platform diagnostics where available; correlate app activity with OS battery statistics.

A test is invalid if the phone is charging, starting battery/thermal conditions differ materially, the route differs, or unrelated foreground/background activity dominates the run. Do not infer battery savings from fewer callbacks alone; verify both energy and route quality.

### 36.8 Proposed WALKON energy policy

1. **Idle:** no continuous GPS, high-rate motion sampling, BLE scanning, polling timer or background network loop.
2. **Preparing:** obtain a recent location fix using the least expensive approach that meets the start-screen requirement; show GPS readiness/accuracy and allow the user to start with an explicit quality warning rather than waiting indefinitely.
3. **Active recording:** use the platform-supported active-workout background mechanism; collect only required route and session metrics; persist locally; keep the screen optional.
4. **Low Power/Battery Saver:** defer optional work, reduce map/UI refresh and network activity; preserve core route capture if the OS still permits it. Display the changed operating mode.
5. **Thermal serious/severe:** defer optional compute, reduce rendering and noncritical sensor/network work; do not falsify metrics or silently discard points.
6. **Thermal critical/emergency:** prioritize platform safety; stop/reduce intensive work if required and record an interruption/degraded state.
7. **Paused/finished/discarded:** stop location and sensor services immediately; flush and close local writes; release BLE and other resources. Upload later through a durable queue.
8. **No connectivity:** no repeated wakeups; local recording continues and sync is deferred.

### 36.9 Acceptance and fault-injection tests

1. Start a walk, lock the screen and record for 30, 60 and 120 minutes; compare route completeness and battery use with the controlled baseline.
2. Repeat with Low Power Mode/Battery Saver enabled before start and toggled mid-session; confirm truthful status and no silent data-source switch.
3. Inject or induce thermal-state changes; confirm optional work backs off, core local capture behaves as designed, and interruptions are surfaced.
4. Test open sky, urban canyon, tree cover, tunnels/bridges and long GPS no-fix periods; verify no fabricated distance over gaps.
5. Test weak/no cellular service, Wi-Fi changes and repeated connectivity restoration; local capture must not block or enter retry storms.
6. Verify location batches preserve original timestamps and are ordered/de-duplicated before distance calculation.
7. Test pause/resume, phone call, notification interruption, app backgrounding, app process termination where platform permits, force-quit and device reboot separately; document which cases are recoverable versus explicitly unsupported.
8. Confirm no continuous wake lock, silent audio, one-second background timer, duplicate location pipeline or idle GPS operation.
9. Verify memory remains bounded during a two-hour route; inspect queue depth, DB file growth, transaction latency and CPU time.
10. Force local storage pressure/write errors and verify the app reports a recoverable failure without falsely showing “saved”.
11. Confirm finishing stops GPS, sensors, BLE and timers promptly; verify no lingering background energy use.
12. Reconcile battery/thermal metrics with route quality; no battery optimization is accepted if it causes route loss beyond the thresholds later defined in Section 41.
13. Run repeated endurance trials on the minimum supported iOS and Android devices, with battery health and OS build recorded.

### 36.10 Open decisions and evidence gaps

- Freeze the iOS minimum version and Core Location API path before selecting the exact background session implementation; the current draft targets iOS 26+, but the implementation must be verified against the actual SDK.
- Select Android minimum API, foreground-service type/permissions and Play policy declarations at implementation time.
- Establish measured energy budgets per device tier only after baseline trials; do not promise a fixed percentage/hour across phones.
- Define route-quality thresholds and maximum tolerable gap durations in Section 41 using controlled reference routes.
- Decide the exact low-battery warning threshold and whether the user can continue recording after the warning; preserve user control and clearly state the risk.
- Confirm availability and interpretation of MetricKit and Android thermal/battery diagnostics on the actual supported device matrix.
- Validate whether the chosen location APIs provide acceptable point cadence and route accuracy under Low Power/Battery Saver modes on real devices.

### 36.11 Section conclusion

The correct design is event-driven, local-first and adaptive: run high-quality location only during an explicitly active walk; use OS-managed location delivery and batching where compatible with route quality; avoid unnecessary sensor loops, wake locks, timers, rendering and network activity; respond to Low Power and thermal signals by shedding optional work before critical capture work; and make the session recoverable through durable incremental persistence. Neither iOS nor Android guarantees uninterrupted recording under every force-quit, shutdown, thermal, permission or battery-exhaustion condition. Battery efficiency must be measured together with route completeness and accuracy.

Research complete for Section 36 at documentation/specification level. No battery baseline has been measured on a WALKON build and no implementation is claimed. Section 37 is next.

#### Section 36 references

- [A1] Apple, Accessing the device's location efficiently: https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently
- [A2] Apple, Handling location updates in the background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- [A3] Apple, Core Location framework: https://developer.apple.com/documentation/corelocation
- [A4] Apple, Responding to power notifications (Low Power Mode and thermal states): https://developer.apple.com/documentation/xcode/responding-to-power-notifications
- [A5] Apple, ProcessInfo isLowPowerModeEnabled and thermalState: https://developer.apple.com/documentation/foundation/processinfo
- [A6] Apple, MetricKit performance, power and diagnostic reports: https://developer.apple.com/documentation/metrickit
- [A7] Apple Support, iPhone battery usage and background activity: https://support.apple.com/guide/iphone/understand-iphone-battery-usage-health-iphd453d043a/27/ios/27
- [G1] Android, Optimize location use for real-world scenarios: https://developer.android.com/develop/sensors-and-location/location/battery/scenarios
- [G2] Google Play services, LocationRequest batching: https://developers.google.com/android/reference/com/google/android/gms/location/LocationRequest
- [G3] Android, Thermal mitigation: https://source.android.com/docs/core/power/thermal-mitigation
- [G4] Android, Thermal API and thermal status: https://developer.android.com/games/optimize/adpf/thermal
- [G5] Android Developers, Battery technical quality and wake-lock guidance: https://android-developers.googleblog.com/2026/03/battery-technical-quality-enforcement.html
- [G6] Android, Fused Location Provider and battery-efficient location: https://developers.google.com/location-context/fused-location-provider


## 37. Offline-first storage, sync, conflict handling and export

Research update: 2026-11-08. This section specifies durable capture and later reconciliation of WALKON-owned workout records, route points and explicitly authorized health-store exports. Research only: no backend, sync worker, HealthKit export or device behaviour is claimed to exist.

### 37.1 Governing rule and ownership boundaries

**Local commit first; remote synchronization second.** WALKON must be able to record, finish, inspect and recover a walk when cellular data, Wi-Fi, DNS, the remote API or the user's account session is unavailable. A workout is not dependent on successful cloud upload. Android's official offline-first guidance describes a disk-backed local source of truth for repositories using network resources; higher layers read from local data, while the repository reconciles network state into it. [R1]

Keep three domains distinct: (1) WALKON-owned activity—workout UUID, start/end times, pause/resume events, route segments, accepted route points, session metrics, algorithm version, completion state and user notes; the local database owns it. (2) Platform health-store data—HealthKit workouts/routes and permitted read aggregates; HealthKit remains an external store with independent authorization, identifiers, failure modes and deletion semantics. (3) Remote account data—an optional synchronized copy of WALKON-owned records, never a prerequisite for recording or the only copy.

Do not sync raw HealthKit history wholesale. Export only the WALKON workout and route the user explicitly chooses and authorizes. Daily HealthKit aggregate steps remain platform-derived dashboard data, not a second workout upload or a value to add to session steps.

Generate stable globally unique IDs on-device before any network request. Workout UUID is the aggregate root; route segments, route points, events, export jobs and sync jobs reference it. Retries reuse original IDs and never mint a second workout identity.

### 37.2 Durable local write and transaction boundary

The SQLite proposal in Section 3 remains the baseline; exact library and schema migration choices are implementation decisions.

- Create the workout header and initial session event before sensor capture is considered active.
- Append accepted route points with workout ID, segment ID, monotonically increasing per-workout sequence, event timestamp, coordinate, accuracy metadata and source/algorithm provenance.
- Persist pause/resume/interruption events as durable state transitions.
- Commit route points in bounded transactions. Do not keep a whole route only in memory or hold one transaction open for an entire walk.
- On finish, atomically mark the local workout complete, persist end time/final metrics, close the active segment and create downstream export/sync intents.
- A crash before the final transaction leaves a recoverable active/incomplete workout; after it leaves a completed local workout with pending downstream work.
- Do not report “saved to HealthKit” or “synced” until external success is confirmed and the acknowledgement is persisted locally.

Use foreign keys and uniqueness constraints to reject orphan points and duplicate identities. WAL mode, bounded queues and versioned migrations remain proposals from Section 3; profile write latency, checkpoint behaviour, disk pressure and recovery on target hardware before freezing settings.

### 37.3 Transactional outbox and inbox

A local database commit and an HTTP request cannot be one atomic transaction. Avoid the failure window where the workout commits but the app dies before recording that it needs upload.

Use a transactional outbox. In the same local transaction that finalizes a workout, insert pending outbox rows. Each row includes immutable operation UUID, workout UUID, operation type, schema version, payload reference/content hash, creation time, attempt count, next eligible retry time, last error class and state.

States: pending, inFlight, acknowledged, permanentlyFailed and cancelled. Persist inFlight before sending. On relaunch, stale inFlight rows become retryable only after checking whether the server already accepted the operation. Acknowledgement is a separate durable transaction. Keep payloads reproducible from immutable local records or a versioned snapshot, not a fragile temporary-file pointer.

Use an inbox/deduplication ledger on the receiver for client operation IDs and server-originated events that may be delivered more than once. This gives at-least-once delivery with idempotent effects; it does not claim exactly-once network delivery.

### 37.4 Idempotency, ordering and server contract

Every create/update/export command carries a stable operation ID (idempotency key), workout UUID, child segment/point identity, authenticated account scope established by the server, schema/algorithm version, client event timestamp, sequence number and canonical payload checksum.

The server enforces a database unique constraint on the idempotency key within the correct account/operation scope. Repeating the same key and same canonical payload returns the original logical result. Reusing a key with a different payload is a conflict, never an overwrite. Application-only “check then insert” is race-prone; deduplication and mutation must be protected by a database transaction and uniqueness constraint.

Order operations per workout: create/header before route batches; batches carry sequence ranges; finalize follows all required batches. Do not assume HTTP completion order equals event order. The server rejects, buffers or requests missing sequence ranges instead of silently finalizing an incomplete route.

Route-point batches are immutable and include sequence start/end, point count and content hash. An identical retry is harmless. A correction is a versioned repair/reprocessing operation, not changed bytes hidden under the same operation ID.

### 37.5 Retry classification and network transitions

Connectivity notifications are hints to attempt work, not proof that DNS, TLS, authentication or the WALKON endpoint works.

- **Transient:** offline, timeout, reset, DNS failure, HTTP 408/429 and appropriate 5xx. Retry with exponential backoff, jitter, a maximum delay cap and server Retry-After where supplied.
- **Authentication:** expired/invalid credentials. Refresh only through the supported session flow; otherwise pause account sync and request sign-in when the user returns. Do not loop on 401/403.
- **Permanent validation/schema errors:** 400/422 or incompatible payload. Stop rapid retries, preserve local data and mark for repair/update.
- **Conflict:** 409/version mismatch. Fetch and compare canonical state; apply conflict policy rather than blindly retrying.
- **Rate limit:** respect Retry-After and reduce concurrency.

Persist nextAttemptAt and attempt metadata. Coalesce connectivity changes into one sync coordinator. Never create one timer per record, tight retry loops, repeated wakeups or a request for every GPS callback. Android's official guidance discusses exponential backoff, error classification, queued writes and WorkManager for persistent network-constrained work. [R1]

On iOS, background URLSession supports eligible long-running transfers outside the app process and completion event delivery. It has constraints: HTTP(S), delegate-based event delivery, and uploads from files rather than in-memory data/streams after the app exits. The system may rate-limit repeated background relaunch/transfer scheduling. Prepare durable upload files, use bounded batches and do not rely on one background callback per route point. [R2]

Use BGTaskScheduler for opportunistic refresh/maintenance/sync that the system chooses to run; it is not a precise timer or guarantee of immediate execution. The user-initiated walk capture path must not depend on it. [R3] For future Android, use WorkManager with connected-network constraints and unique work to drain the durable queue; an in-memory coroutine is not a durable sync mechanism. [R1]

### 37.6 Conflict policy

Do not apply generic last-write-wins to fitness records. Device clock skew, delayed uploads and route integrity make wall-clock timestamps an unsafe sole conflict rule.

- **Workout identity/capture:** device creates immutable UUID; duplicate creation is idempotent.
- **Route points/event journal:** append-only, sequence-ordered records. Never merge distinct point streams by timestamp alone. Corrections are versioned and preserve original observations.
- **Final summary:** versioned snapshot derived from the local journal. An explicitly authorized recalculation increments algorithmVersion/revision; it does not silently overwrite prior output.
- **User-editable metadata:** versioned updates. Use field-level merge only where semantics are safe; otherwise preserve both versions and request user resolution.
- **Deletion:** explicit tombstone wins over stale upserts for the same record generation. A stale device must not resurrect deleted content.
- **Account preferences:** separate from workout capture; never block local recording.

Server responses include canonical revision/version and accepted sequence ranges. The client must not apply remote state that discards local pending operations. If two devices record the same real-world walk independently, do not auto-merge on overlapping time/location; preserve both or ask the user to resolve.

### 37.7 Deletion propagation and privacy

Deletion is a first-class sync operation, not an upsert with fields missing.

A local deletion creates a durable tombstone with record ID, generation/revision, deletion time and pending propagation state. Transmit idempotently; server prevents stale retries from recreating the record. Retain only minimum tombstone metadata under a documented policy; never retain route coordinates in a tombstone.

If a user deletes a HealthKit item, use permitted platform change-query mechanisms where applicable and reconcile the local relationship. Do not assume deleting a HealthKit copy automatically deletes the WALKON original or remote copy. HealthKit anchored queries can return new samples and deleted objects with an anchor corresponding to the last change. Persist anchors and advance them only after local reconciliation commits. [R4]

Distinguish deletion of a local WALKON workout, its HealthKit export and its cloud copy. Explain each scope. Export and cloud sync are separately consented; local-only recording remains possible. Do not put precise route coordinates in analytics, crash logs, ordinary push payloads or diagnostic breadcrumbs. Retention periods, account deletion and tombstone lifetime are decisions for Section 39.

### 37.8 HealthKit workout and route export state machine

HealthKit export is separate from cloud sync: it is a platform-store operation with independent authorization and partial failure.

Track stages per workout: localWorkoutCommitted → healthWorkoutPending → healthWorkoutSaved (persist returned workout identifier) → healthRoutePending → healthRouteSaved → healthExportComplete. Failure must identify whether workout creation or route association failed. Never create a second HealthKit workout just because route finalization failed.

Apple's route guide requires permission to share workout and workout-route samples. Its documented sequence is to collect locations, end the workout, save the workout, then finish the route builder to associate the route. The route builder's finish operation requires an already-saved workout; it must be finished before deallocation or accumulated route data is lost. An empty route cannot be finalized. [R5, R6]

Keep the local route journal as durable recovery copy until HealthKit route save is confirmed. The workout coordinator owns the live route builder lifecycle. Do not assume an in-memory builder can be reconstructed after process death unless the platform explicitly supports restoration. If workout save succeeds but route save fails, retain the workout identifier and retry/reconcile the route stage without duplicating the workout. Never write duplicate step samples or upload a HealthKit daily aggregate as a WALKON session. Preserve Section 34's privacy-protected HealthKit read-authorization semantics.

### 37.9 Route upload format and transfer boundaries

The local database remains canonical for route capture. Remote transfer uses versioned bounded batches or a compact immutable file, not one request per point.

Each batch carries workout UUID, segment UUID, sequence range, point count, schema/algorithm version, checksum and timestamps. Server validates sequence continuity, payload size, coordinate ranges, timestamp order and account authorization. Keep raw accepted observations distinct from derived/simplified display geometry.

For background iOS file upload, write a complete immutable export file to app-controlled durable storage, close and validate it, then create a file-backed background URLSession upload task. Keep a manifest linking task identifier, outbox operation ID, workout ID, file hash and lifecycle. Do not delete the source file until transfer is confirmed and server acknowledgement is durable. Rebuild from the local journal if missing/corrupt. Do not build an unbounded in-memory JSON object for a long route.

HealthKit export uses native HealthKit APIs; it is not route upload to a server. These destinations have separate consent and status.

### 37.10 Recovery and reconciliation

On launch/foreground: (1) open and integrity-check the local database; apply migrations before sync; (2) recover workouts left preparing/recording/paused/finishing and never silently mark incomplete sessions complete; (3) recover stale inFlight outbox rows while preserving IDs; (4) inspect persisted background URLSession tasks and map them to outbox operations; (5) resume HealthKit export from its last confirmed stage and query for an already-created workout before creating another when a prior result may have been lost; (6) drain eligible outbox items in per-workout order with bounded concurrency; (7) pull remote revisions/tombstones using a persisted cursor and apply transactionally; (8) persist the cursor only after the received page and effects commit locally; (9) derive sync status from durable state, not transient reachability.

Test every crash boundary: before request, after request leaves device, after server commit, before response, after response but before local acknowledgement, and during acknowledgement commit.

### 37.11 User-visible status and account transitions

Expose clear independent states: Saved on this iPhone; Waiting for connection; Uploading; Synced; Sign-in required; Needs attention; HealthKit export pending; HealthKit export complete; Export failed (retry available).

Do not conflate local save success, HealthKit export, remote upload, server acknowledgement and complete synchronization. A generic connectivity check is not proof that the WALKON API is available.

On sign-out, local workouts remain accessible according to the local privacy policy. Pending account uploads pause until a valid session exists. Bind each outbox row to the account scope that authorized it; account switching must never upload one user's private workout into another account without an explicit migration/reassignment policy.

### 37.12 User export and portability

Provide explicit user-initiated export of their own history. GPX suits route geometry; CSV/JSON can carry summaries, events and provenance. FIT/TCX can be evaluated after format validation and privacy review. Preserve UTC timestamps plus original time-zone context where available, units and coordinate assumptions.

Generate from a consistent database snapshot or immutable workout snapshot. Include a manifest with format version, export time, workout IDs, record counts and checksums. Validate the archive before calling it complete. Do not silently include private notes/photos unless selected.

Cloud sync is not a substitute for independent user export; export does not imply a remote backup exists.

### 37.13 Failure-injection and acceptance tests

1. Record and finish in airplane mode; force-quit/relaunch; verify exactly one complete local workout and route.
2. Toggle Wi-Fi/cellular repeatedly during a walk; capture remains independent of upload.
3. Crash before/after final local transaction; recover as incomplete or complete, never falsely synced.
4. Simulate server commit followed by dropped response; retry same idempotency key; exactly one remote workout.
5. Replay identical route batch repeatedly; no duplicate points; reject changed payload under same key.
6. Deliver batches out of order or omit a sequence range; server must not finalize incomplete route.
7. Expire authentication mid-sync; pause retries, retain local data, no tight 401 loop.
8. Exercise 429/Retry-After, 5xx, timeout, 400/422 and 409; verify correct policy.
9. Delete offline, reconnect a stale device copy; tombstone wins and route coordinates are not resurrected.
10. Interrupt HealthKit workout save, route finalization and acknowledgement persistence separately; resume without duplicate workout.
11. Revoke HealthKit sharing permission before export; local workout remains and export is blocked clearly.
12. Test long routes with thousands of points; bounded memory/request size, stable DB latency and resumable upload.
13. Simulate storage pressure/write failure; app reports local persistence failure honestly and never claims saved.
14. Export and validate manifest, checksums, timestamps, units, point counts and round-trip parsing.
15. Migrate each supported prior schema version; test interrupted migration and corrupt database recovery.
16. Verify sync status after restart, sign-out/in, reboot and prolonged offline operation.

### 37.14 Open decisions and evidence gaps

- Select the remote backend/API contract only after auditing the existing architecture; this research does not mandate a backend vendor.
- Freeze SQLite schema, WAL/checkpoint policy, encryption/file-protection settings and migration tool after device profiling and Section 39 security review.
- Decide whether multi-device editing belongs in v1. A safer first release can make remote history read-only on secondary devices until full conflict UX exists.
- Define batch size, compression, concurrency and retention of acknowledged local route data using measured route sizes and battery tests.
- Verify background URLSession restoration and file-protection behaviour on minimum supported iOS and locked-device state.
- Validate HealthKit export retry/reconciliation and deletion semantics against the target SDK.
- Define cloud retention, tombstone retention, account deletion and export guarantees in Section 39.
- Set performance/fault-injection thresholds in Section 41. This section defines tests, not measured pass results.

### 37.15 Section conclusion

WALKON should use a **local-first, transactionally journaled, at-least-once synchronization design with idempotent server effects**. The device creates stable workout identities, commits route and event data locally, and records pending downstream work in the same transaction. A durable outbox is drained opportunistically with classified retries, backoff, bounded batches and per-workout ordering. The server deduplicates operations under database-enforced unique keys. Route points are append-only; corrections are versioned. Deletions propagate as tombstones. HealthKit workout and route export is a separate staged state machine, never conflated with cloud sync. User export is independent of both.

This is an architecture proposal only. No backend contract, sync implementation, HealthKit export, upload, offline test or device result is claimed. Research complete for Section 37. Next: Section 38 — maps, route display, map matching and location privacy.

#### Section 37 references

- [R1] Android Developers, Build an offline-first app: https://developer.android.com/topic/architecture/data-layer/offline-first
- [R2] Apple Developer Documentation, Downloading files in the background (background URLSession): https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- [R3] Apple Developer Documentation, Using background tasks to update your app: https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app
- [R4] Apple Developer Documentation, HKAnchoredObjectQuery: https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
- [R5] Apple Developer Documentation, Creating a workout route: https://developer.apple.com/documentation/healthkit/creating-a-workout-route
- [R6] Apple Developer Documentation, finishRoute(with:metadata:completion:): https://developer.apple.com/documentation/healthkit/hkworkoutroutebuilder/finishroute%28with%3Ametadata%3Acompletion%3A%29
- [R7] Apple Developer Documentation, HKWorkoutBuilder.finishWorkout(completion:): https://developer.apple.com/documentation/healthkit/hkworkoutbuilder/finishworkout%28completion%3A%29

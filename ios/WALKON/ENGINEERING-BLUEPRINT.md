# WALKON — Engineering Blueprint (Research Draft)

Status: Research draft — NOT final architecture approval
Date: 2026-11-07
Product: WALKON (temporary six-letter product name)
Platform in first release: Native iPhone app (SwiftUI, iOS 17+)
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

The current XcodeGen spec says iOS 17. That target must be re-evaluated before implementation. Apple's WWDC25 video describes the newer iPhone/iPad workout-session experience; the exact deployment availability of the required iPhone-specific APIs must be checked against the SDK's availability annotations and Apple's current sample project. Do not assume that every WWDC25 capability works on iOS 17. The final deployment target should be selected only after this availability audit. The user's current iPhone model and installed iOS version must be included in the device test matrix.

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

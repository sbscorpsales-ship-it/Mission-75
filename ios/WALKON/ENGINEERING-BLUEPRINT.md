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

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

Use a local transactional database for durable activity records; do not treat a single UserDefaults JSON blob as the long-term route database. Choose SwiftData or SQLite after testing migrations, crash recovery and route volume. Initial app data namespace must be WALKON-only and must not import legacy app records.

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

## 10. Open decisions for user review

Do not lock these until the reference-app recordings are reviewed:
- Whether WALKON should record a workout in HealthKit automatically or ask at finish.
- Whether auto-pause is enabled by default for walking.
- Which metrics belong on the live screen.
- Whether music, audio cues or coaching are first-release features.
- Whether routes are private by default and what sharing controls are required.
- Whether a future Android app is in scope and when.
- Final visual identity and permanent app name.

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

**Decision: the first native iPhone release must target iOS 26.0 or later if it uses the new iPhone-native workout-session workflow.** Apple's iOS 26 release notes explicitly state that `HKWorkoutSession` and `HKLiveWorkoutBuilder` workout-session APIs are now available on iOS and iPadOS. This is not an iOS 17 capability. The existing iOS 17 deployment setting is therefore incompatible with the proposed single-path workout engine.

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

**Compatibility trade-off:** choosing iOS 26+ excludes older iPhones that cannot run iOS 26. This is an explicit product reach decision, not an incidental code setting. The current user's iPhone 12 Pro Max must be checked against the supported iOS version and then tested on-device before committing to the target. If that device cannot run iOS 26, we must choose between a legacy fallback engine for older iOS and a newer-device-only release; do not silently downgrade the architecture.

The iOS 17 value in `ios/project.yml` remains unchanged until the user reviews the device compatibility and approves the deployment decision.

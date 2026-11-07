# GATIVX Native Data Layer - Rebuild V2

## Non-negotiable data rules
- Apple Health daily steps are one HealthKit cumulative aggregate for the current local calendar day.
- CoreMotion daily steps are a separate iPhone-only measurement and fallback; never sum it with HealthKit.
- A walk session is a separate interval beginning at the user's Start action and ending at Finish.
- GPS distance is calculated only from accepted CLLocation route points. Daily/manual distance is never relabelled as GPS distance.
- Every measurement carries a source and measured-at timestamp. Missing permission/data is unknown, not zero.
- Cloud writes are idempotent by owner + local date for daily totals and stable UUID for sessions.
- Local history is retained until a cloud acknowledgement is received. Never clear local records on a failed request.

## Current rebuild slice
The HealthKitManager replacement uses a single-day HKStatisticsQuery cumulative aggregate, keeps nil distinct from zero, serializes refreshes, refreshes on observer notifications and app foreground, and never merges CoreMotion values into the HealthKit total.

## Required next implementation slices
1. Isolate CoreMotion daily and session streams in a dedicated service with independent timestamps.
2. Add a durable outbox for cloud writes and acknowledgement-based removal.
3. Add deterministic unit tests for source precedence, local-day boundaries, duplicate session IDs and retry behavior.
4. Sign the iOS app with the owner's Apple Developer team and verify on a physical iPhone.
5. Verify HealthKit permissions and background delivery on device; simulator compilation is not proof.

## Acceptance tests
- Walk with the phone for 2-3 minutes: CoreMotion daily total must increase without a manual entry.
- Connect Health: displayed HealthKit total must match the Health app's current-day aggregate after refresh.
- Start/finish a walk: session steps and GPS route distance must be limited to that interval.
- Kill/relaunch during a walk: recover the unfinished draft without losing accepted route points.
- Go offline then online: queued records sync once, without overwriting unrelated profile or wellness fields.

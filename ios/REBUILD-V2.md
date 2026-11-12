# GATIVX Native Data Layer — Rebuild V2

## Non-negotiable data rules

- Apple Health daily steps are HealthKit cumulative aggregates. Core Motion daily steps remain a separate iPhone-only measurement; never add the two sources together.
- Missing permission or missing samples means unknown, not zero.
- A walk session begins only after the member taps Start and ends when they tap Finish.
- GPS distance is calculated only between accepted route points. Never bridge long gaps, rejected fixes or implausible jumps.
- Daily/manual distance is never relabelled as GPS distance.
- Every measurement carries its source and measured-at timestamp where supported.
- Cloud writes are scoped to the authenticated owner. Daily aggregates reconcile by owner + local date; route sessions use stable UUIDs.
- Local history is retained when cloud writes fail. A route draft is cleared only after a verified local save or explicit user discard.

## Implemented in the current main branch

### iOS

- SwiftUI GATIVX application with HealthKit, Core Motion and Core Location integration.
- HKStatisticsCollectionQuery imports up to 30 local calendar days of measured step totals. Missing days are skipped; today's display is cleared before refresh to avoid stale readings.
- HealthKit observer queries and best-effort background delivery are registered for steps and active energy. iOS controls delivery timing; this is not a real-time guarantee.
- Core Motion daily totals are kept separate from HealthKit totals and synced to a separate table.
- Daily HealthKit steps, active energy and Core Motion totals enter a persistent, per-account local retry queue before network upload. Successful server acknowledgements remove only the exact queued version, so an older in-flight request cannot erase a newer measurement. Pending counts are private to the signed-in account; retries run after sign-in and when the app returns to the foreground.
- GPS rejects inaccurate/stale fixes, implausible jumps and long-gap distance bridges.
- Unfinished GPS route drafts are written atomically to Application Support. Legacy UserDefaults drafts are migrated only after the file write succeeds.
- Native GPS route and activity history are retained locally and synced to the signed-in account.

### Android

- Native Kotlin application with Health Connect read permissions and aggregated daily steps/active calories.
- Foreground location service records while the screen is locked after the member starts a walk.
- GPS points and route drafts are stored using Android Keystore AES-GCM encryption.
- The completed route history is synchronously committed and read back before the active draft is cleared.
- Recording does not start if the initial encrypted route draft cannot be verified.
- Pending routes remain local until account-scoped cloud sync is acknowledged.

### Web/PWA and cloud

- GATIVX v2 is the published default PWA; the previous dashboard remains accessible at `legacy-runtime.html`.
- The v2 home supports daily journal entries, foreground GPS tracking, account-specific local records, cloud sync and Apple Health Shortcut imports.
- Member goals now capture personal purpose and desired feeling. GURU reconnects the member with that purpose and offers a small next action.
- Mission progress counts actual saved check-in days. It does not display a fabricated fitness-achievement percentage.
- Supabase profiles now persist goal type, duration, purpose, desired feeling and timestamps for cross-device restoration.
- Existing daily logs and GPS walks are migrated read-only where supported; source browser records remain untouched.
- Supabase Row Level Security is enabled for the inspected profile, daily-log, activity-session, motion-step and walk-session tables. Health RPC functions exist and execute as invoker.

## Automated validation evidence

As of 12 November 2026:

- iOS GitHub Actions: simulator build passed, packaged permission strings and source HealthKit entitlements passed, unsigned device-targeted IPA build/package passed.
- Android GitHub Actions: GPS/privacy/cloud safeguard checks passed and debug APK build passed.
- Web GitHub Actions: release validation and Playwright mobile browser smoke tests passed, including navigation, account isolation, cloud reconciliation, Apple Health Shortcut import, GPS pause/resume filtering and purpose-linked GURU flow.
- Supabase live project: profile goal/purpose columns are present; the additive migration is applied.

These results validate source builds and automated browser/native build checks. They do not prove that GPS, HealthKit, Health Connect or background execution works on a physical device.

## Remaining release blockers

1. Sign the iOS IPA with a valid Apple provisioning profile and verify whether the HealthKit and HealthKit Background Delivery entitlements are permitted for that signing account.
2. Install and test on the actual iPhone: Core Motion, HealthKit values, lock-screen GPS, app interruption/recovery, offline upload and relaunch persistence.
3. Install and test the Android APK on physical hardware: Health Connect permission, screen-locked GPS, battery restrictions, reboot recovery and cloud sync.
4. Extend the durable daily-sensor outbox to every cloud write type, including route and activity-session uploads, with explicit acknowledgements, network-aware retry scheduling and per-record sync visibility. Daily HealthKit/Core Motion totals are already queued and retried; route/activity history currently relies on local persistence plus retry on sign-in/foreground.
5. Add automated unit tests for local-day/time-zone boundaries, source precedence, route segmentation and retry/idempotency.
6. Enable Supabase leaked-password protection; the current project security advisor reports it disabled.
7. Complete community, challenge, referral, rewards, subscription and partner/wearable integrations.

## Device acceptance tests

- Walk with the iPhone for 2–3 minutes: Core Motion daily steps should increase without manual entry.
- Connect Apple Health: the displayed total should match the Health app's current local-day aggregate after refresh.
- Start and finish a walk: session steps and GPS distance must be limited to that interval.
- Lock the screen during a walk with Always location permission: route updates should continue where iOS permits.
- Interrupt/relaunch during a walk: the unfinished draft should recover without losing accepted points.
- Go offline and reconnect: queued records should sync once without overwriting unrelated profile or wellness fields.
- Repeat on Android with Health Connect and the foreground location notification visible.

## Important platform limitation

A successful unsigned IPA build is not a signed iPhone installation. Free Apple personal-team signing is temporary, and HealthKit entitlements may be rejected by Apple's provisioning service for a free team. A physical iPhone acceptance test and valid HealthKit provisioning are still required before claiming the native iOS app is complete.

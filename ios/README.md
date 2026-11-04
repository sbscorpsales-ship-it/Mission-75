# GATIVX iOS — Native app architecture

Owner: Param IT Solutions, Belgaum, India.

This directory is the native iPhone implementation track. It does not replace the existing GitHub Pages web app.

## Product split

- Existing web app: remains live at https://sbscorpsales-ship-it.github.io/Mission-75/
- Native iOS app: SwiftUI + HealthKit + Core Location.
- Shared account and cloud records: existing Supabase project already configured by the web app.
- Existing localStorage data: remains in Safari until exported from the web app and imported/migrated. It is not automatically visible to a native app merely because both use the same brand.

## HealthKit data flow

1. Ask for HealthKit read access only after the user chooses Connect Apple Health.
2. Query the HealthKit cumulative step total for each local calendar day. Do not add individual samples manually; HealthKit's cumulative statistics query performs source/device aggregation.
3. Register an HKObserverQuery for step-count changes and request hourly background delivery.
4. When HealthKit notifies the app, re-query the day's cumulative total and sync the aggregate to the signed-in user's daily record.
5. Display the last successful sync time and a clear state when HealthKit access, sign-in, network, or background delivery is unavailable.

Background delivery is best-effort and controlled by iOS. It is not a promise of second-by-second updates. The app refreshes on launch/foreground and after observer notifications. Background observer behaviour must be tested on a physical iPhone, not only the Simulator.

## Data compatibility and protection

The web app currently stores daily records in `daily_logs` with a unique `(user_id, log_date)` key and reads `steps` for the dashboard. The migration in `supabase/migrations` adds step provenance and a narrowly scoped RPC. The RPC changes only the step-related columns; it does not replace weight, food, water, sleep, habits, or other user fields.

The existing browser uses localStorage keys including `mission75.logs.v1`, `mission75.gps.sessions.v1`, `mission75.settings.v1`, and `mission75.habits.v1`. Keep those keys and the existing JSON export/import flow intact. Existing device-only records must be exported/imported or explicitly migrated; a Supabase account does not magically upload records that were never synced.

## iOS project setup

Create an iOS App project in Xcode named GATIVX, bundle identifier owned by Param IT Solutions, minimum iOS 17. Add the Swift files under `ios/GATIVX`.

Enable the HealthKit capability and add these Info.plist usage strings:
- `NSHealthShareUsageDescription`: "GATIVX reads your daily step count and walking/running distance to show progress toward your mission."
- `NSHealthUpdateUsageDescription` is not required unless a future feature writes health data. Do not request write access for this read-only step integration.

Add the official Supabase Swift SDK package (supabase-swift) to the Xcode project. Keep the project URL and publishable/anon key in app configuration; never embed a service-role key. Configure the same Supabase Auth project and RLS policies as the web app.

Enable the HealthKit background-delivery entitlement/capability as required by the current Apple developer provisioning workflow. Test authorization, lock-screen/background delivery, app relaunch, time-zone/day-boundary changes, offline retry, and multi-source step totals on a real iPhone.

## Important implementation gates

- Do not ship until the Supabase migration has been applied and RLS/RPC permissions verified.
- Do not assume the current web app's local-only records are in Supabase.
- Do not claim HealthKit permission was granted just because the authorization request completed: HealthKit intentionally limits apps' ability to infer read authorization status.
- Health data is sensitive. Use explicit consent, least-privilege access, secure transport, account deletion/export support, and no advertising use.
- The native app requires macOS with Xcode for signing, running on an iPhone, and App Store/TestFlight distribution. GitHub Pages cannot compile or sign an iOS app.

## Apple references

- HealthKit overview: https://developer.apple.com/documentation/healthkit
- Reading HealthKit data: https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit
- Observer queries and background delivery: https://developer.apple.com/documentation/healthkit/executing-observer-queries
- Daily cumulative statistics: https://developer.apple.com/documentation/healthkit/executing-statistics-collection-queries

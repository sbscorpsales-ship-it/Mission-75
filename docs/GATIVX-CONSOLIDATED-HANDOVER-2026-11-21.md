# GATIVX — consolidated engineering handover

**Prepared:** 21 November 2026  
**Repository:** https://github.com/sbscorpsales-ship-it/Mission-75  
**Working branch:** `feat/gativx-approved-screen-designs`  
**Source revision inspected:** `7b02df7eb1e38b4a09ab283b056dd5f42399b946`  
**Integration PR:** [#108](https://github.com/sbscorpsales-ship-it/Mission-75/pull/108) (open draft)

This handover describes the repository as inspected. It does not represent unfinished items as complete.

## 1. Project entry points

- Web/PWA: `index.html`, `app-v2.html`, `manifest.webmanifest`, `sw.js`
- Native Android: `android/`
- Native iOS GATIVX: `ios/GATIVX/`
- Earlier standalone WALKON reference implementation: `ios/WALKON/`
- Supabase SQL migrations: `supabase/migrations/`
- CI/build workflows: `.github/workflows/`
- Product and design requirements: `PRODUCT_BLUEPRINT_V1.md`, `GATIVX-DESIGN-BACKLOG.md`, `docs/`

GATIVX is the single product. RunJeet is a prior implementation/data source to consolidate, not a separate product. Shree Ram Weekly Fund Manager is unrelated and excluded.

## 2. Current verified build position

- Android workflow run [44897038997](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44897038997): completed successfully (as last checked).
- iOS workflow run [44897038918](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44897038918): still in progress at the last status check. Xcode selection, XcodeGen, project/scheme validation, and first-run auth/portrait/permission preflight passed; the serial iOS unit-test step was still running. Downstream HealthKit checks, tracking checks, simulator build, Release build and IPA packaging were pending.
- No artifact was listed for run 44897038918 at the last artifact check.
- Earlier successful run references in historical acceptance documents are not proof that this current revision passed.
- No signed, physically installed iPhone build or physical-device acceptance result is established by these CI records.

## 3. Implemented foundations documented in source

### Android
The Android README documents native Kotlin/Compose, Supabase email/password auth, Health Connect reads for aggregated steps and active calories, foreground GPS route recording, route quality filters, encrypted local route drafts, account ownership safeguards, and cloud route sync. It also explicitly says background health reads/periodic WorkManager sync and physical-device acceptance are outstanding. Debug APK is not a signed Play Store release.

Main files:
- `android/app/src/main/java/com/paramitsolutions/gativx/MainActivity.kt`
- `SessionVault.kt`
- `WalkOnLocationService.kt`
- `WalkOnStore.kt`

The approved product navigation/design still requires implementation and visual verification on Android; do not assume that a successful debug build means the final approved screen structure is complete.

### iOS
The native GATIVX source includes SwiftUI app/dashboard, HealthKit integration, Core Motion, Core Location route recording, Supabase REST client, local activity persistence and health/activity outbox components. Relevant source:
- `ios/GATIVX/ContentView.swift`
- `ios/GATIVX/Cloud/SupabaseRESTClient.swift`
- `ios/GATIVX/HealthKit/HealthKitManager.swift`
- `ios/GATIVX/GPSRouteRecorder.swift`
- `ios/GATIVX/Storage/ActivitySessionStore.swift`
- `ios/GATIVX/Storage/HealthKitWorkoutOutboxStore.swift`
- `ios/GATIVX/Storage/HealthSyncOutboxStore.swift`
- `ios/GATIVX/Models/`
- `ios/GATIVXTests/` and `ios/GATIVXUITests/`

A CI-generated unsigned IPA, even if successfully packaged, must be signed with a valid Apple provisioning profile before it can be installed. HealthKit entitlement availability must be confirmed during signing. Free Apple personal-team signing is temporary and may not provision HealthKit capabilities.

### Web/PWA
The web/PWA is a separate browser implementation. The root README explicitly warns that the original PWA local-storage tracker is not native Apple Health, reliable background GPS, or Strava-connected. Do not represent PWA functionality as equivalent to native HealthKit/background services.

## 4. Approved dashboard and product requirements

Authoritative design references:
- `docs/GATIVX_IOS_FIRST_ACCEPTANCE.md`
- `docs/GATIVX-FINAL-DAY-NIGHT-DESIGN-LOCK.md`

The approved direction is premium white/soft-neutral Day Mode with neon-green accents and deep charcoal Night Mode, with System/Automatic as default and manual Day/Night/Automatic settings. The five-tab navigation is Home, Activity, Missions, Community, Profile. The Home composition includes brand/profile/notifications, purpose-led greeting, step progress, Today's Mission, real-data metrics, Start Walk, Gati Guru, My Journey and Community Gati. Do not redesign or rearrange without the owner's approval. Metrics with no valid source must show unavailable/permission/syncing states, never fabricated values.

Product consolidation and architecture:
- `docs/CONSOLIDATED_APP_PLAN.md`
- `docs/UNIVERSAL_DATA_HUB_ARCHITECTURE.md`
- `docs/RUNJEET_SOURCE_AND_BACKUP_AUDIT.md`

## 5. Backend and data safety

Supabase project URL and public client configuration are in the iOS source. The repository contains SQL migrations under `supabase/migrations/`. This handover does not assert that all migrations have been applied to the live Supabase project or that deployed RLS/RPC permissions have been verified.

Before release:
1. Review and apply migrations only through an authorized, backed-up deployment process.
2. Verify RLS and RPC grants against a non-production test account.
3. Confirm owner-scoped access for profiles, daily logs, GPS sessions and activity records.
4. Never put a Supabase service-role key in mobile/web client code.
5. Preserve local records and backups; do not clear browser storage or delete RunJeet archives during consolidation.

## 6. Required remaining work / acceptance gates

1. Complete the current iOS CI run and inspect its actual test/build results.
2. Finish and verify the approved dashboard/navigation on each promised platform; Android build success alone is not UI acceptance.
3. Resolve and reproduce the reported Finish & Save / Apple Health write error on a physical iPhone. Confirm local activity persistence independently of HealthKit/cloud upload; a cloud or HealthKit failure must not discard the saved activity.
4. Sign the iPhone app with a profile that supports the required entitlements, then install and test on the owner's iPhone.
5. Verify HealthKit daily totals, workout save, GPS route, lock-screen/background behaviour, app relaunch recovery, offline queue retry, account isolation and no duplicate records.
6. Complete Android physical-device Health Connect and lock-screen GPS testing.
7. Verify web/PWA compatibility and backup import/export.
8. Verify live Supabase migrations, RLS and RPC permissions before release.
9. Record physical-device acceptance in `docs/GATIVX_IOS_FIRST_ACCEPTANCE.md`.

## 7. Windows + iPhone installation notes

The documented Windows route is `ios/ZERO-COST-IPHONE-INSTALL.md`:
1. Obtain the **GATIVX-iPhone-unsigned-IPA** artifact from a successful iOS workflow run.
2. Use Sideloadly from its official website on Windows, connect/unlock the iPhone and trust the computer.
3. Sign with an Apple ID controlled by the device owner; never share credentials or verification codes.
4. Complete device trust/Developer Mode prompts.
5. Confirm the provisioning profile actually includes HealthKit before describing HealthKit as operational.

An unsigned IPA is not directly installable. Free personal-team signing normally expires after seven days and may reject HealthKit capabilities. App Store/TestFlight distribution requires an appropriate Apple Developer account.

## 8. Build instructions

### Android
Use Android Studio/Gradle with JDK 17 and the checked-in Gradle configuration. CI workflow: `.github/workflows/gativx-android.yml`. Debug build output is `android/app/build/outputs/apk/debug/app-debug.apk`.

### iOS
A Mac with Xcode and XcodeGen is required for local native compilation:
```sh
brew install xcodegen
cd ios
xcodegen generate
open GATIVX.xcodeproj
```
CI workflow: `.github/workflows/gativx-ios.yml`. The workflow generates the project, runs unit tests, validates configuration, builds Simulator and iPhone Release targets, and packages an unsigned IPA when all stages pass.

### Web
The web/PWA workflows and deployment configuration are in the repository root and `.github/workflows/`. Existing GitHub Pages hosting is separate from native iOS signing.

## 9. Scope and release honesty

This repository is the source-of-truth handover for the inspected branch. It includes source, project configuration, migrations, workflows, tests, product/design documents and installation instructions. It is not evidence that every feature is finished, that production migrations are applied, or that a signed iPhone release has passed physical-device acceptance.

Do not delete or overwrite the existing project or member data. Keep the approved design lock. Keep the separate Shree Ram Weekly Fund Manager project out of this repository.

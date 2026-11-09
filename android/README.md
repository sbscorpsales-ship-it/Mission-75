# GATIVX Android — Health Connect foundation

This native Android target is the first Health Connect integration for GATIVX.

## Implemented in this milestone

- Native Kotlin / Jetpack Compose Android application shell.
- Health Connect availability check and user-controlled read permissions.
- Aggregated daily steps and active-calorie reads (aggregation is used to reduce duplicate-source counting).
- Supabase email/password sign-in against the existing GATIVX project.
- Member-owned `daily_logs` upsert using the signed-in access token and existing row-level security.
- Refresh-token retry after an expired access token.
- Explicitly omits missing measurements instead of writing estimated zeros.
- Android CI builds a debug APK and uploads it as a workflow artifact.

## Current limitations — not a public release yet

- The access/refresh token pair is held in memory for this first build. The member must sign in again after closing the app; encrypted persistent session storage is a follow-up.
- Health data is read on demand while the app is in the foreground. Background reads and periodic WorkManager sync are not included yet.
- Native GPS foreground-service tracking is not included yet.
- No Android device/emulator acceptance test has been completed.
- The debug APK is not a Play Store release or a signed production bundle.

## Build

The `GATIVX Android CI` workflow builds `android/app/build/outputs/apk/debug/app-debug.apk` on GitHub Actions and publishes the APK as a short-retention artifact.

Health Connect is supported on Android 9+ devices with a compatible provider. The app checks provider availability at runtime and asks the member to grant read-only permissions for Steps and Active Calories Burned.

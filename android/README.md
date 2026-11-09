# GATIVX Android — Health Connect foundation

This native Android target is the first Health Connect integration for GATIVX.

## Implemented in this milestone

- Native Kotlin / Jetpack Compose Android application shell.
- Health Connect availability check and user-controlled read permissions.
- Aggregated daily steps and active-calorie reads (aggregation is used to reduce duplicate-source counting).
- WalkOn foreground GPS route recording designed to continue with the screen locked, with a persistent notification and explicit stop control.
- GPS quality filtering: reject fixes worse than 50 m accuracy, reject jumps over 150 m or speeds over 8 m/s, and break route segments after gaps over 30 seconds.
- Encrypted local route drafts and history using an Android Keystore AES-GCM key.
- Account ownership captured at recording start; routes are only uploaded to the same account. Offline routes require an explicit assignment before upload.
- Cloud route backup uses the existing `sync_walk_session_route` RPC with an unknown step count, not an invented zero.
- Supabase email/password sign-in against the existing GATIVX project.
- Member-owned `daily_logs` upsert using the signed-in access token and existing row-level security.
- Refresh-token retry after an expired access token.
- Explicitly omits missing measurements instead of writing estimated zeros.
- Android CI builds a debug APK and uploads it as a workflow artifact.

## Current limitations — not a public release yet

- Supabase access/refresh tokens are encrypted at rest using an AES-GCM key held by Android Keystore. Signing out clears the encrypted local session and attempts server-side token revocation.
- Health data is read on demand while the app is in the foreground. Background reads and periodic WorkManager sync are not included yet.
- The route preview is a GPS trace, not a street-map basemap. Map tiles / map matching are a later enhancement.
- No physical Android device acceptance test has been completed; screen-locked tracking must be validated on real Android hardware and OEM battery-management settings.
- No Android device/emulator acceptance test has been completed.
- The debug APK is not a Play Store release or a signed production bundle.

## Build

The `GATIVX Android CI` workflow builds `android/app/build/outputs/apk/debug/app-debug.apk` on GitHub Actions and publishes the APK as a short-retention artifact.

Health Connect is supported on Android 9+ devices with a compatible provider. The app checks provider availability at runtime and asks the member to grant read-only permissions for Steps and Active Calories Burned.

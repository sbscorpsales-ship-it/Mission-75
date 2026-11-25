# GATIVX Android build validation — 25 November 2026

## Purpose

This draft change requests an isolated Android CI build of the current GATIVX Android source so that a debug APK can be produced for fresh-device testing. It does not claim that Android is feature-complete or customer-accepted.

## Source baseline

- Repository: sbscorpsales-ship-it/Mission-75
- Base: main
- Android application ID: com.paramitsolutions.gativx
- Version: 0.1.0 (versionCode 1)
- Minimum Android API: 28
- Target Android API: 36
- Build type requested by current CI: debug APK

## Current implementation boundaries

The current Android source contains:
- Email account sign-up/sign-in and Supabase session handling
- Health Connect read flow for steps and active calories
- WalkOn GPS foreground service and local route persistence
- A feature hub whose own labels mark several areas as Testing or Coming soon

The presence of these code paths does not prove they work on a physical Android phone. The current screen is an early-access/test surface, not evidence that the complete approved five-tab GATIVX experience is delivered.

## CI acceptance

The Android CI workflow must:
1. Run the WalkOn source safeguard script without failures.
2. Compile the Android project using the configured Gradle and Android SDK.
3. Produce `app-debug.apk`.
4. Upload the artifact as `GATIVX-Android-debug`.

A successful CI build proves compilation and the source safeguards only. It does not prove installation, Health Connect permission, sensor accuracy, background GPS, account sync, or customer acceptance.

## Fresh-device acceptance required

On a clean Android phone, record:
- Manufacturer/model and Android version
- APK artifact/run ID and SHA-256
- Install and first-launch result
- Account registration/sign-in result
- Health Connect availability and permission result
- Steps/active-energy source and timestamp
- GPS start, screen-locked continuation, finish and local save
- Cloud sync result and duplicate/loss checks
- Screenshots or screen recording for failures

## Release status

**Not accepted for release.** This build is for controlled engineering/customer testing only. Do not describe the full GATIVX Android product as complete based on this APK.

# GATIVX 3-Day Sprint Report

## 2026-11-28 — engineering checkpoint

### Android — Motorola / POCO C65 common native build

- Working branch: `fix/gativx-design-c-purpose-explore-20261128`
- PR: #171 (draft; not merged)
- Current source head at checkpoint: `8e2165df1be47d7720a88c6e3eceb3bd3fd2c41d`
- Changed production code: `android/app/src/main/java/com/paramitsolutions/gativx/WalkOnStore.kt`
  - A completed activity with measured session steps is now retained even when GPS produced no route points.
  - If neither GPS points nor measured steps exist, the active encrypted draft is retained for retry instead of being cleared.
  - Account-ownership and cloud-sync marker writes now report read-back verification failures rather than silently continuing.
- Added pure rule `WalkOnSessionRules.kt` and three JVM regression tests in `WalkOnSessionRulesTest.kt`.
- Added JUnit dependency and CI execution/reporting for `:app:testDebugUnitTest`.
- Added four static safeguards covering step-only saves, active-draft retention, ownership-write verification and sync-marker verification.
- CI run #213 on source commit `f3982a4b021716142169ffa3659dcea73ab657d5`: SUCCESS. Android JVM test task, static safeguards and debug APK build all succeeded. APK artifact #15264465201 was uploaded. This run preceded the final test-count summary step.
- CI run #214 on current source/workflow head `8e2165df1be47d7720a88c6e3eceb3bd3fd2c41d`: IN PROGRESS at report time; it includes a new step that fails if JUnit XML reports are absent and prints exact test counts.
- No Motorola or POCO C65 physical-device test is claimed. The same APK is intended for both Android handsets, but installation/update signing compatibility must be checked before overwriting an existing install.

### iPhone 13 — native iOS permissions and daily step visibility

- PR #107 and its branch were not modified.
- Created stacked draft PR #173 from the exact PR #107 head:
  - Branch: `fix/gativx-ios-health-permission-onboarding-20261128`
  - Source head: `2feb6f23cb0a9ea7c43b8e755c3e3b5df19935a6`
  - Base: `feat/consolidated-gativx-runjeet`
- Changed `ios/GATIVX/ContentView.swift` to expose two separate, explicit first-run permission actions: Connect Apple Health and Enable Motion & Fitness.
- The Motion action invokes the existing daily Core Motion pedometer path only after the member taps it. No permission is silently granted or requested without a user action.
- Added stable accessibility identifiers and UI-test assertions for both actions.
- CI run #727: IN PROGRESS at report time. Project generation and first-run validation steps passed; XCTest and subsequent build steps were still running.
- Latest completed iOS baseline run #726 (PR #167 diagnostics branch): 85 unit tests + 13 UI tests passed, 0 failures. Runtime frame warnings were still present in the dashboard/Guru keyboard tests; root cause not established and not marked fixed.
- The CI-generated iPhone IPA is unsigned. No physical iPhone 13 installation or HealthKit runtime acceptance is claimed.

### Device acceptance matrix

| Device | Native path | Current evidence | Acceptance |
|---|---|---|---|
| Motorola Android | Android / Health Connect / WalkOn | Android CI build and JVM/static checks; run #214 pending | Not device-tested |
| POCO C65 Android | Same Android APK / Health Connect / WalkOn | Android CI build and JVM/static checks; run #214 pending | Not device-tested |
| iPhone 13 | iOS / HealthKit / Core Motion / GPS | PR #173 permission-onboarding change; run #727 pending | Not device-tested |

### Blockers and safety controls

- The phones are not connected to this engineering environment, so physical sensor readings, OS permission dialogs, GPS lock, background behavior and real Health Connect/HealthKit data cannot be observed remotely.
- Android debug APK signing must be stable and compared against the installed app before an in-place update. Do not uninstall the current app or clear app data as a workaround.
- iOS requires a valid signing certificate and provisioning profile for direct installation. The current CI IPA is unsigned.
- PR #107 remains untouched; PR #112 remains unmerged; PR #171 and PR #173 remain draft/unmerged. No production deployment or merge was performed.
- Device acceptance remains pending until a real Motorola, POCO C65 and iPhone 13 test records model, OS, build/commit, permission state, test steps, results and logs.

### Next engineering actions

1. Complete Android run #214 and record exact JUnit counts, safeguard counts, APK artifact ID and hash.
2. Complete iOS run #727; inspect the test report and confirm both welcome permission controls are present.
3. Resolve Android stable internal signing and iOS signing/provisioning before requesting in-place installation.
4. Continue the iPhone 13 HealthKit/Core Motion and Finish & Save verification; do not add daily step samples to HealthKit without a deduplication-safe design.
5. Keep all device statuses at Not device-tested until physical evidence exists.


## 2026-11-28 — CI follow-up checkpoint

- Android run #213 (`46146649495`) completed successfully on the source code containing the persistence fix and JVM tests: `:app:testDebugUnitTest` succeeded, all 32 static safeguards passed, `:app:assembleDebug` succeeded, and APK artifact #15264465201 was uploaded.
- Android run #214 (`46146806480`) ran the exact JUnit XML summary step successfully: **3 tests, 0 failures, 0 errors, 0 skipped**. All 32 static safeguards also passed. The run was subsequently cancelled before its APK build/upload stage, so it is not counted as a complete build. Run #213 remains the completed APK build for the same application source.
- iOS run #727 (`46146738909`) remains in progress. Project generation, scheme validation and the first-run permission/static validation step passed. XCTest and later packaging stages have not yet reported completion.
- PR #171 current branch also contains this append-only report; latest report commit: `3e9f3f7406b5d08ddb620dc4b3e4b42f09087302`.
- No physical device acceptance is claimed for Motorola, POCO C65 or iPhone 13.


## GATIVX Self-Diagnostic & Test Report — 2026-11-28 12:55 UTC

### Verified Android artifact inspection

- Source/PR: #171, working branch `fix/gativx-design-c-purpose-explore-20261128`
- Completed build: Android CI run #213 / `46146649495`
- Artifact: `GATIVX-Android-debug.zip`, artifact ID `15264465201`
- Artifact archive SHA-256 independently checked after download: `6dee85fa0bc4ea67ef96143474b9643509e71225b8d7f6c36c554595568c1f57`
- Archive contains one file: `app-debug.apk`, 29,676,176 bytes.
- Extracted APK SHA-256: `dcd795be6e87af84a7f07002a2e63921682b9ee724de3bf5604cb45458d98cfe`
- Package contents and archive integrity were inspected. APK certificate fingerprint / installed-app signer compatibility were **not** verified in this environment because Android SDK `apksigner` is unavailable here. Do not treat the archive hash as a signing-certificate fingerprint.
- Do not uninstall existing Motorola or POCO C65 installations or clear application data to work around a signer mismatch.

### Android automated checks

- Completed run #213: JVM unit-test Gradle task succeeded; debug APK built and uploaded.
- Separate exact JUnit XML summary in run #214: **3 total, 0 failures, 0 errors, 0 skipped**.
- All **32 static safeguards** passed in run #213 and were repeated successfully in run #214 before its cancellation.
- Run #214 was cancelled after the JUnit summary and before the remaining safeguard/build/upload steps. It is not counted as a completed APK build.
- No real Android handset was attached to CI; sensor accuracy, Health Connect permission grant, screen-off tracking, GPS, OEM battery optimization and local save/read-back remain physical-device acceptance items.

### iOS automated checks

- PR #173 / CI run #727 remains in progress at the latest check.
- Completed stages: checkout, Xcode 26 selection, XcodeGen installation, project generation, scheme validation and first-run permission validation.
- XCTest and all subsequent entitlement/build/package stages have not yet reported completion.
- No iPhone 13 was attached to CI. HealthKit authorization, Core Motion delivery, background behavior, actual daily-step display and Finish & Save read-back remain device acceptance items.
- Current IPA path remains unsigned for direct handset installation unless a separate signing/provisioning step is completed.

### Self-diagnostic outcome

- Android activity-save fallback: **CI-tested** (three focused JVM cases plus 32 static safeguards).
- Android debug APK artifact: **built and archive hash verified**.
- Motorola installation / runtime tracking: **Not device-tested**.
- POCO C65 installation / runtime tracking: **Not device-tested**.
- iPhone first-run permission controls: **CI static validation passed; XCTest pending**.
- iPhone 13 HealthKit / Core Motion runtime: **Not device-tested**.
- Cross-platform account isolation, sync, background tracking and sensor values: **not accepted solely on the basis of this report**.

### Immediate next actions

1. Complete iOS run #727; inspect XCTest result bundle, runtime diagnostics and IPA packaging.
2. Verify Android APK signer with Android `apksigner` and compare it with the currently installed app before any in-place update.
3. Obtain a correctly signed iOS build before installation on iPhone 13.
4. Run and record the same walk/save/read-back sequence on Motorola, POCO C65 and iPhone 13, separately recording OS permissions, sensor readings, GPS availability, foreground/background state, saved history after relaunch and cloud sync.
5. Keep the three physical-device statuses as **Not device-tested** until this evidence is recorded.

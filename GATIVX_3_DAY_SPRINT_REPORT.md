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

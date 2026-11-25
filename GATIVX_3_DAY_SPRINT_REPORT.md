# GATIVX 3-Day Engineering Sprint Report

**Last updated:** 2026-11-25 21:53 IST (16:23 UTC)  
**Repository:** sbscorpsales-ship-it/Mission-75  
**Audit branch:** audit/gativx-completion-gap-ledger-20261125  
**Primary repair branch:** fix/gativx-ui-test-guest-reset  
**Primary repair head:** b6c04d41dc67bd191ed0cf8966331eb5661a9887  
**Primary PR:** [#112](https://github.com/sbscorpsales-ship-it/Mission-75/pull/112), open, draft, unmerged  
**Finish & Save PR:** [#114](https://github.com/sbscorpsales-ship-it/Mission-75/pull/114), open, draft, unmerged  
**Protected consolidation PR:** [#107](https://github.com/sbscorpsales-ship-it/Mission-75/pull/107), open, draft, untouched

## Release verdict

**NOT RELEASE-READY.** The repository contains real native iOS activity, persistence and HealthKit code, an Android Health Connect/WalkOn foundation, a browser-based Web Hub and Supabase integration. It does not yet contain the complete approved cross-platform product. Several core modules remain explicit placeholders, Android is an early-access shell, the web information architecture differs from the locked native experience, and no signed iPhone install, physical-device acceptance or production release has been evidenced.

No pull request has been merged.

## Status definitions

- **Verified:** direct test/build evidence exists for the exact source revision and stated scope.
- **Implemented-but-unverified:** relevant code exists, but required end-to-end, live-backend or device proof is missing.
- **Missing:** absent or explicitly presented as a placeholder.
- **Blocked:** completion/acceptance requires external credentials, hardware, account access or an owner-controlled release action.

## Traceable product gap ledger

| Area | Status | Repository evidence and remaining gap |
|---|---|---|
| iOS account sign-up/sign-in/password recovery | Implemented-but-unverified | Supabase REST auth endpoints, local-only entry and password recovery code exist. No live-account acceptance or email/OTP verification evidence. |
| First-run onboarding | Missing | Welcome/auth exists, but there is no complete guided first-run journey covering goal, purpose, preferences, permissions and mission setup end-to-end. |
| iOS Design C dashboard | Implemented-but-unverified | Native dashboard contains the approved step ring, metrics, mission, Guru, journey and community sections. UI test evidence exists on another repair SHA; physical iPhone visual comparison remains outstanding. |
| iOS daily activity/Health metrics | Implemented-but-unverified | Core Motion and HealthKit code reads daily metrics and separates daily totals from workout sessions. No physical iPhone data-parity or background-delivery acceptance. |
| iOS GPS activity | Implemented-but-unverified | Core Location recorder includes route segmentation, draft persistence, pause/resume and recovery. Screen-locked/background route behaviour has not been verified on the owner's iPhone. |
| iOS Finish & Save | Implemented-but-unverified | Local history and HealthKit retry/outbox code exist. The six-file recovery/coalescing patch is on PR #114, not integrated into PR #112. Its 13 regression tests passed on CI #628, but a separate run on the same SHA had a UI timeout. No physical-device save/export test. |
| Apple Health workout export | Implemented-but-unverified | HealthKit workout export and retry queue exist, with unit coverage. A signed app carrying the HealthKit entitlement and an actual iPhone export/read-back are still required. |
| GATIVX Guru and 30/90/180/365-day journey | Implemented-but-unverified | Goal, purpose, emotion, next-action and journey logic exist; the 8 goal/journey unit tests passed in CI #628. iOS values are locally persisted; cross-device cloud persistence is not proven. |
| Missions | Missing | iOS currently exposes one fixed “Today · Consistency” mission and a step-progress view, not a goal-linked mission engine with member-created missions, milestones and reviews. |
| Community | Missing | iOS explicitly gates the feed/shared missions. No live community feed, groups, sharing, moderation, blocking or reporting. |
| Profile | Implemented-but-unverified | Account identity, local photo, appearance, motion/location and Health settings exist. Profile navigation/photo-picker candidate fix has not yet received a clean passing full UI run. Photo is local-only. |
| Notifications | Missing | iOS explicitly states notifications are inactive; no delivery pipeline or member notification controls are implemented. |
| Apps hub | Missing | No Apps destination in the current five-tab iOS shell. |
| Android authentication | Implemented-but-unverified | Supabase email/password auth, encrypted Android Keystore session storage and refresh-token handling exist. No phone OTP or physical-device auth acceptance. |
| Android Health Connect | Implemented-but-unverified | Aggregated Steps and Active Calories reads are present. Reads are on-demand/foreground; background Health Connect sync is not implemented. |
| Android WalkOn GPS | Implemented-but-unverified | Foreground location service, route filtering, step-counter hook, encrypted route history and cloud RPC exist. No emulator or physical Android acceptance. |
| Android remaining product modules | Missing | Android feature hub labels Home/Activity/Profile as available for testing, Mission as testing, and Guru/Community/Motion 3D/Rewards/Referrals/Settings as coming soon. It is not the complete approved GATIVX app. |
| Web Hub | Implemented-but-unverified | app-v2.html contains account auth, local journal, goals, browser GPS, Guru and Supabase sync. It has no complete Community/Profile/Notifications/Apps experience and browser GPS is not native background tracking. |
| Cross-platform design parity | Missing | Current web navigation is Home/Journey/Record/Walk/Coach; Android is an early-access feature hub; iOS uses Home/Activity/Missions/Community/Profile. The approved design documents also conflict on tab naming. Do not redesign; reconcile the IA under owner-approved Design C before visual parity work. |
| Shared Supabase backend and sync | Implemented-but-unverified | REST clients, owner-scoped RPCs, RLS migrations, daily logs, walk sessions and retry outboxes exist. The tracked repository has incremental migrations but no complete baseline schema/config/test harness proving a fresh environment can be reproduced. Live migration state and conflict behaviour are not verified. |
| Universal Data Hub | Missing | The architecture document is a proposal. No complete provider/device registry, canonical raw-measurement store, reconciliation audit, BLE adapter suite or manufacturer API connector is present. |
| Security and privacy | Implemented-but-unverified | Member-scoped RLS and encrypted local Android tokens/routes are present. No independent security assessment, live tenant-isolation test, complete data-export/account-deletion workflow or operational audit review. |
| Nutrition, hydration, sleep and strength | Missing | Web has basic weight/water/protein journal fields. A complete food diary, nutrition analysis, measured sleep integration and strength-training programme are not present across platforms. |
| Motion 3D route replay | Missing | No 3D route playback/flyover implementation. |
| Referrals, subscriptions, learning rewards, admin and moderation | Missing | Product blueprint defines these modules; the audited repair branch does not contain the required end-to-end systems. |
| iOS CI/release | Implemented-but-unverified | XcodeGen, simulator build, unsigned Release build and IPA packaging work in recorded runs. Full UI suite is unstable; current full-suite run is pending. Unsigned IPA is not installable. |
| Android CI/build | Verified (CI scope only) | CI #168 built the debug APK and passed the WalkOn source safeguard script. This proves compilation/static safeguards, not installation, sensors, Health Connect or customer acceptance. |
| Web CI | Implemented-but-unverified | Web run #411 passed on SHA e005c1a..., but that is not the current PR #112 head and the web file differs from the audited repair branch. No current-head web smoke result. |
| Signed iOS installation/physical acceptance | Blocked | Requires a valid Apple Developer signing identity and provisioning profile with HealthKit capability, then owner iPhone testing. |
| Android device/production acceptance | Blocked | Requires emulator/physical-device validation, a signed release bundle and owner-controlled Play Console/release configuration. |
| Web production deployment | Blocked | No verified production Pages deployment/URL and live-backend acceptance were found for the audited repair head. |
| Data export and account deletion | Missing | No complete member-facing export and deletion workflow was found in the audited implementation. |

## Latest repository and PR state

| Item | Observed state |
|---|---|
| PR #112 | Head b6c04d41dc67bd191ed0cf8966331eb5661a9887; base feat/consolidated-gativx-runjeet; open/draft |
| PR #114 | Head 87318182360d4369ea2f7a773a27dd3fa3e7c558; open/draft; its recorded base is the older PR #112 commit fa92bb43... |
| PR #114 base freshness | Current PR #112 head is 7 commits ahead of the recorded PR #114 base. Refresh/stack PR #114 only after the current iOS validation stabilises; do not merge automatically. |
| PR #107 | Open/draft at c19bdbd...; not edited or merged in this audit |
| Other work | PRs #110 (Android build validation), #108 (approved dashboard), #100 (auth recovery), #97 (target progression), #90 (sleep), #102 (family/device identity) and #1 (data hub) remain open. Review each diff before deciding what belongs in the consolidated product; do not assume every open PR is integrated. |

## CI evidence and exact outcomes

### iOS

- **Run #628 — PASS** on source SHA 87318182360d4369ea2f7a773a27dd3fa3e7c558: 71 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; simulator build passed; unsigned Release build and IPA packaging passed. This is valid evidence for that source SHA, not proof that the current PR #112 head is green. [Run #628](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633053186)
- **Run #629 — FAIL** on the same source SHA: 71 unit tests passed, 0 failed. The dashboard navigation UI test timed out while evaluating the Profile tab selection/query at GATIVXDashboardUITests.swift:295; the second UI test began but the 40-minute XCTest step timed out. Simulator build, unsigned Release build and IPA packaging passed; aggregate release gate failed. The logs do not prove the exact underlying cause of the UI-query timeout. [Run #629](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633166732)
- **Run #634 — FAIL** on PR #112 SHA 2a49e849...: the old branch-specific workflow ran only one UI test; the XCTest runner process was killed before it established its test connection. No XCTest case result was produced. Simulator build and unsigned Release/IPA packaging completed, but the aggregate gate failed. [Run #634](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45645392450)
- **Runs #631–#633 — CANCELLED**; no passing test result can be inferred from them.
- **Run #635 — TEST STEP DID NOT EXECUTE** on SHA 9ce45fd...; validation was cancelled while the follow-on simulator build was still running. It is not a test result.
- **Run #636 — QUEUED** on current PR #112 head b6c04d41.... This is the first run after restoring full-suite execution; no result is available at report time. [Run #636](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652420651)

### Android

- **Run #168 — PASS** on d0dbfb67377a298f90bc732a1c16d46546bef185: WalkOn static safeguards passed, Gradle debug APK build passed and APK artifact upload passed. The Android code tree is the same as the audited PR #112 tree; the comparison showed only android/BUILD_ACCEPTANCE.md added on that validation branch. No emulator/physical-device test was run. [Run #168](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45557738344)
- An isolated Android sync-acknowledgement correction is in branch feat/gativx/android-sync-ack-20261125, current head 19c679a7f2ef675176c0009148865563fca2fd00. It makes a failed/unreadable local encrypted sync marker throw into the existing retry/error path rather than silently allowing “backup complete”; a static safeguard was added. **Run #171 — PASS on the final revision:** the new sync-acknowledgement safeguard passed, Gradle debug APK build passed and artifact upload passed. This is CI/source/build evidence only; no Android emulator or physical-device acceptance. [Run #171](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476) · [Debug APK artifact](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476/artifacts/15042071077) [Run #171](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476)

### Web

- **Run #411 — PASS** for static checks and Playwright mobile browser smoke tests on SHA e005c1a512d93a5715b9b130e7eea019a2cf5ffe. That SHA is not the current PR #112 head; app-v2.html differs by 32 changed lines in the branch comparison. The smoke test uses a mocked Supabase client and blocks external network calls; it is not live-backend or production acceptance. [Run #411](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44889592176)

## Engineering changes made in this sprint run

1. **iOS CI test narrowing removed.** Commit 9ce45fd6a00a22ed6cbccb308c900f805a48ad0e removed the branch-specific -only-testing filter from .github/workflows/gativx-ios.yml. Commit b6c04d41dc67bd191ed0cf8966331eb5661a9887 corrected the step label. The next run is pending; no test pass is claimed.
2. **Android sync acknowledgement hardening.** On isolated branch feat/gativx/android-sync-ack-20261125, WalkOnStore.markSynced now throws if local history is unreadable, the uploaded route cannot be found, or the encrypted synced marker cannot be written and read back. The existing caller's try/catch therefore reports the failure and leaves the route available for safe retry instead of unconditionally reporting backup complete. A static regression guard was added to android/scripts/check-walkon.py. Final CI #171 is pending.
3. **Gap ledger created.** This report is on isolated audit branch audit/gativx-completion-gap-ledger-20261125; it does not change PR #112, PR #114 or PR #107.

## Documentation conflicts to resolve without redesign

- docs/GATIVX_IOS_FIRST_ACCEPTANCE.md says Android and web are frozen until iOS acceptance.
- The later docs/GATIVX-FINAL-DAY-NIGHT-DESIGN-LOCK.md (2026-11-15), current CLAUDE.md, and the current owner instruction require one coherent iOS/Android/Web product.
- Navigation definitions also differ: the iOS acceptance/CLAUDE documents list Home/Activity/Missions/Community/Profile, while the later design lock lists Home/Activity/Workouts/Health-Progress/Community. Preserve the approved Design C and current implemented layout; do not silently change navigation until the product owner resolves the specification conflict.

## External blockers and exact evidence needed

1. **iOS signing/device:** owner-controlled Apple Developer signing identity and provisioning profile with HealthKit entitlement; then install on the actual iPhone and record IOS-01 through IOS-14 from docs/GATIVX_IOS_FIRST_ACCEPTANCE.md.
2. **Android device:** a clean Android device/emulator, Health Connect provider and permissions; record install, sign-in, measured metrics, screen-locked WalkOn, save/recovery and cloud sync. A debug APK is not a Play release.
3. **Backend:** a reproducible baseline schema/configuration and a non-production Supabase test project whose migration state can be inspected; run RLS, cross-account isolation, retry/idempotency and deletion/export tests.
4. **Web release:** current-head browser smoke test against a controlled staging backend, then verify the actual Pages deployment URL and live auth/data flows.
5. **Product completion:** implement the missing onboarding, full Missions, Community, Notifications, Apps, full Android screens, web parity, 3D and the remaining blueprint modules before describing GATIVX as feature-complete.

## Next engineering actions

1. Obtain the final result of iOS run #636. Keep the full unit/UI suite enabled; diagnose genuine failures rather than narrowing or skipping tests.
2. Obtain Android run #171; if it passes, retain the isolated branch for review and then stack it into the consolidated repair work without merging.
3. Refresh PR #114 onto the latest PR #112 head only after the full iOS validation is stable; preserve its Finish & Save tests and keep both PRs open.
4. Continue from the gap ledger, prioritising member onboarding, activity reliability, HealthKit/Health Connect acceptance, Missions, Community, Notifications and cross-platform parity.
5. Keep PR #107 untouched and unmerged. Do not claim signed installation, physical-device acceptance or production deployment without their evidence.


---

## 2026-11-25 22:48 IST — latest verified state (supersedes earlier pending labels)

### Branches and pull requests rechecked
- PR #112 remains open/draft/unmerged at `b6c04d41dc67bd191ed0cf8966331eb5661a9887`.
- PR #114 remains open/draft/unmerged at `87318182360d4369ea2f7a773a27dd3fa3e7c558`; its base is still `fa92bb43a6b2064e0d412e4607c575057535ca1b`, which is 7 commits behind current PR #112 head. GitHub currently reports PR #114 as not mergeable. Do not refresh/merge until a reviewed integration plan is ready.
- PR #107 remains open/draft/unmerged at `c19bdbd307df7048cefd86bd3e6064ac4f4e3042`; no PR #107 files, branch refs or metadata were changed.
- New isolated candidate PR #115 is open/draft/unmerged. Head branch `fix/gativx-activity-tab-transition-20261125`, commit `d37733e3b08a585344506f73534b6e93ac2c1aea`, base `fix/gativx-ui-test-guest-reset` at PR #112 head.

### Latest iOS full-suite evidence
- **Run #636 — FAIL** on PR #112 head `b6c04d41dc67bd191ed0cf8966331eb5661a9887`. Exact XCTest totals from the job log: **58 unit tests passed, 0 failed; 2 UI tests executed, 1 passed and 1 failed; 0 cancelled**. The failing test is `testDashboardSectionsMetricsAndPrimaryNavigation` at `GATIVXDashboardUITests.swift:237`. After the Guru sheet was dismissed, XCTest tapped the Activity tab; the app did not emit an event-loop-idle notification, subsequent accessibility queries stalled, and XCTest timed out. This is now a reproducible Activity-tab transition failure on the full-suite run, not evidence of a Profile-only defect. The second UI test `testHomeStartWalkNavigatesWithoutStartingSession` passed.
- Run #636 also completed the iPhone Simulator build, source entitlement/privacy checks, unsigned iPhone Release build and unsigned IPA packaging successfully. The aggregate release gate correctly failed because XCTest failed. No signed/device behavior is inferred. [Run #636](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652420651)
- **Candidate correction in PR #115:** commit `d37733e3b08a585344506f73534b6e93ac2c1aea` removes the unused nested `NavigationStack` around Activity (there are no Activity navigation destinations), adds a stable Activity-tab accessibility identifier, and updates both Activity-tab UI test queries to use it. This is a hypothesis-driven, isolated correction; it is not yet verified.
- **Run #637 — IN PROGRESS** on the PR #115 head at report time. No test outcome is claimed. [Run #637](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45663157699)

### Latest Android evidence
- **Run #171 — PASS** on `19c679a7f2ef675176c0009148865563fca2fd00`: all six WalkOn source safeguard assertions passed, Gradle debug APK build completed successfully (35 actionable tasks executed), and the APK artifact uploaded successfully. This is source/static-check plus debug-build evidence only; no emulator/physical Android device test, Health Connect live read, signing or Play deployment was performed. [Run #171](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476) · [Debug APK artifact](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476/artifacts/15042071077)

### Next actions
1. Inspect the actual logs and exact test counts from run #637 when it completes. If it fails, retain the failure and investigate the remaining event-loop/accessibility issue; do not narrow the suite.
2. Keep PR #114 unmerged and stale until PR #112/PR #115 navigation validation stabilises. Then reconcile the overlapping Finish & Save, HealthKit and ContentView changes on a new isolated integration branch and rerun the complete suite.
3. Continue the documented product gap work. The current code still gates Community and Notifications, has only a fixed consistency mission, lacks an Apps tab, and does not provide complete onboarding or a complete Android/Web parity experience.
4. Preserve Design C, keep PR #107 untouched, and keep all signing, physical-device and production-release claims blocked until direct evidence exists.


## Cross-platform test-readiness verification — 25 November 2026

### Android source and CI scope
- The audited PR #112 base contains native Android Kotlin/Compose code in `MainActivity.kt`, an encrypted local `WalkOnStore`, and a foreground `WalkOnLocationService`. The manifest declares location, foreground-service, activity-recognition, notification and Health Connect read permissions.
- The feature hub explicitly marks Home, Activity and Profile as “Available” (for testing), Mission as “Testing”, and Wellness, Strength, GURU, Community, Motion 3D, Rewards, Referrals and Settings as “Coming soon”. The visible copy confirms that full goal planning/milestones, coaching, community and wellness features are not delivered in this Android build.
- The repository tree at PR #112 base contains no Android `src/test` or `src/androidTest` source sets. The Android workflow runs `android/scripts/check-walkon.py` (six source-pattern safeguards in the current run) and `gradle assembleDebug`; it does not run JVM unit tests or instrumentation tests. Run #171 therefore proves the six source safeguards and successful debug APK compilation/package/upload, not runtime behavior.
- The sync acknowledgement hardening on `feat/gativx/android-sync-ack-20261125` is a safe improvement, but the static assertions are not a substitute for behavioral tests. Add JVM-testable pure reconciliation logic and Android instrumentation coverage before treating Android save/sync as accepted.

### Web Hub source and CI scope
- The current web entry redirects to `app-v2.html`. Its five navigation destinations are Home, Journey, Record, Walk and GURU; the native five-tab information architecture is not present. The source has no Community feed, member Profile/settings, Notifications or Apps destination.
- The browser walk UI explicitly instructs members to keep the screen open. It uses browser geolocation and local storage/recovery; this must not be described as native background GPS tracking.
- Web run #411 passed its structural Node release gate and Playwright mobile browser smoke test on SHA `e005c1a512d93a5715b9b130e7eea019a2cf5ffe` (PR #108), not the current PR #112 head. The smoke test seeds local fixtures, aborts all external network requests and supplies a mocked Supabase client. It validates client-side navigation, goal/GURU behavior, sample health import and account-store logic, but it is not live Supabase, email-auth, production or deployment acceptance. [Run #411](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44889592176)
- The GitHub Pages workflow is configured only for pushes to `main` or manual dispatch. No Pages/deploy run appeared in the latest 100 repository workflow runs at this audit time. No production Pages URL or live deployment evidence is claimed.

### Shared backend and reproducibility
- The tracked `supabase/` tree contains ten incremental SQL migrations (daily Health sync, GPS sessions, owner RLS/RPC hardening and member goal/purpose fields). It does not contain a Supabase CLI `config.toml`, checked-in baseline schema, deterministic seed fixture or backend test suite. A clean Supabase environment cannot be proven reproducible from the repository alone.
- The owner-scoped RLS migration revokes public/anon execution of trigger helpers and limits the GPS route RPC to authenticated callers; policies use `(select auth.uid())` for member ownership. Source inspection is positive, but there is no live two-account RLS isolation test or verified production migration state.
- The web and Android workflows do not run a shared contract/integration suite against a controlled Supabase staging project. This remains implemented-but-unverified/blocked, not verified.

### Engineering priority
1. Keep the current isolated iOS Activity-tab candidate under full-suite CI.
2. Once iOS is stable, integrate the six-file Finish & Save/HealthKit patch on a fresh branch and rerun all 71 unit tests plus both UI tests and packaging.
3. Establish a reproducible Supabase test project and migration baseline before expanding cloud-backed Community or member data.
4. Add actual Android JVM/instrumentation tests and web live-backend contract tests; do not promote static source checks into behavioral acceptance.


## Finish & Save six-file patch compatibility review — 25 November 2026

The six-file PR #114 patch was re-read against the current PR #112 changes:

- PR #114 adds two pure policy/coalescing source files, changes `ContentView.swift` and `HealthKitManager.swift`, and adds regression coverage plus one existing test-string correction.
- PR #112 also changes `ContentView.swift`, but the inspected hunks are in separate areas: live step reconciliation, Profile photo presentation, Community navigation and UI-test launch/accessibility setup. No direct same-line collision was found in the inspected patches. `HealthKitManager.swift` and the two new pure helper files are not changed by PR #112.
- The PR #114 branch is still based on the older `fa92bb43...` version of the repair branch. Current PR #112 is seven commits ahead. GitHub reports PR #114 as not mergeable. Therefore this is a source-level compatibility assessment only; the combined tree has not yet been built or tested.
- **Run #628** on PR #114 SHA `87318182360d4369ea2f7a773a27dd3fa3e7c558`: exact XCTest log totals are 71 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; simulator build, unsigned Release build and IPA packaging succeeded. [Run #628](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633053186)
- **Run #629** on the same SHA: 71 unit tests passed, 0 failed; the dashboard UI test failed at line 295 with an accessibility-query timeout; the second UI test did not complete before the 40-minute test-step timeout. Simulator and unsigned Release/IPA packaging succeeded, but the aggregate gate failed. [Run #629](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633166732)

**Integration decision:** preserve PR #114 as-is for now. After PR #115 proves or disproves the Activity-tab correction, create a fresh isolated integration branch from the then-current PR #112 head, apply the PR #114 six-file patch without rewriting either existing branch, and run the complete combined suite. Keep both PRs open/draft and do not merge any PR.

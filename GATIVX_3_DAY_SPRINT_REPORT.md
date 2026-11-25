# GATIVX 3-Day Engineering Sprint Report

**Last updated:** 2026-11-26 02:45 IST (21:15 UTC)  
**Repository:** sbscorpsales-ship-it/Mission-75  
**Audit branch:** audit/gativx-completion-gap-ledger-20261125  
**Primary repair branch:** fix/gativx-ui-test-guest-reset  
**Primary repair head:** b6c04d41dc67bd191ed0cf8966331eb5661a9887  
**Primary PR:** [#112](https://github.com/sbscorpsales-ship-it/Mission-75/pull/112), open, draft, unmerged  
**Passing Activity-navigation candidate:** [#115](https://github.com/sbscorpsales-ship-it/Mission-75/pull/115), head d37733e3b08a585344506f73534b6e93ac2c1aea  
**Combined Finish & Save integration:** [#117](https://github.com/sbscorpsales-ship-it/Mission-75/pull/117), head 7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417, full CI pending  
**Web visual-completeness preview:** [#116](https://github.com/sbscorpsales-ship-it/Mission-75/pull/116), head 090678d93dc6f373b2313e0239c0158dc54f5a30  
**Cumulative report PR:** [#118](https://github.com/sbscorpsales-ship-it/Mission-75/pull/118), open, draft, unmerged  
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
| iOS Finish & Save | Implemented-but-unverified | Recovery-time policy, local-first history, HealthKit retry/outbox and duplicate-export coalescing are implemented on PR #114 and now stacked into PR #117. PR #117 adds four step-reconciliation tests to the 13 existing Finish & Save tests; its combined full suite is running. The UI suite still does not drive a complete Finish & Save flow, and no physical-device save/export test exists. |
| Apple Health workout export | Implemented-but-unverified | HealthKit workout export and retry queue exist, with unit coverage. A signed app carrying the HealthKit entitlement and an actual iPhone export/read-back are still required. |
| GATIVX Guru and 30/90/180/365-day journey | Implemented-but-unverified | Goal, purpose, emotion, next-action and journey logic exist; the 8 goal/journey unit tests passed in CI #628. iOS values are locally persisted; cross-device cloud persistence is not proven. |
| Missions | Missing | iOS currently exposes one fixed “Today · Consistency” mission and a step-progress view, not a goal-linked mission engine with member-created missions, milestones and reviews. |
| Community | Missing | iOS explicitly gates the feed/shared missions. No live community feed, groups, sharing, moderation, blocking or reporting. |
| Profile | Implemented-but-unverified | Account identity, local photo, appearance, motion/location and Health settings exist. Profile tab navigation passed in PR #115 UI run #637; settings/photo-picker behavior and account lifecycle are not fully end-to-end verified. Photo is local-only. |
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
| iOS CI/release | Verified (CI scope only) | PR #115 run #637 passed 58 unit tests and 2 UI tests, then simulator build, unsigned Release build and IPA packaging/upload. The combined Finish & Save PR #117 full suite is still running. Unsigned IPA is not installable and does not prove device acceptance. |
| Android CI/build | Verified (CI scope only) | CI #171 passed 20 source-safeguard assertions, built the debug APK and uploaded it. This proves compilation/static safeguards, not installation, sensors, Health Connect or customer acceptance. |
| Web CI | Verified (CI scope only) | PR #116 run #45675295670 passed the structural release gate, existing mobile browser smoke and the separate visual-preview navigation/screenshot checks: 25 PASS assertions, 0 FAIL. Eight screenshots were uploaded. The Supabase client is mocked and external network is blocked; this is not live-backend or production acceptance. |
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
- **Run #636 — FAIL** on PR #112 head b6c04d41dc67bd191ed0cf8966331eb5661a9887: 58 unit tests passed, 0 failed; 2 UI tests executed, 1 passed and 1 failed; 0 cancelled. The Activity-tab navigation query timed out after Guru dismissal. [Run #636](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652420651)

### Android

- **Run #168 — PASS** on d0dbfb67377a298f90bc732a1c16d46546bef185: WalkOn static safeguards passed, Gradle debug APK build passed and APK artifact upload passed. The Android code tree is the same as the audited PR #112 tree; the comparison showed only android/BUILD_ACCEPTANCE.md added on that validation branch. No emulator/physical-device test was run. [Run #168](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45557738344)
- An isolated Android sync-acknowledgement correction is in branch feat/gativx/android-sync-ack-20261125, head 19c679a7f2ef675176c0009148865563fca2fd00. It throws on unreadable local history, missing uploaded route or failed encrypted sync-marker read-back so the existing retry/error path is used. **Run #171 — PASS:** 20 source-safeguard assertions passed, Gradle debug APK build passed and artifact upload passed. This is CI/source/build evidence only; no Android emulator or physical-device acceptance. [Run #171](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476) · [Debug APK artifact](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476/artifacts/15042071077)

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
- **Run #637 — PASS** on PR #115 head d37733e3b08a585344506f73534b6e93ac2c1aea: 58 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; 0 cancelled. The dashboard navigation test (including Profile) and Start Walk navigation test both passed. Simulator build, unsigned Release build, IPA integrity, packaging and artifact upload passed. [Run #637](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45663157699)
- **PR #117 combined integration run #45674730866 — IN PROGRESS** on SHA 7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417. The full unit/UI step is still running; no counts or build/package result are claimed yet. [Run #45674730866](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45674730866)

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
- The repository tree at PR #112 base contains no Android src/test or src/androidTest source sets. The Android workflow runs android/scripts/check-walkon.py (20 explicit PASS assertions in run #171) and gradle assembleDebug; it does not run JVM unit tests or instrumentation tests. Run #171 therefore proves source safeguards and successful debug APK compilation/package/upload, not runtime behavior.
- The sync acknowledgement hardening on `feat/gativx/android-sync-ack-20261125` is a safe improvement, but the static assertions are not a substitute for behavioral tests. Add JVM-testable pure reconciliation logic and Android instrumentation coverage before treating Android save/sync as accepted.

### Web Hub source and CI scope
- The current web entry redirects to `app-v2.html`. Its five navigation destinations are Home, Journey, Record, Walk and GURU; the native five-tab information architecture is not present. The source has no Community feed, member Profile/settings, Notifications or Apps destination.
- The browser walk UI explicitly instructs members to keep the screen open. It uses browser geolocation and local storage/recovery; this must not be described as native background GPS tracking.
- Web run #411 passed its structural Node release gate and Playwright mobile browser smoke test on an older PR #108 SHA. The current PR #116 head also passed: run #45675295670 produced 25 PASS assertions, including the existing browser smoke and eight separate visual-preview screenshots. The Supabase client is mocked and external network calls are blocked; neither run is live-backend, production or deployment acceptance. [Run #45675295670](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45675295670)
- The GitHub Pages workflow is configured only for pushes to `main` or manual dispatch. No Pages/deploy run appeared in the latest 100 repository workflow runs at this audit time. No production Pages URL or live deployment evidence is claimed.

### Shared backend and reproducibility
- The tracked `supabase/` tree contains ten incremental SQL migrations (daily Health sync, GPS sessions, owner RLS/RPC hardening and member goal/purpose fields). It does not contain a Supabase CLI `config.toml`, checked-in baseline schema, deterministic seed fixture or backend test suite. A clean Supabase environment cannot be proven reproducible from the repository alone.
- The owner-scoped RLS migration revokes public/anon execution of trigger helpers and limits the GPS route RPC to authenticated callers; policies use `(select auth.uid())` for member ownership. Source inspection is positive, but there is no live two-account RLS isolation test or verified production migration state.
- The web and Android workflows do not run a shared contract/integration suite against a controlled Supabase staging project. This remains implemented-but-unverified/blocked, not verified.

### Engineering priority
1. Keep PR #115 as the passing Activity-navigation baseline; do not merge automatically.
2. Inspect PR #117's combined full-suite CI. It is stacked on PR #115 and preserves PR #112's higher valid step-count reading while applying the Finish & Save recovery/coalescing patch.
3. Establish a reproducible Supabase test project and migration baseline before expanding cloud-backed Community or member data.
4. Add actual Android JVM/instrumentation tests and web live-backend contract tests; do not promote static source checks into behavioral acceptance.


## Finish & Save six-file patch compatibility review — 25 November 2026

The six-file PR #114 patch was re-read against the current PR #112 changes:

- PR #114 adds two pure policy/coalescing source files, changes `ContentView.swift` and `HealthKitManager.swift`, and adds regression coverage plus one existing test-string correction.
- PR #112 and PR #114 do overlap in the finish-step reconciliation expression. PR #114 uses queriedSteps ?? sessionSteps; PR #112 uses the maximum non-negative queried/live reading. Replacing PR #112's ContentView.swift with PR #114's version would lose the higher live reading. The PR #117 integration branch keeps the max-reading behavior in ActivitySessionFinishPolicy.highestMeasuredSteps and adds four direct tests.
- The PR #114 branch is still based on the older `fa92bb43...` version of the repair branch. Current PR #112 is seven commits ahead. GitHub reports PR #114 as not mergeable. Therefore this is a source-level compatibility assessment only; the combined tree has not yet been built or tested.
- **Run #628** on PR #114 SHA `87318182360d4369ea2f7a773a27dd3fa3e7c558`: exact XCTest log totals are 71 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; simulator build, unsigned Release build and IPA packaging succeeded. [Run #628](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633053186)
- **Run #629** on the same SHA: 71 unit tests passed, 0 failed; the dashboard UI test failed at line 295 with an accessibility-query timeout; the second UI test did not complete before the 40-minute test-step timeout. Simulator and unsigned Release/IPA packaging succeeded, but the aggregate gate failed. [Run #629](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633166732)

**Integration decision:** PR #114 remains unchanged. A fresh isolated branch integration/gativx-finish-save-on-activity-tab-20261125 was created from the passing PR #115 head and opened as draft PR #117. It applies the Finish & Save recovery/coalescing work, preserves the higher valid live step reading and adds four direct regression tests. The combined CI is pending; keep PRs #112, #114, #115 and #117 open/draft and do not merge any PR.


## Final PR metadata recheck — 25 November 2026, 22:51 IST

A final live metadata read changed one detail from the earlier snapshot: GitHub now reports PR #114 `mergeable: true` (the earlier read returned false). Its recorded base SHA is still `fa92bb43a6b2064e0d412e4607c575057535ca1b`, while PR #112's current head is `b6c04d41dc67bd191ed0cf8966331eb5661a9887` (seven commits ahead of that base). This mergeability flag is not evidence that the six-file patch has been validated on the current combined tree. Keep PR #114 open and draft; no merge or base retargeting was performed.


---

## 2026-11-26 00:03 IST — verified automation run 1

### Repository and branch state
- Default branch main remains at 143889db3e72540fb478b76c486082f45395e9bd (2026-11-17); no main-branch content was changed.
- PR #112 remains open/draft/unmerged at b6c04d41dc67bd191ed0cf8966331eb5661a9887.
- PR #114 remains open/draft/unmerged at 87318182360d4369ea2f7a773a27dd3fa3e7c558; its base is still the older fa92bb43a6b2064e0d412e4607c575057535ca1b, seven commits behind PR #112's current head.
- PR #115 remains open/draft/unmerged at d37733e3b08a585344506f73534b6e93ac2c1aea, stacked on PR #112.
- PR #117 remains open/draft/unmerged at 7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417, stacked on PR #115. Its only product changes are the six iOS files listed below.
- PR #116 remains open/draft/unmerged at 090678d93dc6f373b2313e0239c0158dc54f5a30, based on main. Its last source/test change is 21bfe65; the final commit only removes the duplicate report file.
- PR #118 remains open/draft/unmerged as the documentation-only report PR.
- PR #107 remains open/draft/unmerged at c19bdbd307df7048cefd86bd3e6064ac4f4e3042; no PR #107 branch, file, base, metadata or review state was changed. No PR was merged.

### Verified engineering changes and commits

**Finish & Save integration — commit 7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417, draft PR #117**
- Files: ios/GATIVX/ContentView.swift, ios/GATIVX/HealthKit/HealthKitManager.swift, ios/GATIVX/Models/ActivitySessionFinishPolicy.swift, ios/GATIVX/HealthKit/HealthKitWorkoutExportCoalescer.swift, ios/GATIVXTests/GATIVXActivitySessionTests.swift, ios/GATIVXTests/GATIVXFinishSaveRegressionTests.swift.
- Carries forward PR #112's maximum non-negative queried/live step reading, rather than PR #114's older nil-coalescing expression.
- Adds four tests for higher-live, higher-query, negative and unavailable step readings; the Finish & Save regression test file now contains 17 tests.
- Integrates recovered-session finish-time handling and one-export-per-session coalescing for concurrent Finish & Save/outbox retry calls.
- CI run #45674730866 is still executing the full simulator unit/UI test step. No combined pass/fail count is available yet. The UI suite does not yet perform a full simulated Finish & Save gesture/data round-trip; local persistence, finish policy and export coalescing are covered by unit tests.

**Web visual preview and test harness**
- Commit 066810a88e1b2ffd9b891c9e75bcd73b4070ae59: scripts/browser-smoke.mjs and scripts/visual-preview-smoke.mjs — stabilised panel/card navigation and separated preview smoke from normal browser smoke.
- Commit 8248d79995837943edf6227b0b99a9b637be70c4: scripts/browser-smoke.mjs — switched browser fixtures to a local HTTP origin, seeded the cloud fixture only once across reloads, and asserted account-isolation storage before/after reload.
- Commit 21bfe65da8b7d49b7fd133f799f0639eb1609ba2: scripts/browser-smoke.mjs, .github/workflows/web-checks.yml, and restored app-v2.html to the exact main-branch blob 8089f536017ffb3a60a8bb99291313a3f5413927. The final PR #116 diff does not alter the working app file.
- Commit 090678d93dc6f373b2313e0239c0158dc54f5a30 deletes the duplicate sprint-report snapshot from PR #116; the canonical cumulative report is tracked separately in PR #118.
- Run #45675295670 — PASS on the code-bearing PR #116 head 21bfe65: 25 PASS assertions across the structural release gate, existing mobile browser smoke and visual preview checks; 0 FAIL. The only later PR #116 commit removes the duplicate report file. Eight screenshots were captured at 390x844: Home, Explore, Missions, Community, Profile, Connected Apps, Notifications and Profile-header entry. Screenshot artifact 15052765109 is 3.5 MB. The new screens are explicitly preview-only; they are not production feature completion. Run: https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45675295670
- The original app-v2.html remains byte-for-byte the same blob as main. No Pages deployment was attempted. The preview is not live on the production URL.

### Exact CI evidence rechecked
- iOS PR #115, run #637: 58 unit passed, 0 failed; 2 UI passed, 0 failed; 0 cancelled. The dashboard navigation test (including Profile) and Start Walk navigation test passed. Simulator build, unsigned Release build, IPA ZIP integrity, packaging and artifact upload passed. This verifies the candidate CI pipeline only; it does not verify a signed install, physical iPhone, HealthKit export or background GPS.
- iOS PR #117, run #45674730866: in progress at report time; no counts, simulator build or package result claimed.
- Android run #171: 20 source-safeguard PASS assertions, 0 FAIL; Gradle debug APK build and artifact upload succeeded. No Android JVM/instrumentation suite or emulator/physical-device test ran.
- Web PR #116, run #45675295670: 25 PASS assertions, 0 FAIL; 8 screenshots uploaded. Supabase is mocked and external network calls are blocked.

### Updated gap ledger interpretation
- Profile tab navigation is verified in CI scope on PR #115; Profile settings, photo picker, data export/deletion and live account behavior remain implemented-but-unverified or missing.
- iOS simulator/unit/UI/release packaging is verified in CI scope on PR #115; the combined Finish & Save candidate PR #117 remains pending.
- Finish & Save is implemented-but-unverified until PR #117's full suite passes and a real device confirms local save, HealthKit export and recovery. The current UI suite still lacks a complete end-to-end Finish & Save UI flow.
- Android source/build and Web Hub browser/preview checks are verified in CI scope only. They do not prove physical device behavior, live backend acceptance or production deployment.
- Onboarding, full Missions, Community, Notifications, Apps hub, Universal Data Hub provider registry/reconciliation, 3D replay, full nutrition/sleep/strength, referrals/subscriptions/rewards, cross-platform parity, and complete export/deletion remain missing or incomplete as marked in the ledger.

### Blockers and next action
1. Wait for and inspect the actual logs from PR #117 run #45674730866. If it fails, fix the real defect and rerun the full suite; do not narrow tests.
2. Keep all PRs open/draft. Do not merge PR #107 or any other PR.
3. Keep the working app-v2.html and live Pages deployment untouched. The eight-screen preview is review evidence only.
4. Physical iPhone HealthKit/background GPS and signing remain blocked on the owner-controlled Apple signing identity/provisioning profile and actual iPhone. Android acceptance remains blocked on emulator/device plus Health Connect. Live Supabase/RLS acceptance remains blocked on a controlled non-production project and test accounts.


---

## 2026-11-26 01:01 IST — Design C review delivered; full-suite evidence reconciled

### Repository and pull-request state
- main remains at 143889db3e72540fb478b76c486082f45395e9bd; no main-branch file was changed.
- PR #107 remains open/draft/unmerged at c19bdbd307df7048cefd86bd3e6064ac4f4e3042; its branch and metadata were not changed.
- PR #112: open/draft/unmerged, head b6c04d41dc67bd191ed0cf8966331eb5661a9887.
- PR #114: open/draft/unmerged, head 87318182360d4369ea2f7a773a27dd3fa3e7c558, still based on fa92bb43a6b2064e0d412e4607c575057535ca1b. A fresh compare confirms PR #112 is 7 commits ahead of that base. Do not merge or silently retarget.
- PR #115: open/draft/unmerged, head d37733e3b08a585344506f73534b6e93ac2c1aea.
- PR #116: open/draft/unmerged, head 090678d93dc6f373b2313e0239c0158dc54f5a30.
- PR #117: open/draft/unmerged, head 7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417.
- PR #118 remains the documentation-only report PR.
- New PR #119: open/draft/unmerged, head b75a0639b34e5c7329db801c3ff423f406f9ce7e, based on main. No PR has been merged.

### Owner-facing Design C review — PR #119
The earlier PR #116 screenshot set was inspected, not merely assumed to be sufficient. Its sign-in panel dominated the screens and its navigation/layout did not represent the locked Design C hierarchy. It was therefore not treated as the final owner review.

A new isolated review page was created:
- Files changed on PR #119: gativx-design-c-review.html, scripts/design-review-smoke.mjs, scripts/browser-smoke.mjs, GATIVX_DESIGN_C_REVIEW_README.md, and .github/workflows/web-checks.yml.
- Five primary dashboards: Home, Activity, Workouts, Health & Progress, Community.
- Five supporting screens: GURU, Missions, Profile, Connected Apps, Notifications.
- Includes Day/Night appearance, 9:16 portrait-first layout, activity rings, daily metrics, mission/purpose hierarchy, route visual, weekly trends and source-status states.
- All metrics, routes and member/feed examples are explicitly illustrative. The page does not connect to an account, Supabase, HealthKit, Health Connect, GPS, sensors, background tracking or push delivery.
- The original app-v2.html blob was compared against main and is byte-for-byte identical. No production entry point or existing app code was changed.
- The preview package is a local review artifact, not a live Pages deployment. The interactive HTML and its verified gativx-logo.jpg are included in the artifact with the README and screenshots.

Run #45686178223 — PASS on exact PR #119 head b75a0639b34e5c7329db801c3ff423f406f9ce7e:
- Structural release gate: 15 PASS, 0 FAIL.
- Existing mobile browser smoke: 7 PASS, 0 FAIL.
- Design C review: 29 PASS, 0 FAIL.
- Checks include all ten screens, five primary destinations, 390×844 mobile overflow, Day/Night switching, period selection, Start Walk/GURU preview disclosures, browser console and uncaught exceptions.
- Screenshot artifact: [15056846592](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45686178223/artifacts/15056846592), 902,780 bytes; contains ten screen captures plus Home Day-mode capture, the interactive HTML, JPG logo and README.
- Run: https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45686178223

Design/parity status: the visual review is ready for owner inspection. This does not convert the production Missions, Community, Apps or Notifications rows from Missing to Implemented. Production cross-platform parity remains Missing/Incomplete until the real app modules are built and accepted.

### iOS Finish & Save and navigation — actual combined-run result
- PR #114 run #628 on 87318182360d4369ea2f7a773a27dd3fa3e7c558: 71 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; simulator build, unsigned Release build and IPA packaging passed. [Run #628](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633053186)
- PR #114 run #629 on the same SHA: 71 unit tests passed, 0 failed; the dashboard UI test failed on a Profile accessibility-query timeout; the second UI test did not complete before the test-step timeout. Simulator build, unsigned Release and IPA packaging passed. [Run #629](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633166732)
- PR #112 run #636: 58 unit tests passed, 0 failed; 2 UI tests executed, 1 passed and 1 failed. The failure was the Activity-tab transition after GURU dismissal. Simulator build, unsigned Release and IPA packaging passed. [Run #636](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652420651)
- PR #115 run #637 on d37733e3b08a585344506f73534b6e93ac2c1aea: 58 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; 0 cancelled. testDashboardSectionsMetricsAndPrimaryNavigation (which exercises the profile control, Missions, Community and Profile tab navigation) and testHomeStartWalkNavigatesWithoutStartingSession passed. Simulator build, unsigned Release build, IPA packaging and artifact upload passed. [Run #637](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45663157699)
- PR #117 combined run #45674730866 on 7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417: 75 unit tests passed, 0 failed. The UI suite did not complete: testDashboardSectionsMetricsAndPrimaryNavigation started, then the app main run loop stopped responding after the GURU sheet was dismissed and the Activity tab was tapped; the second UI test was not reached. The XCTest result contains no completed UI case, so do not report it as a passing or counted completed test. The test step failed; the overall run ended cancelled. The simulator build, unsigned Release build, IPA packaging and upload steps all completed successfully. [Run #45674730866](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45674730866)
- The PR #117 XCTest result bundle records an Invalid frame dimension (negative or non-finite) runtime issue during the GURU keyboard sequence. This is a diagnostic clue, not a proven root cause. The event-loop/accessibility stall after sheet dismissal remains unresolved.
- Finish & Save policy, local history/recovery and HealthKit outbox/coalescing unit tests passed within the 75-test run. There is still no full UI gesture/data round-trip for Finish & Save and no signed physical-device HealthKit save/read-back. Therefore Finish & Save remains Implemented-but-unverified.
- Profile tab navigation is Verified in CI scope on PR #115; profile settings/photo picker/account lifecycle are not fully end-to-end verified.

### Android and Web Hub
- Android sync-ack branch feat/gativx/android-sync-ack-20261125, head 19c679a7f2ef675176c0009148865563fca2fd00: run #171 passed 20 source-safeguard assertions and the Gradle debug APK build/upload. No emulator or physical-device behavior, Health Connect read, signing or Play release was tested. [Run #171](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476)
- Web Hub on PR #119: structural checks and existing browser smoke passed as above. The browser smoke test now waits for the account-migration marker before reloading after sign-out; this strengthens the test sequence and does not modify app-v2.html.
- The web smoke uses local fixtures/mocked Supabase and blocked external network; no live backend, tenant-isolation, production migration or Pages deployment claim is made.

### Current gap ledger interpretation
- iOS: Finish & Save = Implemented-but-unverified; Profile navigation = Verified in CI scope; HealthKit/background GPS = Implemented-but-unverified; signed install/physical iPhone acceptance = Blocked.
- Android: auth, Health Connect and WalkOn foundations = Implemented-but-unverified; remaining product modules and Android behavioral test suite = Missing; device/Play acceptance = Blocked.
- Web: existing Home/Journey/Record/Walk/GURU flow = Implemented-but-unverified; the new ten-screen Design C page = Verified as a visual prototype only; production Missions/Community/Profile/Apps/Notifications parity = Missing or incomplete.
- Shared backend/security: migrations, owner-scoped RLS and retry code exist, but a reproducible clean Supabase baseline, live two-account isolation test and shared contract suite remain Missing/Blocked.
- No physical iPhone, Android device, Apple signing identity, production Supabase credentials or production deployment was available or claimed.

### Next action
1. Present PR #119's interactive Design C package for owner review before starting another design change. Keep PR #119 open/draft; do not merge.
2. After the visual review handoff, investigate the GURU dismissal → Activity event-loop stall from the #117 xcresult; preserve the full unit/UI suite and rerun it without filtering.
3. Reconfirm Finish & Save local persistence, HealthKit outbox acknowledgement and Profile navigation on the combined tree; retain all existing regression tests.
4. Continue Android instrumentation and Supabase staging/RLS readiness work independently of device-only acceptance.
5. Keep PR #107 untouched and all PRs unmerged.

---

## 2026-11-26 01:49 IST — automation run 2: latest-state audit and GURU UI-stall investigation

### Repository, branch and PR state verified from GitHub
- Default branch: `main` at `143889db3e72540fb478b76c486082f45395e9bd`. The current `app-v2.html` blob on main is `8089f536017ffb3a60a8bb99291313a3f5413927`; no main-branch app file was changed in this run.
- PR #107 remains open/draft/unmerged at `c19bdbd307df7048cefd86bd3e6064ac4f4e3042`. Its metadata, branch and files were not changed.
- PR #112 remains open/draft/unmerged at `b6c04d41dc67bd191ed0cf8966331eb5661a9887`; run #636 is still the observed failed full-suite result.
- PR #114 remains open/draft/unmerged at `87318182360d4369ea2f7a773a27dd3fa3e7c558`, base `fa92bb43a6b2064e0d412e4607c575057535ca1b`. Its base is still seven commits behind PR #112's head. GitHub reports mergeable true at this read; this does not validate the stale-base patch on the latest combined tree. No retarget or merge was performed.
- PR #115 remains open/draft/unmerged at `d37733e3b08a585344506f73534b6e93ac2c1aea`.
- PR #117 remains open/draft/unmerged at `7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417`.
- PR #118 remains open/draft/unmerged; this update is being committed to its existing report branch.
- PR #119 remains open/draft/unmerged at `b75a0639b34e5c7329db801c3ff423f406f9ce7e`.
- New isolated PR #120 is open/draft/unmerged, head `c9414c2f734dce1577e8f193a36b517902774a4a`, based on PR #117 head `7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417`. Its diff is exactly one file, `ios/GATIVX/ContentView.swift` (2 additions, 3 deletions). No PR was merged.

### Exact CI results and inspected logs

**iOS**
- PR #112, run #636 (`45652420651`): 58 unit tests passed, 0 failed; 2 UI tests executed, 1 passed and 1 failed, 0 cancelled. Failure: Activity-tab navigation after GURU dismissal; app event loop/accessibility query timed out. [Run #636](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652420651)
- PR #114, run #628 (`45633053186`): 71 unit tests passed, 0 failed; 2 UI tests passed, 0 failed; simulator build, unsigned Release build, IPA packaging and aggregate release gate passed. [Run #628](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633053186)
- PR #114, run #629 (`45633166732`): 71 unit tests passed, 0 failed; the dashboard UI test failed at the Profile query at `GATIVXDashboardUITests.swift:295`; the other UI test did not complete before the 40-minute test-step timeout. Simulator build, unsigned Release build and IPA packaging passed; aggregate gate failed. [Run #629](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45633166732)
- PR #115, run #637 (`45663157699`): 58 unit tests passed, 0 failed; 2 UI tests passed, 0 failed, 0 cancelled. Profile navigation, Community/Missions navigation, and Home Start Walk navigation passed in this simulator UI suite. Simulator build, unsigned Release build, IPA packaging and upload passed. [Run #637](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45663157699)
- PR #117, run #638 (`45674730866`): **75 unit tests passed, 0 failed**. The UI suite did not produce a completed UI case: `testDashboardSectionsMetricsAndPrimaryNavigation` started, reached the GURU goal editing flow, then stalled after closing the GURU sheet and tapping Activity. XCTest reported the app main run loop busy for 30 seconds and failed to receive the idle notification; the 40-minute UI test step timed out. The second UI test was not reached. Overall workflow conclusion: cancelled after the timed-out test step. Simulator build, unsigned Release build, IPA packaging and uploads completed successfully. Do not count the UI suite as a pass. [Run #638](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45674730866)
- The PR #117 xcresult artifact (`15053478071`, 24,221,988 bytes) was downloaded and inspected, including the XCTest session log and app standard output. The app emitted SwiftUI `Invalid frame dimension (negative or non-finite)` warnings during the GURU keyboard sequence. XCTest subsequently logged `Unable to perform work on main run loop, process main thread busy for 30.0s` and `App event loop idle notification not received`. This is a reproducible diagnostic clue; the exact SwiftUI layout root cause is not yet proven.
- PR #120 run #639 (`45694286567`) is **in progress** on exact head `c9414c2f734dce1577e8f193a36b517902774a4a`. No test result is claimed yet. [Run #639](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45694286567)

**Android**
- Run #171 (`45652707476`) was rechecked from job logs: 20 source-safeguard assertions passed, 0 failed; Gradle debug APK build reported `BUILD SUCCESSFUL`; APK artifact `15042071077` uploaded. No JVM/instrumentation test, emulator run, physical-device test, Health Connect provider interaction, signed bundle or Play release was performed. [Run #171](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476) · [Debug APK](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476/artifacts/15042071077)

**Web Hub and Design C review**
- PR #119 run #436 (`45686178223`) passed on exact head `b75a0639b34e5c7329db801c3ff423f406f9ce7e`: structural gate 15 PASS/0 FAIL; existing mobile browser smoke 7 PASS/0 FAIL; Design C review navigation 29 PASS/0 FAIL. Total: 51 PASS assertions, 0 FAIL. The ten-screen visual review, five primary navigation destinations, Day/Night switch, period selector, 390px mobile overflow, preview-only disclosures, browser console and uncaught exceptions were checked. Screenshot/review artifact: [15056846592](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45686178223/artifacts/15056846592). [Run #45686178223](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45686178223)
- The production `app-v2.html` on main remains blob `8089f536017ffb3a60a8bb99291313a3f5413927`; PR #119 does not change it. Web smoke fixtures use mocked/local Supabase and blocked external network. The design review is a visual-only prototype, not production feature completion, live-backend acceptance or Pages deployment.

### Engineering change made in this run — PR #120
- Created isolated branch `fix/gativx-guru-goal-keyboard-layout-20261126` from PR #117 head `7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417`.
- Commit `c9414c2f734dce1577e8f193a36b517902774a4a` changes only the GURU goal input in `ios/GATIVX/ContentView.swift`: removes vertical TextField expansion and the redundant simultaneous tap gesture, retaining the same binding, FocusState, Done submit behavior, accessibility identifier and rounded-border style. Other GURU fields, sheet behavior, Finish & Save code and tests are unchanged.
- Opened draft PR #120 against the PR #117 integration branch, not main, so the PR diff is exactly one file and does not include inherited PR #107 or other stacked changes.
- This is a hypothesis-driven UI-layout mitigation based on the xcresult evidence. It is not a confirmed fix. Run #639 is the full, unfiltered validation; inspect all logs before updating status.

### Gap ledger status carried forward
- iOS auth, onboarding, goal/purpose, daily metrics, GPS, Finish & Save and HealthKit remain implemented-but-unverified where noted in the ledger. Profile navigation is verified in CI scope on PR #115; profile settings, photo picker, identity lifecycle and export/deletion remain unverified or missing.
- Android auth, Health Connect and WalkOn foundations remain implemented-but-unverified; remaining feature hub modules and Android behavioral/instrumentation tests remain missing. Device acceptance is blocked.
- Web Hub core flows remain implemented-but-unverified; PR #119 verifies the Design C review prototype only. Production Community, Missions, Profile, Apps and Notifications parity remains missing/incomplete.
- Shared Supabase migrations/RLS/outbox code remain implemented-but-unverified. A reproducible clean baseline, live two-account isolation, cross-platform contract tests and production migration verification remain missing/blocked.
- Signed iOS installation, physical iPhone HealthKit/background GPS, Android device acceptance, live Supabase credentials/test accounts and production Pages deployment remain blocked. No such acceptance is claimed.

### Next action
1. Inspect the exact run #639 job logs and xcresult. If all 75 unit tests, both UI tests, simulator build, unsigned Release build and IPA packaging pass, retain PR #120 as an unmerged review candidate; if not, isolate the next actual runtime/layout cause.
2. Do not merge PR #120, #117, #115, #114, #112, #119, #118 or PR #107.
3. Keep Design C and the original main-branch `app-v2.html` unchanged.
4. Continue the gap-ledger work only on isolated branches; physical-device and live-backend gates remain blocked pending the exact external evidence listed above.

---

## 2026-11-26 01:50 IST — PR #120 source-guard correction; full validation queued

### Correction to the preceding run status
- PR #120's first CI run #639 (`45694286567`) did **not** reach XCTest. The workflow step `Verify GATIVX first-run auth, portrait layout and permissions` failed, and the full XCTest step was skipped. Therefore run #639 is not evidence for or against the keyboard mitigation.
- The precise stale assertion required the literal `isGuruFieldFocused = true` tap-gesture assignment in `ContentView.swift`. The candidate intentionally removes that redundant gesture and relies on the native `.focused($isGuruFieldFocused)` binding. The workflow guard was updated to assert the focus binding itself, not the deleted implementation detail. No XCTest was skipped or weakened.
- The corrected branch head is now `66635d847964b90ab9b8a3d5b74dbb64257c09dd`. PR #120 remains one isolated, two-file change: `ios/GATIVX/ContentView.swift` and `.github/workflows/gativx-ios.yml`. It is still based on PR #117 head `7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417`.
- New full iOS workflow run #640 (`45694454367`) has been created for the corrected head and is pending. No test result is available yet. [Run #640](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45694454367)
- Run #639 remains in progress in its later build/package steps after the earlier source-guard failure; it must not be counted as a passing release gate. The full test suite was skipped on that run.

### Next action
Inspect run #640's complete logs. Require the full unit/UI suite to execute, then verify simulator build, unsigned Release build and IPA packaging. If the GURU UI stall remains, continue from the xcresult diagnostics rather than changing the test or claiming a pass.


---

## 2026-11-26 02:45 IST — automation run 3: GURU keyboard mitigation passes the full iOS CI suite

### Latest repository and PR state verified
- Default branch `main`: `143889db3e72540fb478b76c486082f45395e9bd`.
- PR #107 remains open/draft/unmerged at `c19bdbd307df7048cefd86bd3e6064ac4f4e3042`; no PR #107 file, branch or metadata was changed.
- PR #112 remains open/draft/unmerged at `b6c04d41dc67bd191ed0cf8966331eb5661a9887`.
- PR #114 remains open/draft/unmerged at `87318182360d4369ea2f7a773a27dd3fa3e7c558`, based on `fa92bb43a6b2064e0d412e4607c575057535ca1b`. A direct commit comparison confirms PR #112's head is 7 commits ahead of that base. No retarget or merge was performed.
- PR #115 remains open/draft/unmerged at `d37733e3b08a585344506f73534b6e93ac2c1aea`.
- PR #117 remains open/draft/unmerged at `7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417`.
- PR #118 remains open/draft/unmerged at `21c1b54a447214d7ad5500e48f0d0cc64e8576b1` before this report-only update.
- PR #119 remains open/draft/unmerged at `b75a0639b34e5c7329db801c3ff423f406f9ce7e`.
- PR #120 remains open/draft/unmerged at `66635d847964b90ab9b8a3d5b74dbb64257c09dd`, based on PR #117 integration head `7bb41d9de3cc43b4e03b4e54faf94f6ee48c3417`.
- PR #110 remains open/draft/unmerged at `d0dbfb67377a298f90bc732a1c16d46546bef185`; this is the Android debug-build validation PR. The separate Android sync-acknowledgement branch is recorded below.
- All PRs remain unmerged. No change was made to PR #107.

### PR #120 full iOS validation — PASS
- Candidate branch: `fix/gativx-guru-goal-keyboard-layout-20261126`.
- Source commit: `66635d847964b90ab9b8a3d5b74dbb64257c09dd`.
- Workflow run #640: [45694454367](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45694454367), completed successfully. The job log was downloaded and inspected.
- XCTest unit suite: **75 passed, 0 failed, 0 cancelled**.
- XCTest UI suite: **2 passed, 0 failed, 0 cancelled**.
- UI test `testDashboardSectionsMetricsAndPrimaryNavigation` passed. The recorded sequence entered GURU, focused the goal field, typed “Walk consistently”, dismissed the keyboard with Done, selected a 180-day journey, started the journey, changed the next-selection control to 30 days while the active journey remained 180 days, closed GURU, navigated to Activity and verified the Activity screen, navigated to Missions, Community and Profile, and verified the Profile identity control.
- UI test `testHomeStartWalkNavigatesWithoutStartingSession` passed; the Home Start Walk control navigated to Activity without starting a recording, and the Finish & Save button was present.
- The #640 log contains no recurrence of the earlier `Invalid frame dimension`, main-thread-busy or event-loop-idle-timeout diagnostics. The GURU keyboard mitigation is therefore validated for this simulator UI sequence, not proven across every iPhone size or physical device.
- iPhone Simulator build: **BUILD SUCCEEDED**.
- Unsigned iPhone Release build: **BUILD SUCCEEDED**.
- IPA packaging: ZIP integrity check passed; bundle identity/version metadata verified. Unsigned IPA artifact [15061672408](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45694454367/artifacts/15061672408), 698,523 bytes. Simulator artifact [15060788600](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45694454367/artifacts/15060788600). XCTest result bundle artifact [15061078309](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45694454367/artifacts/15061078309).
- Workflow job: **1 success, 0 failures, 0 cancelled**. The aggregate release gate reported all automated gates passed.
- The IPA is unsigned. This does not establish iOS installation/signing, physical iPhone HealthKit, background GPS or real-device save/export acceptance.

### What this changes in the gap ledger
- **GURU goal keyboard and the previously failing GURU-dismissal → Activity transition:** Verified in the #640 simulator UI sequence on PR #120's exact source head. Keep the change as an unmerged candidate pending owner review.
- **Profile navigation:** Verified in the same #640 simulator UI sequence, which opened Profile and found the authenticated member identity element. Profile photo picker, settings persistence and account lifecycle remain implemented-but-unverified.
- **Finish & Save:** The 17 dedicated Finish & Save regression tests and 24 activity-session persistence/recovery tests passed within the 75-unit suite. Atomic local history read-back, recovery upsert, retryable HealthKit outbox and duplicate/coalescing policies have unit-level evidence. The UI suite does not execute a full walk recording and save/read-back cycle; HealthKit export is not exercised against a real iPhone. Overall feature remains **implemented-but-unverified**, with its covered unit behaviors verified in CI.
- **iOS release pipeline:** Verified for simulator build, unsigned device-target Release build and IPA packaging on this source revision only. Signed install and device acceptance remain blocked.
- **GURU logic and journey model:** Unit and UI coverage passed in CI for the tested path. Cross-device persistence and live account sync remain unverified.
- The older PR #117 run #638 was cancelled after its UI timeout; run #640 on the PR #120 merge commit is the successful full-suite result for the corrected combined candidate. Do not rewrite the historical #638 outcome.

### Android and Web Hub latest evidence rechecked
- Android sync acknowledgement branch `feat/gativx/android-sync-ack-20261125`, source commit `19c679a7f2ef675176c0009148865563fca2fd00`, workflow run #171 [45652707476](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45652707476): inspected the job log. **20 source-safeguard assertions passed, 0 failed**; Gradle reported `BUILD SUCCESSFUL` in 26 seconds; debug APK artifact was produced. No JVM/instrumentation test, emulator, physical Android device, Health Connect provider or signed release test ran. Device behavior remains implemented-but-unverified / blocked.
- Web Design C review PR #119, exact head `b75a0639b34e5c7329db801c3ff423f406f9ce7e`, run #436 [45686178223](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45686178223): job completed successfully. Logs show 15 structural release assertions, 7 existing mobile browser smoke assertions and 29 Design C review assertions: **51 PASS, 0 FAIL**. All ten review screens, five primary navigation destinations, Day/Night toggle, period selector, 390px mobile overflow, preview disclosures and zero browser/page errors were checked. Screenshot artifact [15056846592](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/45686178223/artifacts/15056846592).
- The `app-v2.html` blob on `main` and PR #119's Design C branch was independently fetched and compared: both have blob SHA `8089f536017ffb3a60a8bb99291313a3f5413927`. The original working Web Hub file is unchanged. PR #119 is a visual-only review page; it is not a live production deployment or implementation of the gated features.
- Web smoke tests use mocked/local Supabase fixtures and block external network calls. Live auth, RLS, account isolation, production migration and Pages deployment remain unverified/blocked.

### Files and commits changed in this run
- No new application source commit was made in this automation run. The tested source change is the already-open PR #120 commit `66635d847964b90ab9b8a3d5b74dbb64257c09dd`, changing only `ios/GATIVX/ContentView.swift` and `.github/workflows/gativx-ios.yml` relative to its parent. Its change removes vertical expansion and a redundant simultaneous tap gesture from the GURU goal TextField while preserving binding, FocusState, Done submission and accessibility ID; the workflow guard now checks the native focus binding. No test case was removed, filtered or weakened.
- This report update changes only `GATIVX_3_DAY_SPRINT_REPORT.md` on the existing documentation branch. No production app, database, release configuration or user data was changed.

### Remaining blockers and next action
1. Keep PR #120 open/draft and unmerged. Review its two-file diff and retain the #640 evidence; do not merge automatically.
2. Do not refresh or merge PR #114 yet. Its base is seven commits behind PR #112; after owner review, plan an explicit safe rebase/stack and rerun the complete combined suite before any merge decision.
3. Add a true UI/integration test for a completed GPS walk: finish, local atomic write/read-back, app relaunch recovery, queued HealthKit export result and visible saved history. The current UI test checks navigation and presence of Finish & Save, not the actual save gesture.
4. Continue the missing-feature ledger: guided first-run onboarding; full Missions engine; Community groups/feed/moderation; notifications; Apps hub; Android parity; web parity; Universal Data Hub; export/deletion; nutrition/hydration/sleep/strength; 3D route replay; subscriptions/referrals/rewards/admin.
5. Obtain owner-controlled Apple signing identity/profile with HealthKit entitlement for physical iPhone installation and IOS-01..14 acceptance. Obtain Android emulator/device with Health Connect for screen-locked GPS, save/recovery and sync tests. Obtain a non-production Supabase environment with reproducible schema/migrations and two test accounts for RLS/tenant isolation/idempotency tests. Verify a controlled Pages deployment and live web auth before claiming production readiness.
6. Preserve Design C and the existing product decisions. Keep PR #107 untouched and every PR unmerged.

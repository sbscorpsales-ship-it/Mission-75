# GATIVX Unified Source Consolidation Audit

**Status:** Initial repository-backed audit  
**Date:** 17 November 2026  
**Purpose:** Consolidate the strongest verified work from Mission-75/GATIVX and RunJeet into one GATIVX product without losing working code or duplicating subsystems.

## 1. Product decision

GATIVX is the single end-user product. Mission-75 is the earlier product repository and current GATIVX web/dashboard foundation. RunJeet is a separate engineering source containing useful native tracking and local-first workout implementations. WALKON is a separate walking-focused project identified in the historical product record, but its source repository/code is not currently present in the connected GitHub repositories or the available project archive. Do not infer or fabricate its implementation.

This audit does not merge repositories, change production data, deploy, or make a release decision.

## 2. Source inventory

### Mission-75 repository (current GATIVX product foundation)

Repository: https://github.com/sbscorpsales-ship-it/Mission-75

Verified repository facts:
- Root `index.html` identifies GATIVX and routes the main experience to `app-v2.html`; it also links to `legacy-runtime.html` for the previous dashboard/saved-record tools.
- `app-v2.html` is the newer GATIVX dashboard entry and contains the current mobile-first visual system.
- Recent main-branch commits include:
  - `9836c0d`: iOS workout finish/save idempotency safeguards.
  - `00a7d80`: locked Day/Night dashboard theme implementation.
  - `a95b4f3`: adaptive personal health rings.
- Draft PR #103 adds a measured Walk Minutes ring based only on completed GPS walks with a finish timestamp and saved duration. It includes a browser smoke test for a completed 30-minute walk.
- Draft PR #104 adds a BACKUP PENDING state and retry of saved walks when cloud backup is interrupted. It explicitly avoids deleting local walks when cloud sync fails.
- Draft PR #101 adds idempotent Apple Health workout export after local persistence. Physical signed-iPhone verification remains required.
- Other open draft work covers Apple Health one-time connection, adaptive target ceilings, password recovery, and brand assets. Each must be reviewed for overlap before integration.

### RunJeet repository (native tracking and reliability source)

Repository: https://github.com/sbscorpsales-ship-it/RunJeet

Its README documents:
- Android hardware step counting via `TYPE_STEP_COUNTER`, a foreground health service, daily rollover and reboot-baseline recovery.
- Android Health Connect reads for steps, activity totals and imported workouts.
- iOS Core Motion pedometer and HealthKit daily totals/workout reads.
- Native GPS services and locally persisted route points, replayed to the dashboard.
- Local workout history, route display, IndexedDB persistence, and JSON backup/import.
- Android tests for step counter rollover, reboot handling and counter regression.
- Explicit limits: screen-lock/background behaviour depends on OS/device permissions and battery policy; force-stop/force-quit ends the process; a PWA cannot match native screen-off tracking.

RunJeet PR #2 describes shared Supabase authentication, local outbox/retry, cloud profile/steps/workout reads, Android Health Connect RPC, and backfill. Its physical cross-device acceptance test is still required.
RunJeet PR #3 is the open draft GATIVX cross-platform integration proposal.
RunJeet PR #4 is closed and must not be treated as a verified delivered fix without locating equivalent code and passing tests.

### WALKON source status

The historical GATIVX blueprint explicitly distinguishes WALKON as a separate native walking-focused app with local-first architecture. The connected GitHub installation currently exposes Mission-75 and RunJeet only; the available Library archive contains GATIVX and RunJeet materials but no WALKON source repository/archive. Therefore WALKON remains an identified but unaudited source. No user action is required for this audit to proceed with the two accessible repositories.

## 3. Recommended consolidation architecture

- Keep Mission-75 as the canonical GATIVX product repository and dashboard/product experience.
- Treat RunJeet native tracking as a source of candidate modules, not a second app to ship.
- Port only the native sensor, GPS, persistence, recovery and tests that pass code review and platform acceptance.
- Maintain one GATIVX identity, one canonical activity/session model, one cloud account and one sync contract.
- Keep device-specific adapters for Core Motion/HealthKit and Android step counter/Health Connect.
- Keep local-first completed workout persistence; cloud failure must never erase a saved local workout.
- Keep measured, imported, estimated and manually entered values distinguishable with source and timestamp. Missing values stay unavailable/null, not fabricated zeroes.
- Do not write duplicate step/distance samples into Apple Health if the device already records them. Workout export must be idempotent.
- Preserve existing member history and local data. No destructive reset or schema migration without a reviewed migration and backup plan.

## 4. Feature-by-feature decision register

| Area | Preferred source to inspect first | Integration decision |
|---|---|---|
| GATIVX identity, goals, Guru and product journey | Mission-75 + approved GATIVX charter | Keep canonical product doctrine |
| Dashboard layout and Day/Night visual system | Mission-75 `app-v2.html` and theme work | Keep as baseline; compare alternatives before changing |
| Progress rings and adaptive targets | Mission-75 PRs #96, #97, #103 | Keep source-backed metrics; reconcile overlapping ring branches |
| Native Android steps | RunJeet native Android implementation | Candidate to port after source and device tests |
| Native iOS steps/HealthKit | Mission-75 native iOS plus RunJeet native reference | Compare implementations; keep one owner per data type |
| GPS route capture | RunJeet native route service and Mission-75 GATIVX walk UI | Port reliable native capture into GATIVX's single session model |
| Workout finish/save/recovery | Mission-75 commit `9836c0d` plus RunJeet recovery work | Verify both; consolidate one idempotent lifecycle |
| Offline/cloud retry | Mission-75 PR #104 and RunJeet PR #2 | One outbox/retry strategy; never delete local completed walks |
| Apple Health workout export | Mission-75 PR #101 | Keep local-save-first and stable sync ID; physical signing/device test required |
| Hydration, sleep, meals, reminders | Existing GATIVX implementation in Mission-75/RunJeet PR history | Keep one shared wellness model and native adapters |
| WALKON-only features | Not yet source-verifiable | Do not copy or claim until actual source is available |

## 5. Required regression gates before calling the consolidated app functional

1. **Build gates:** web, Android and iOS builds pass on the same reviewed integration commit.
2. **Step integrity:** permission denied/unavailable is shown as unavailable, not zero; no double counting across HealthKit, Health Connect and native pedometer.
3. **Workout durability:** start → pause/resume → finish → verify local history → force-close/relaunch → history remains; repeated Finish creates one session only.
4. **GPS correctness:** route points filtered for accuracy, realistic distance/speed, route survives app background/lock as supported, and saved route is visible after relaunch.
5. **Offline resilience:** finish while offline; local record remains and shows BACKUP PENDING; reconnect and confirm exactly one cloud record; second device reads the same record.
6. **Health integration:** explicit permissions; HealthKit export only from a correctly signed iPhone build with the entitlement; Health Connect reads on a real Android device.
7. **Dashboard integrity:** steps, active calories and walk minutes show only valid source-backed values; targets are personalised and accepted by the member.
8. **Wellness:** hydration, sleep, meals and reminders persist across relaunch and sync without duplicate records.
9. **Security/data:** member isolation, RLS, no secrets in client code, backup/restore and migration review.
10. **Visual/accessibility:** mobile layout, Day/Night, readable rings, touch targets, and no regression in the approved GATIVX information architecture.

## 6. Immediate next engineering sequence

1. Freeze feature additions while source comparison is underway.
2. Inspect the complete Mission-75 and RunJeet native source files and their tests for step counting, GPS, finish/save, HealthKit/Health Connect and cloud sync.
3. Compare overlapping modules and choose one canonical implementation for each responsibility.
4. Create a small, reviewable integration branch with a module-by-module migration map; preserve both source repositories.
5. Run all automated tests and builds on the integrated branch.
6. Produce a fresh Android test build for the user's current device testing only after the integration checks pass.
7. Complete physical-device acceptance before describing the app as fully functional.

## 7. Non-negotiable safeguards

- No merge, production deployment, signing, release, or destructive data operation is authorized by this audit.
- Do not claim physical-device acceptance from CI alone.
- Do not ask the user to repeat already recorded product decisions.
- Keep WALKON's separate identity and data boundary intact until its source can be independently audited.

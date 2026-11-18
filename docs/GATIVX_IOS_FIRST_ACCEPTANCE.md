# GATIVX iOS — single-platform acceptance record

**Active platform:** iOS only  
**Integration PR:** #106  
**Rule:** Android and web implementation are frozen until iOS is accepted. Do not start parallel platform work.

## Dashboard design decision — locked

- Visual identity: **C — White + Neon Green**.
- Layout priority: **Balanced** — fitness metrics, missions, Gati Guru and community share the home dashboard.
- Primary navigation: **Home, Activity, Missions, Community, Profile**.
- Keep the dashboard readable, accessible and consistent; do not switch back to the earlier neon-yellow/black concept.
- Treat this as the approved design direction. Implementation and visual QA still need to be completed on the iOS app; approval of the concept is not proof that the shipped screen matches it.

## Appearance preference — approved

- Default appearance: **System / Automatic** — follow the iPhone's Light/Dark appearance setting.
- Manual override: provide **Day Mode**, **Night Mode**, and **Automatic** in Profile → Settings → Appearance.
- Keep the approved White + Neon Green identity in Day Mode and adapt surfaces/text for Night Mode while preserving accessible contrast.
- This is an approved product requirement; native implementation and device verification are still pending.

## Final dashboard visual lock — approved, no redesign

The user has explicitly approved the premium two-mode GATIVX dashboard concept as **full and final** and requested no alterations. Treat the generated premium dashboard mockup shown in the conversation as the visual reference. Do not redesign, rearrange, recolor, or remove approved dashboard elements without explicit user authorization.

### Locked visual direction
- Brand identity: GATIVX wordmark and green brand accent.
- Day Mode: premium bright white / soft neutral surfaces with neon-green accents.
- Night Mode: deep near-black / midnight surfaces with the same neon-green accents.
- Default appearance: **System / Automatic**, following the iPhone appearance setting; manual Day, Night and Automatic options remain available in Profile → Settings → Appearance.
- Premium visual language: refined typography, restrained glow, layered/glass-like cards, scenic nature imagery, clear spacing and high-contrast readable text.
- Header: GATIVX branding, notifications and profile entry.
- Hero: greeting, purpose-led message, prominent circular step-progress display and Today's Mission card.
- Metrics: distance, active time, calories and heart rate only when a real supported reading is available. Never display mock or fabricated readings as live data.
- Primary action: prominent Start Walk / Activity Tracker card.
- Supporting sections, in order: Gati Guru, My Journey, Community Gati.
- Bottom navigation, in order: Home, Activity, Missions, Community, Profile.
- Keep Day and Night layouts structurally consistent; adapt only theme surfaces, text, imagery treatment and contrast.

### Implementation and acceptance rule
This is a **design lock**, not a claim that the native iOS screen has already been implemented. Implement the approved composition faithfully. Any necessary accessibility, platform-safety or data-integrity correction must preserve the visual direction and be disclosed; ask before making a visible design alteration. Verify both appearances on the physical iPhone before release.

## What CI can prove

**Latest verified iOS CI:** [pull-request run 44216805623](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44216805623)  
**Matching push run:** [44216748402](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44216748402)  
**Source commit:** `a4da345a7569794439ce2b988e7b5980fddb18f7`  
**Result:** Both jobs completed successfully on 18 November 2026.

| Check | Result |
|---|---|
| XcodeGen project generation and scheme validation | Passed |
| GATIVX unit tests | 8 executed, 8 passed, 0 failures |
| HealthKit entitlement wiring and permission purpose strings | Passed CI validation |
| Native tracking, persistence and cloud-outbox safeguards | 79 source checks passed, 0 failed |
| iOS Simulator compile | Passed |
| iPhone arm64 Release device-target compile | Passed |
| Unsigned iPhone Release IPA packaging and ZIP integrity | Passed |

**Artifacts from PR run 44216805623** (verified not expired on 18 November 2026):

- `GATIVX-iPhone-unsigned-IPA`: artifact ID `14387979374`, 434,693 bytes. [Download from GitHub](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44216805623/artifacts/14387979374)
- `GATIVX-iOS-Simulator`: artifact ID `14388698940`, 1,568,445 bytes. [Download from GitHub](https://github.com/sbscorpsales-ship-it/Mission-75/actions/runs/44216805623/artifacts/14388698940)

The device artifact is an optimized **Release** build for iPhone arm64, but it is unsigned. It is not installable until signed with a valid Apple provisioning profile carrying the HealthKit capability. Source entitlements and a successful unsigned build do not grant that capability.

The completed-activity history uses atomic JSON file replacement in Application Support. The eight unit tests cover route-segment distance, older route-point decoding, unavailable step counts, duration formatting, atomic activity save/read-back, legacy UserDefaults migration, preservation of corrupt history, and preservation of legacy data when migration cannot write. The 79 source-level safeguards cover Finish & Save retry/recovery, GPS permission transitions and route persistence, HealthKit export idempotency and outbox handling, member-scoped cloud queues, and protection against fabricated zero readings. These static checks are not runtime device tests.

A simulator build and source-level safeguards prove compilation and selected logic, not physical iPhone behaviour. The successful Release build is not an installable signed app and cannot prove that the installed app carries the HealthKit entitlement. Physical-device acceptance remains mandatory.

## Physical iPhone acceptance — all must pass

| ID | Test | Pass condition | Result |
|---|---|---|---|
| IOS-01 | Install and launch | Signed GATIVX app installs, opens and survives force-close/relaunch | Not tested |
| IOS-02 | First Health permission | User explicitly enables Apple Health; permission explanation is clear | Not tested |
| IOS-03 | Daily steps | GATIVX matches Apple Health's daily step total; source and last refresh are visible | Not tested |
| IOS-04 | Active energy | Measured active energy matches Apple Health; no estimate is labelled measured | Not tested |
| IOS-05 | Automatic refresh | New Health data appears on foreground refresh and supported background notifications | Not tested |
| IOS-06 | GPS walk | Start, pause, resume and finish produce a plausible route and distance | Not tested |
| IOS-07 | Screen-locked GPS | A started walk continues with the screen locked under Always-location permission | Not tested |
| IOS-08 | Crash/relaunch recovery | An interrupted walk draft is recoverable; a completed walk is not duplicated or lost | Not tested |
| IOS-09 | Local save | Finish & Save persists the activity and route locally before any cloud/HealthKit operation | Not tested |
| IOS-10 | Apple Health workout export | Workout appears in Apple Health; retrying export does not create a duplicate | Not tested |
| IOS-11 | Offline sync | Health/activity data queues offline and clears only after server acknowledgement | Not tested |
| IOS-12 | Account isolation | Sign-out/sign-in never exposes another member's local or queued data | Not tested |
| IOS-13 | Data integrity | Missing readings remain unavailable; no false zeroes, double-counting or silent history replacement | Not tested |
| IOS-14 | Day boundary | Local midnight/time-zone change does not duplicate or lose daily totals | Not tested |

## Required evidence

For each test record: iPhone model, iOS version, app build/commit, steps performed, expected result, actual result, screenshot or short screen recording where useful, and pass/fail. Do not mark a test passed from source inspection alone.

## Known constraints and dependencies

- HealthKit read authorization is privacy-protected; the app cannot reliably infer whether read access was denied. The UI must describe the request state honestly.
- HealthKit background delivery is controlled by iOS and may be batched. Do not promise second-by-second background updates.
- Background GPS requires the correct location purpose strings, Always permission and a correctly configured signed app.
- The Apple Developer App ID and provisioning profile must permit HealthKit. Source entitlements and unsigned CI output do not grant that capability.
- The iOS app shares Supabase account services with other clients, but cross-platform validation is deferred until the iOS acceptance record is complete.

## Release decision

**Current status: NOT RELEASED — device acceptance outstanding.**

Only when all required IOS tests pass on the physical iPhone may this iOS release be called complete and Android work begin. Web work remains last.

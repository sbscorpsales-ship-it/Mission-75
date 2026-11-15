# GATIVX — Apple Health Reference Validation & Release Specification

**Product owner:** Param IT Solutions  
**Product:** GATIVX  
**Status:** Approved engineering direction; implementation and release evidence required  
**Applies to:** iOS, Android, web, Supabase and the Universal Data Hub

## 1. Product outcome

GATIVX helps a member move from a meaningful personal goal to consistent action and achievement. Fitness is the starting category, not the limit of the product.

The product must be accurate, approachable, motivating, privacy-conscious and dependable. The member is the centre of the system: the same authenticated member must see a consistent history and current state on iOS, Android and web.

**Product promise:** Your Goal. Your Guide. Your Achievement.

Engineering priorities:
1. Correctness, data integrity and member safety.
2. Reliable capture, persistence and synchronisation.
3. Clear, useful member experience.
4. Performance, accessibility and maintainability.
5. Visual refinement without regressing working functionality.

No release may be described as error-free. Release readiness means no known release-blocking defects, all required automated gates passing, data integrity checks passing, and documented device acceptance evidence.

## 2. Existing architecture to preserve

The repository already contains:
- A web application and established member dashboard.
- Native iOS code using HealthKit, Core Motion and Core Location.
- Native Android code using Health Connect and platform services.
- Supabase authentication, member-owned data and activity synchronisation.
- A Universal Data Hub architecture decision record at `docs/UNIVERSAL_DATA_HUB_ARCHITECTURE.md`.
- Existing activity, daily-log, GPS route and goal data.

Do not replace the current architecture or rewrite working modules as a first response to a defect. Audit the current implementation, make the smallest safe change, and preserve existing storage keys, account flows, schema compatibility and historical records.

Relevant open work observed during this review:
- PR #90 proposes measured sleep synchronisation across Apple Health, Health Connect and web. Its migration requires review and deployment before dependent builds are released.
- PR #91 validates HealthKit entitlement project wiring. Its unsigned CI build cannot prove that a signed, installed iPhone app carries the entitlement.
- Earlier work has addressed native motion upload retry, route history rendering, date normalisation and dashboard integration. Re-test these behaviours as regression gates.

These references describe repository state at the time this specification was prepared. Re-check current PR and workflow state before acting.

## 3. Apple Health export: permitted use

A founder-provided Apple Health export was inspected privately as a reference dataset. It contains historical records from multiple data categories and providers, workout records and GPX route files. Available categories include:
- Step count, walking/running distance, active energy and basal energy.
- Walking speed, step length, double-support percentage and walking asymmetry.
- Heart rate, sleep analysis, flights climbed and walking steadiness.
- Cycling distance, blood pressure, oxygen saturation, body mass and height.
- Workout sessions and GPS route files.

The export includes records from iPhone and third-party wearable/fitness sources, including GOBOULT Fit, Fastrack and Strava. Availability and completeness differ by metric and date.

**Privacy rule:** Never commit the raw Apple Health ZIP/XML/GPX export, raw health samples, personal daily totals, exact routes, or identifiable health timelines to this repository, CI logs, fixtures or screenshots. Use synthetic or irreversibly redacted fixtures only. Keep any local validation copy access-controlled and delete it when no longer required.

The export is a historical test corpus, not a live HealthKit connection and not proof that the current installed GATIVX build can read or sync these records.

## 4. Canonical data and provenance

Every imported measurement or event must preserve, where available:
- Authenticated member identity (server-derived; never trust a client-supplied owner ID).
- Provider/platform, source app, source device and external record identifier.
- Metric type, value, unit, start/end timestamps and source timezone.
- Recorded, received and last-synced timestamps.
- Permission/scope state, sync state and adapter/schema version.
- Quality classification: measured, estimated, manual, incomplete, duplicate, corrected or unavailable.

Keep raw provider records, workout sessions and derived daily summaries logically separate. Do not use a workout session as an extra contribution to a daily aggregate if the platform total already includes it.

Unknown, unavailable, denied, delayed, stale, zero and sync-failed are distinct states. Never turn missing data into zero or invent a value to fill a dashboard tile.

## 5. Source reconciliation rules

1. Prefer HealthKit's platform-aggregated daily totals for iOS and Health Connect aggregate results for Android where those APIs provide the relevant metric.
2. Never blindly add iPhone, wearable, Strava and direct sensor totals together.
3. Use provider record IDs for idempotency where available. Otherwise use conservative duplicate matching based on member, metric, interval, value, unit and known source relationships.
4. Keep workout events separate from daily totals.
5. Make source priority metric-specific; a provider trusted for steps is not automatically authoritative for sleep or heart rate.
6. Preserve source provenance and reconciliation decisions so a displayed value can be explained and audited.
7. A later sync must not overwrite a newer trusted value with an older measurement.
8. Retries and replayed imports must not create duplicate rows or inflate totals.
9. Do not silently merge incompatible units, timezones or day boundaries.
10. Manual entries and legacy records must remain available unless a member explicitly edits or deletes them under the product's data controls.

## 6. Workout lifecycle: critical correctness gate

Daily movement collection and intentional workout recording are separate systems. Starting or finishing a GPS workout must not start or stop all-day step collection.

Implement and test an explicit workout state machine:

`idle → recording → paused → recording → finishing → saved`

Error/recovery states must be explicit and recoverable. The UI must prevent invalid transitions and repeated finish actions.

**Finish-and-save acceptance criteria:**
- Finish is a single idempotent operation; repeated taps cannot create multiple sessions.
- Elapsed time and moving time stop at the correct instant.
- Location collection and workout timers stop after finish.
- The final valid route points, distance, timestamps, splits and available metrics are flushed before the session is marked saved.
- The session is durably saved locally before cloud upload is attempted.
- A visible completion summary is produced from the saved session, not from transient UI state.
- Cloud upload is retryable and idempotent; offline completion does not lose the local session.
- A failed upload is visibly pending/failed and retries later; it is never falsely marked synced.
- Relaunching the app recovers a session that was interrupted or saved but not yet uploaded.
- The saved session appears once in history and on the other signed-in platforms after cloud sync.
- Finishing a workout does not reset or stop the daily step counter.

This gate directly addresses the reported defect where walking mode records activity continuously but the finish action does not reliably complete and save the session.

## 7. Platform integration requirements

### iOS
- HealthKit is the primary source for permitted daily health aggregates and compatible third-party/wearable data written to Apple Health.
- Core Motion is a separate on-device movement capability; do not add overlapping Core Motion samples to HealthKit daily totals.
- Core Location records routes only during a member-started workout, subject to permissions and OS policy.
- Request only the data types needed, explain why, and support disconnect/revocation.
- Refresh on app foreground and use background delivery only as best-effort.
- Empty HealthKit results must not be presented as proof that access was denied; HealthKit intentionally limits what an app can infer about read denial.
- A successful unsigned CI build is not proof of a HealthKit-enabled signed install. Validate App ID capability, provisioning profile, entitlements and the actual installed build.

### Android
- Health Connect is the preferred aggregated health-data layer for supported metrics and providers.
- Request granular permissions and handle missing provider, unavailable records, revoked permissions and background restrictions.
- Keep daily aggregation separate from GPS workout capture.
- Do not rely on deprecated Google Fit APIs for new integrations.
- Verify on a physical Android device with the intended Health Connect provider and real permission flows.

### Web
- The web dashboard is a cross-platform view and interaction surface, not a substitute for native HealthKit or Health Connect permissions.
- Read canonical authenticated cloud records and label source/freshness.
- Do not imply that a Safari PWA can perform native HealthKit reads or guaranteed background GPS.
- A member must see the same saved history, goal progress and synced daily values after signing in on another platform.

## 8. Metrics and feature scope

| Metric / feature | Expected behaviour | Important constraint |
|---|---|---|
| Steps | Daily aggregate, history and goal progress | No cross-source double count |
| Walking/running distance | Daily aggregate and workout distance | Keep daily and workout totals distinct |
| Active energy | Measured platform value where available | Do not substitute basal energy |
| Basal energy | Separate wellness metric if product requires it | Never label as active calories |
| Heart rate | Time-stamped samples and supported summaries | No diagnosis or unsupported inference |
| Sleep | Measured asleep intervals/stages and duration | Merge overlapping intervals; preserve unavailable state |
| Walking speed/step length | Trends where sufficient samples exist | Explain sampling limitations |
| Walking asymmetry/double support/steadiness | Optional movement insight | Never present as diagnosis or fall-risk determination |
| Flights/elevation | Source-specific measurement | Do not equate flights climbed with GPS elevation gain |
| GPS route | Route, distance, pace, elevation where available | User-started session; permission and quality indicators |
| Water/food/protein | GATIVX-owned logging and reminders | Not supplied by this export; do not fabricate |
| Sedentary insights | GATIVX logic from permitted activity timeline | Respect privacy, quiet hours and user controls |
| GURU Mode | Explainable goal and habit guidance | Not a medical professional or diagnostic system |

## 9. Dashboard and GURU experience

Follow the approved GATIVX home direction in the design backlog:
- Premium, calm, glanceable dark canvas with GATIVX electric lime, cyan, violet and warm orange.
- Daily activity hero and compact steps, distance, active-calorie and wellness cards.
- Mission progress and focused quick actions.
- Prominent GURU Mode entry on home and as a first-class navigation destination.
- Clear source and freshness labels where available.
- Honest unknown states; no fabricated rings, zeroes, calories, heart points or sleep.
- Preserve the existing cinematic intro, goals, journal, GPS history, account access and data stores.

GURU guidance should use only available, consented and sufficiently fresh data. It should state when a recommendation is based on incomplete data and should avoid clinical or diagnostic claims.

## 10. Security, consent and data lifecycle

- Enforce Supabase row-level security and server-side ownership checks for all member records and sync functions.
- Use authenticated, least-privilege RPCs; revoke public/anonymous execution where inappropriate.
- Validate metric types, units, ranges, dates, timestamps and payload sizes at ingestion.
- Keep secrets out of client bundles, logs, repository history and test fixtures.
- Encrypt data in transit and at rest; restrict operational access.
- Provide clear per-provider connection, permission, sync freshness, disconnect and deletion controls.
- Never sell health or location data or expose it to advertisers.
- Log sync metadata and security events without logging sensitive raw health payloads.
- Review every database migration for additive/backward-compatible behaviour, RLS, grants, rollback/forward recovery and impact on existing rows.

## 11. Required automated test suite

### Unit and domain tests
- Unit conversion and rounding.
- Local-day boundaries, daylight-saving changes and timezone travel.
- Missing vs zero vs denied vs delayed vs stale vs error states.
- Source precedence and metric-specific trust.
- Duplicate detection, idempotent replay and late-arriving records.
- Overlapping sleep intervals and local wake-up-day attribution.
- Workout state transitions and invalid transition rejection.
- Finish tapped twice, finish while paused, app interruption and process relaunch.
- Route distance and timestamp ordering; segment breaks and invalid GPS points.
- Calories, pace and speed calculations with explicit units and provenance.

### Integration tests
- iOS HealthKit and Android Health Connect adapters using synthetic fixtures.
- Supabase authenticated sync, RLS ownership isolation and RPC grants.
- Offline queue, retry, backoff, replay and stale-write rejection.
- Local save followed by cloud upload and cross-device history refresh.
- Account switch/sign-out so one member's health data never appears in another member's session.

### Web/browser regression tests
- Correct root entry and full dashboard navigation.
- Sign-up, email verification, sign-in, session refresh and recovery.
- Activity start/pause/resume/finish and one saved history item.
- Dashboard rings, metrics, goals, journal and GURU entry.
- Water, food/nutrition and sleep unknown/recorded states.
- Source labels, freshness, loading, empty and error states.
- Existing local storage and legacy migration preservation.

### CI/release gates
- Format/lint, static analysis, type checks and dependency/security review.
- iOS project generation and unsigned build checks, clearly labelled as unsigned.
- Android build and tests.
- Web syntax/build and browser regression suite.
- Supabase migration lint/review and policy tests.
- No release if a required check is cancelled, skipped or failing without an explicitly approved, documented exception.

## 12. Physical-device acceptance matrix

| Scenario | iPhone | Android | Web |
|---|---|---|---|
| Fresh install, sign-in and account recovery | Required | Required | Required |
| Health permission grant, partial grant and revoke | Required | Required | Explain native-only boundary |
| Phone + wearable source overlap | Required | Required | Verify cloud total |
| Steps while app is backgrounded/locked | Required | Required | No unsupported promise |
| GPS walk, screen lock, pause/resume/finish | Required | Required | Test supported browser limits |
| Offline finish, relaunch and retry | Required | Required | Verify synced history |
| Same member signs in on another platform | Required | Required | Required |
| Different member signs in on same device | Required | Required | Required |
| Timezone/day-boundary change | Required | Required | Required |

Record device model, OS version, app build/commit, permission state, test case, expected result, actual result, evidence reference and tester. Do not attach raw personal health data or precise home routes to public CI artefacts.

## 13. Release readiness definition

A release candidate is ready only when:
- All required CI checks pass on the exact release commit.
- No known P0/P1 defects remain.
- Workout finish/save/retry passes on physical iOS and Android devices.
- Health permissions, aggregation, source reconciliation and sync pass with representative devices.
- Cross-platform account and history parity passes.
- Supabase migrations are reviewed and applied in the intended environment.
- Existing user data and legacy records are verified intact.
- Privacy, consent, access control and data deletion/export paths are checked.
- Web deployment and native signed build are verified separately.
- Remaining limitations are explicit and communicated honestly.

A green web test does not prove native permissions. An unsigned iOS build does not prove HealthKit entitlement. A successful local save does not prove cloud sync. A successful cloud sync does not prove correct cross-source reconciliation.

## 14. Delivery order

1. Audit main and every active PR; map changes, dependencies, checks and migrations before merging.
2. Fix and regression-test the workout finish/save lifecycle.
3. Validate HealthKit entitlement and signed iPhone installation; review PR #91.
4. Review measured sleep logic, migration and platform parity; review PR #90.
5. Validate source reconciliation against synthetic fixtures derived from the private export's schema.
6. Validate GPS route accuracy and the 73-route reference corpus locally without publishing personal routes.
7. Verify dashboard metrics, mission progress and GURU data contracts.
8. Complete iOS, Android, web and Supabase release gates.
9. Only then prepare a controlled release and monitor post-release errors and sync health.

## 15. Governing principle

Connect what is compatible. Ask permission. Preserve provenance. Reconcile rather than blindly add. Save before syncing. Retry without duplication. Show what is known, estimated, delayed or unavailable. Keep the member in control. Build the experience around the member's mission, not around a device brand.

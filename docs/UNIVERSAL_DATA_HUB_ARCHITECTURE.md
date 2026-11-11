# GATIVX Universal Data Hub
## Architecture decision record

Status: Proposed foundation for implementation  
Owner: GATIVX / Param IT Solutions  
Platforms: iOS, Android, web services and future partner integrations

## 1. Product objective

GATIVX is device-independent. A member may connect a phone, watch, ring, band, smart shoes, sports sensors and third-party fitness applications. GATIVX presents one trustworthy personal activity picture without requiring any single manufacturer.

The member, not the phone or wearable, is the centre of the system.

## 2. Core architecture

Use a provider-adapter architecture. Each integration translates its source into a common GATIVX measurement contract. Downstream services must not depend on a particular vendor's payload format.

Integration paths, in preferred order:
1. iOS HealthKit for Apple-platform health data and compatible apps/devices that write to Apple Health.
2. Android Health Connect for Android health data and compatible apps/devices that write to Health Connect.
3. Direct Bluetooth Low Energy (BLE) for supported nearby sensors and accessories.
4. Official manufacturer cloud APIs / OAuth integrations where available and contractually permitted.
5. Partner/developer API for approved external integrations.

Do not assume every vendor exposes every metric or supports background sync. Maintain a capability matrix per provider and device family.

## 3. Platform decisions

### iOS
- HealthKit is the primary source for consolidated daily health totals and supported third-party/device data.
- Core Motion provides on-device pedometer and motion capabilities where appropriate.
- Core Location is used for an explicitly user-started workout route, not ordinary daily step collection.
- Use HealthKit observers/background delivery where supported; refresh on app foreground because delivery timing is controlled by iOS.
- Respect HealthKit read permissions; the app cannot reliably infer every denied read permission from an empty result.

### Android
- Health Connect is the preferred aggregation layer for compatible apps and wearables.
- Native Android step-counter sensors may provide device-level measurements where available and permitted.
- Use platform-compliant background work and permissions; never promise uninterrupted recording when Android or device vendors restrict background execution.
- Do not build new integrations on deprecated Google Fit APIs when Health Connect or an official current API is available.

### Direct accessories
- BLE integrations are capability-specific. Use standard GATT services/profiles when supported; otherwise use documented vendor protocols.
- Do not scan or connect continuously without a user-visible need and permission.
- Prefer HealthKit/Health Connect ingestion when a vendor already synchronises there; add direct BLE only when it provides missing capabilities or materially better freshness.

### Manufacturer cloud
- Use official APIs, OAuth and least-privilege scopes.
- Store refresh credentials securely; never store provider passwords.
- Respect API rate limits, revocation, retention rules and vendor terms.
- A connector is not considered supported until its permissions, sync lifecycle, failure states and data mapping are tested.

## 4. Canonical measurement contract

Every ingested measurement/event must preserve:

- member_id (internal identity; never expose in public APIs)
- provider_id and provider_type
- source_device_id (when available), source_app and source_name
- metric_type (e.g. steps, distance, heart_rate, active_energy, sleep, workout, cadence, elevation)
- value and unit
- start_time and end_time in UTC, plus source timezone / local-day context when supplied
- source_record_id / external_id when available
- recorded_at, received_at and last_synced_at
- provenance, permission scope and sync status
- quality flags: measured, estimated, manually_entered, duplicated, corrected, incomplete
- schema_version

Use typed metric definitions and validated units. Never silently convert an unknown unit or discard source provenance.

## 5. Reconciliation and accuracy rules

- Never blindly sum all providers.
- Prefer platform-aggregated totals (HealthKit / Health Connect) for daily totals when the platform provides a deduplicated aggregate.
- Retain raw source records separately from derived daily summaries.
- Deduplicate using provider record IDs first; otherwise use conservative matching based on member, metric, time interval, value and source relationship.
- Do not count a workout's steps twice when those same steps already contribute to the platform daily total.
- Keep workout session records separate from daily aggregate records.
- Do not combine incompatible metrics or units.
- Make source priority metric-specific; a source trusted for heart rate may not be trusted for steps.
- Preserve conflicting source records and record the reconciliation decision so totals can be audited and corrected.
- Distinguish zero from unavailable, not-permitted, delayed and sync-error states.
- Label estimates and manual entries clearly.

## 6. Daily activity vs workout sessions

These are separate product concepts:
- Daily activity is passively accumulated from permitted health-platform/device sources, including incidental movement at home, work and outdoors.
- A workout is an intentional session started by the member. It may capture GPS, duration, pace, distance, workout-specific sensor readings and session steps.
- Starting or stopping a workout must never start or stop all-day step collection.
- Workout steps are not added again to a platform daily total.
- GPS must not run merely to count everyday steps.

## 7. Device and provider registry

Maintain a registry of:
- provider / manufacturer
- integration type (HealthKit, Health Connect, BLE, cloud API, partner API)
- supported platforms and device families
- supported metric capabilities
- authentication / permission requirements
- sync mode and expected freshness
- API / firmware / adapter version
- known limitations and validation status

Expose connection status to members: connected, permission-needed, syncing, delayed, disconnected, unsupported or error.

## 8. Security and member control

- Explicit, revocable consent for each provider and data category.
- Least-privilege access and secure token storage.
- Encrypt sensitive data in transit and at rest.
- Enforce strict member-level row ownership and access controls.
- Provide disconnect and data deletion/export workflows consistent with applicable policy and law.
- Never sell or expose raw health data to device partners.
- Keep audit logs for connector authorisation, sync and administrative access.
- Do not collect a metric simply because a device can provide it; collect only what the feature needs and the member permits.

## 9. Backend design direction

Keep the current Supabase foundation initially; avoid a costly platform rewrite before scale requires it. Add versioned tables/services incrementally:
- connected_providers / connected_devices
- provider_sync_state
- raw_health_records (or partitioned metric-specific raw tables as volume requires)
- daily_metric_summaries
- workout_sessions and workout_route_points
- integration_capabilities
- reconciliation_audit

Use idempotent sync operations, stable external IDs, incremental cursors/watermarks and retry-safe jobs. Keep raw ingestion separate from derived summaries. Add retention/partitioning and aggregation policies before high-volume rollout.

## 10. Open integration programme

Publish a versioned GATIVX integration specification and partner API only after authentication, consent, rate limiting, schema validation, tenant isolation and audit controls are in place.

Partner onboarding requires:
- documented capabilities and data mapping
- security and privacy review
- test fixtures and conformance tests
- duplicate/replay tests
- permission revocation tests
- background sync and offline recovery tests
- clear compatibility status

Use open standards where practical. Proprietary integrations require official, authorised access.

## 11. Delivery sequence

1. Audit existing iOS, Android and Supabase implementations; preserve all current data and account behaviour.
2. Define canonical schema, provider registry and source/provenance fields.
3. Stabilise iOS HealthKit daily totals and explicit workout recording.
4. Stabilise Android Health Connect daily totals and explicit workout recording.
5. Implement common reconciliation and duplicate prevention.
6. Add selected BLE accessory profiles based on member demand and test hardware.
7. Add manufacturer cloud connectors based on official API availability and commercial feasibility.
8. Publish partner/developer integration API after security review.
9. Add insights only after source quality and data completeness are measurable.

## 12. Acceptance criteria

The hub is not production-ready until:
- iOS and Android daily totals are sourced from the correct platform aggregation layer where available.
- incidental steps count without starting a workout.
- workouts are user-controlled and independent from daily collection.
- phone + watch / multiple-source overlap does not inflate daily totals.
- source, timestamp, unit and quality are inspectable for every imported metric.
- denied permissions, delayed sync, offline periods and revoked connections are handled visibly.
- existing users, history and cloud records survive upgrades.
- automated tests cover duplicate imports, replay, timezone/day-boundary handling, unit conversion and partial sync.
- real-device validation is completed on representative iPhone and Android hardware.

## 13. Non-goals and honest limitations

- Universal compatibility with every product cannot be guaranteed. Each device must expose data through a supported platform, standard protocol or authorised API.
- Background delivery is subject to OS scheduling, permissions, battery management and manufacturer restrictions.
- GATIVX must not claim clinical accuracy or medical diagnosis from consumer wearable data.
- No provider should be treated as a perfect source for every metric.

## 14. Governing principle

Connect what is compatible. Ask permission. Preserve provenance. Reconcile rather than blindly add. Show what is known, estimated, delayed or unavailable. Keep the member in control.

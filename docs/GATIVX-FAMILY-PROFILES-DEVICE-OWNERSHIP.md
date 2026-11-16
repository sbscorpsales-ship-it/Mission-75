# GATIVX Family Profiles, Device Ownership & Privacy Specification

Status: Accepted product direction (16 November 2026)  
Scope: Product and engineering specification. This document does not claim that family-profile functionality is implemented.

## Product decision

A family may use one GATIVX family account/subscription while each person has an independent member profile, personal health record, activity history, goals, and permissions. The family administrator sees family-level summaries by default, not private individual health details. A member must explicitly share additional details.

## Identity model

Keep these identities separate:

- **Family ID**: billing, invitation and family-group boundary.
- **Member ID**: the human whose activity and health record this is.
- **Device ID**: a registered physical phone, watch, ring, shoe sensor or other wearable.
- **Source account / provider connection**: the Apple Health, Health Connect or manufacturer account through which data is obtained.
- **Activity ID**: one real-world activity, with multiple sensor observations attached to it.

A device is never treated as proof of who is currently wearing or carrying it. Registration establishes the usual owner, not guaranteed current wearer.

## Required family behaviour

1. A family account can contain multiple member profiles.
2. Every activity must be owned by exactly one Member ID; family totals are derived views and never written back as an individual's health record.
3. A device can be assigned to a member, reassigned with an auditable effective time, or marked shared/unassigned.
4. Before starting an activity on a shared phone, GATIVX must require selection/confirmation of the active member. Do not infer the walker from the phone owner's login.
5. Sensor data must retain source, device, provider, timestamp, units, permission status and provenance.
6. Data from different members must never be deduplicated, fused, or merged into one activity merely because timestamps overlap.
7. A parent/guardian may manage a child's profile subject to applicable age, consent and platform rules. Child privacy and access controls must be explicit; do not assume the family administrator may inspect all health details.
8. Members can view and manage their own profile and connected devices, subject to guardian/legal requirements.
9. Removing a member or device must not silently delete historical records; provide an explicit retention/export/deletion flow.

## Sensor fusion and duplicate prevention

Sensor reconciliation is performed **within a member identity boundary only**.

- Match overlapping records using member ID, timestamps, activity context, source identifiers and (where available) spatial similarity.
- Select a primary route for each activity; do not add distances from parallel GPS tracks.
- Select/derive one consolidated step total; never sum overlapping device step totals.
- Prefer trustworthy category-specific measurements, preserve source readings and explain conflicts.
- Use heart-rate and other time-series data only when the source supports it and timestamps align.
- Keep raw observations and the selected canonical result separately for auditability.
- Late-arriving wearable data may enrich an existing activity but must not create a second activity for the same member and session.
- If identity is uncertain, quarantine the observation for confirmation rather than attaching it to a guessed person.

## Apple Health and Android health-platform boundaries

- HealthKit data is scoped to the iOS device user's Health data store and its granted permissions. A GATIVX family login does not grant access to another family member's HealthKit data.
- Health Connect data is similarly accessed under the Android device/user's permissions and app integration.
- Each person's data must be obtained from that person's own authorised health-data context and linked to that member's GATIVX identity.
- If one person carries another person's phone, the app must ask who is using it before recording. The device's HealthKit owner cannot be assumed to be the person walking.
- Manufacturer cloud integrations must use the provider's authorised account/member connection and explicit consent. Do not share one provider login across family members unless the provider expressly supports separate member profiles and scopes.

## Privacy and access defaults

| Role | Default access |
|---|---|
| Member | Own detailed health data, goals and activities |
| Family administrator | Family roster, invitation/device administration and aggregated family summaries |
| Parent/guardian | Child profile controls as permitted by applicable law/platform rules; detailed health access must be clearly disclosed and controlled |
| Other family members | No access to another member's detailed health data unless explicitly shared |

Family summaries should expose only the metrics needed for the chosen family feature. A member's precise GPS route, sleep, heart rate and medical/health details are private by default.

## Minimum data model (implementation target)

- `families(id, ...)`
- `family_members(id, family_id, auth_user_id, role, status, privacy_settings, ...)`
- `member_devices(id, member_id, device_type, provider, external_device_id, ownership_status, valid_from, valid_to, ...)`
- `provider_connections(id, member_id, provider, provider_subject_id, scopes, status, ...)`
- `activities(id, member_id, family_id, activity_type, started_at, ended_at, canonical_distance, canonical_steps, primary_route_source, status, ...)`
- `activity_observations(id, activity_id, member_id, device_id, source, metric, value, unit, observed_start, observed_end, provenance, ...)`
- `member_shares(id, owner_member_id, grantee_member_id, data_categories, permission, expires_at, ...)`

All server-side reads and writes must enforce member-level authorization (for example, Supabase RLS). Never trust a client-supplied member ID without verifying that the authenticated user is permitted to act for that member.

## Acceptance tests

1. Four family members use four devices in four different directions at the same time: four separate member activities are created.
2. The family dashboard can show an aggregate total, while each member's personal dashboard shows only their own records.
3. One member records the same walk on a phone, watch, ring and shoes: GATIVX creates one activity, not four, and does not sum duplicate steps or route distance.
4. A child uses a parent's shared phone: the app asks which member is walking and stores the activity under the selected member; it does not silently use the phone owner's identity.
5. Two members' records overlap in time and location: they remain separate because member identity differs.
6. A wearable sync arrives late: it enriches the correct member's existing activity without creating a duplicate.
7. A member revokes sharing: family access to the revoked categories is removed without corrupting the member's private record.
8. A user cannot query or modify another member's detailed records by changing a client-side member ID.
9. A device is reassigned: new observations follow the new assignment; historical observations retain their original owner and provenance.
10. Missing or ambiguous ownership never results in guessed attribution or fabricated metrics.

## Delivery sequence

1. Database schema, migrations, RLS policies and authorization tests.
2. Family creation/invitations and member profile lifecycle.
3. Device registration and ownership/reassignment workflow.
4. Per-member activity ingestion and member-scoped sensor reconciliation.
5. Family summary dashboard and explicit sharing controls.
6. Cross-platform tests for iOS, Android and web.

Do not present this feature as complete until the acceptance tests pass on the deployed backend and supported clients.

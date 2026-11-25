# GATIVX Design C Review Prototype

**Purpose:** A separate, interactive, visual-only review of the locked GATIVX cross-platform information architecture. It does not replace `app-v2.html`, the native iOS app, Android app, or any production entry point.

## Screens included

- Home — activity rings, steps, distance, calories, active minutes, mission, GURU, weekly progress and latest workout
- Activity — session controls and illustrative route/metrics
- Workouts — activity types and workout history
- Health & Progress — activity trends, wellness and honest unavailable-source states
- Community — groups, challenges and sample feed layouts
- GATIVX GURU — goal, purpose, emotion and one practical next action
- Missions — goal-linked mission and milestones
- Profile — account, preferences and privacy controls
- Connected Apps — Apple Health, Health Connect and planned provider states
- Notifications — sample notification and delivery settings

## Design baseline

This review follows `docs/GATIVX-FINAL-DAY-NIGHT-DESIGN-LOCK.md`: shared hierarchy, charcoal/soft-neutral surfaces, restrained lime/cyan/violet/orange accents, compact cards, clear metric hierarchy and Day/Night variants. The primary navigation follows Home, Activity, Workouts, Health/Progress and Community. GURU, Missions, Profile, Apps and Notifications remain reachable as supporting screens.

## Safety and limitations

- The review is static sample content with client-side screen navigation only.
- All example metrics and member/feed content are explicitly labelled illustrative.
- It does not access accounts, Supabase, HealthKit, Health Connect, GPS, sensors, push notifications or device storage.
- The Start Walk and GURU buttons show a disclosure rather than performing real activity or coaching.
- This is not a production deployment or evidence that the missing product modules are implemented.

## Automated review

`scripts/design-review-smoke.mjs` checks all ten screens, mobile overflow, Day/Night switching, period selection, preview-only disclosures and browser errors. It captures one 390x844 screenshot per screen in the `GATIVX-Design-C-Review-Screenshots` CI artifact.

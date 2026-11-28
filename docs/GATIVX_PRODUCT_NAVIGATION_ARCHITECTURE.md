# GativX™ Product Navigation & Information Architecture

Status: Founder direction captured; implementation baseline and acceptance rules.
Date: 2026-11-28

## Product principle

GativX™ is a multi-screen product, not a single long webpage and not a six-tile feature directory. Use a small number of primary destinations with meaningful nested destinations inside each. A feature has one canonical home. Other screens may show a compact summary or a deep link, but must not duplicate the full feature.

Preserve the founder-approved Design C direction: balanced iOS-first composition, portrait-first, premium and vibrant with restrained neon/lime accents, clear hierarchy, generous spacing, and deliberate screen boundaries. Do not redesign the approved visual identity while implementing navigation.

## Primary navigation

Use five primary destinations:

1. Home
2. Mission
3. Activity
4. Guru
5. Profile

Each destination must open a real screen. Do not leave feature tiles that only change a status label. Do not show "Available", "Testing", or "Coming soon" as substitutes for working destinations.

## Screen ownership and nested destinations

### 1. Home — daily command centre
Canonical content:
- Greeting and member identity (when signed in)
- Today's goal and concise progress
- Compact today's activity snapshot (steps, active energy, heart points only when genuinely available)
- Primary GativX™ Activity action and active-session state
- One relevant Guru insight / next action
- Shortcuts to the owning screens

Home is a summary, not the full activity history, food diary, sleep dashboard, or content library.

### 2. Mission — purpose, goals and commitments
Nested destinations:
- My Purpose / My Why
- Goal setup and goal periods: 30, 90, 180 and 365 days
- Mission challenges (including personal challenges)
- Milestones and progress
- Habits and daily commitments
- Achievements

Mission owns the user's goals, reasons and commitments. Guru may coach the user about a mission but must not become a second goal editor.

### 3. Activity — measured movement and exercise
Nested destinations:
- Today's Activity
- GativX™ Activity live tracking
- Walking / running sessions
- Activity history and session details
- GPS routes and route maps
- Strength and workout records
- Movement insights and trends
- Connected activity sources and sync diagnostics

Activity owns steps, recorded movement, workouts, routes and session history. Do not repeat full step/calorie/heart-point dashboards on every tab. Display only compact, clearly labelled summaries elsewhere.

Data rules:
- Prefer measured device/provider values and show their source and freshness.
- Unknown or unavailable values remain unknown; never invent sample values or silently estimate.
- Clearly distinguish device-measured totals from a GativX™ Activity session's own values to avoid double counting.
- Permission denial, disconnected providers, empty history and sync failure each need explicit useful states.
- Preserve existing local records and account ownership during navigation refactors.

### 4. Guru — coaching and wellbeing companion
Nested destinations:
- Guru Coach: purpose-led coaching, reflection and practical next action
- Wellness Overview
- Recovery: sleep, rest, readiness and stress (only show metrics when supported by a connected or entered source)
- Nutrition: food diary, nutrition guidance and dietary goals
- Hydration
- Mind & Meditation: meditation, self-control and emotional wellbeing
- Music Library
- Guided Videos
- Podcasts / Audio Guidance
- Learning Library: habits, NLP, discipline and personal development
- Daily guidance / routines

Guru owns guidance, wellbeing practices and curated learning/media. Nutrition and recovery tracking belong under Guru > Wellness; measured steps, GPS walks and workouts remain under Activity. Media content must be lawfully available and clearly labelled by source; do not imply a paid/streaming catalogue is free or licensed unless verified.

Guru's core behavior: reconnect the member to the purpose and emotion behind their goal when motivation drops, then offer one small achievable next action. Do not use generic motivational filler as a substitute for contextual guidance.

### 5. Profile — identity, account and app configuration
Nested destinations:
- Personal profile
- Account and sign-in/security
- Connected devices and health permissions
- Data sources and privacy controls
- Language and accessibility
- Notifications
- Appearance (system / light / dark)
- Subscription and billing (only when implemented)
- Referrals and rewards (only when implemented)
- Help, support and about GativX™
- Company information: Param IT Solutions, Belgaum; company vision, mission and values

Profile owns identity and settings. Referral and reward features must not appear as functional if their flows and backend are not implemented.

## Secondary capabilities and placement

- Community: a nested destination accessible from Home and Mission, with its own screen and clear community/challenge purpose. Promote to a primary destination only if usage justifies it.
- Motion 3D: a movement visualisation inside Activity session details or movement insights, not a standalone placeholder tab.
- Rewards: Mission achievements or Profile > Rewards, depending on whether the item is an earned achievement or an account/redeemable benefit. Do not conflate the two.
- Referrals: Profile > Referrals.
- Settings: Profile > Settings; never a redundant primary tab.
- Strength: Activity > Strength.
- Music, videos and podcasts: Guru > Library.
- Diet, nutrition, hydration, sleep and recovery: Guru > Wellness.
- Daily steps, calories, heart points, walking and GPS: Activity, with only a compact snapshot on Home.

## Navigation and visual behavior

- Use a persistent, clearly labelled bottom navigation for the five primary destinations on phone layouts.
- Nested destinations open as distinct screens with a clear title and back navigation; do not stack every section into one endless vertical page.
- Use cards only when they help grouping or action. Avoid a grid of inactive feature tiles as the main experience.
- Keep primary actions obvious; use consistent spacing, typography, iconography and restrained accent color.
- Support Android back navigation and state restoration. Do not lose an active GativX™ Activity session when changing screens.
- Keep accessibility: readable contrast, touch targets, text scaling and meaningful labels.

## Implementation truth and release gates

This document defines intended product architecture; it does not claim all destinations are implemented. Existing Android code currently combines Health Connect, GativX™ Activity, authentication and status panels in one scrollable Compose screen, and the feature hub contains tiles whose taps only update selection/status. The refactor must reuse the existing working data/service logic while moving UI responsibilities into real destinations.

A destination is complete only when:
1. It opens through real navigation.
2. Its core action works end-to-end or it presents an honest empty/permission/unavailable state.
3. It uses real user/device/backend data, never fabricated demo data presented as live.
4. Loading, error, offline and permission states are designed.
5. It does not duplicate another destination's canonical data.
6. Tests cover navigation and key state transitions.
7. The exact commit's CI succeeds; physical device acceptance is reported separately.

Do not claim the five destinations or nested modules are complete merely because navigation labels or placeholder cards exist. Implement in vertical slices and verify each slice before expanding scope.

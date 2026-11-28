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


## GativX™ Six-Pillar Transformation Engine

The six pillars are the permanent member transformation framework. Preserve the exact pillar names and order:

1. **G — Goal**
2. **A — Aim**
3. **T — Train**
4. **I — Inherit**
5. **V — Vigour**
6. **X — Xcellence**

Do not replace, merge, reorder or rename these pillars. The branded spelling is **GativX™**. The branded outcome word is **Xcellence**; ordinary explanatory prose may use the standard word “excellence”.

### Member-facing philosophy

“Dream with a Goal & Aim with purpose, Train with commitment to Inherit the discipline, perform Vigorously till you achieve Xcellence.”

This is the founder's motivational expression. Preserve its meaning and the six pillar words in brand materials. In polished editorial copy, grammar may be improved without changing the six pillar names or their sequence.

### Pillar intent and member outcomes

- **Goal — discover the dream:** Help the member name a personally meaningful desired outcome, understand why it matters and define a clear starting point.
- **Aim — connect to purpose:** Help the member articulate the personal reason, values and desired life impact behind the goal. Capture the member's own words; do not invent emotional motivations.
- **Train — create the methodology:** Guru translates the goal, current baseline, available time, preferences and constraints into a realistic plan, small daily actions, milestones and review cadence. Training methods must be appropriate to the goal and the member's stated capabilities.
- **Inherit — internalise discipline:** Help the member repeat useful actions until they become sustainable habits and part of their self-identity. Treat “inherit” as the founder's metaphor for internalising discipline, not a claim that discipline is biologically inherited.
- **Vigour — perform vigorously and improve:** Encourage energetic, consistent effort and personal bests. Compare progress against the member's own baseline and history rather than pressuring them to compete with others.
- **Xcellence — achieve and evolve:** Recognise verified milestones, reflect on what the member learned, celebrate progress and invite the member to choose the next meaningful goal.

### Onboarding and discovery conversation

Onboarding is a guided conversation, not a long compulsory questionnaire. Ask one useful question at a time, explain why it matters and allow the member to skip or revisit nonessential questions.

Capture, with explicit member confirmation:
- Goal statement and goal category.
- Why the goal matters, in the member's own words.
- Desired outcome and target date or review horizon.
- Starting baseline and confidence level, where relevant.
- Available time, preferred schedule and practical constraints.
- Skills, resources, support and barriers.
- Preferred coaching tone and check-in frequency.
- First small action the member is willing to take.

Do not infer sensitive personal motivations. Do not require members to disclose private family, medical, financial or emotional details to use the product. Ask only for information relevant to the chosen goal.

### Guru coaching loop

Guru is the guide and methodology partner; the member retains agency and ownership.

1. **Discover:** Clarify the Goal and Aim through the member's own answers.
2. **Plan:** Build a realistic Train methodology with an achievable first action.
3. **Practise:** Support the member in repeating actions and building Inherit-stage habits.
4. **Review:** Use actual activity, completed actions and member reflections to understand progress.
5. **Reconnect:** When a member misses a commitment or reports low motivation, respectfully remind them of the purpose they chose, acknowledge the setback without shame, and offer one small next action.
6. **Adapt:** Ask before materially changing the plan; adjust for new constraints, injury, illness, workload or a changed goal.
7. **Recognise:** Celebrate evidence-based progress and help the member set the next milestone.

### Personalisation and data integrity

- Keep each member's goals, purpose statements, coaching history and plans scoped to that member's authenticated account.
- Respect consent, privacy controls, deletion requests and data minimisation.
- Clearly distinguish member-entered reflections, device-measured activity and Guru-generated suggestions.
- Never fabricate a completed action, activity reading, streak, milestone or achievement.
- If data is unavailable, say so and offer a manual check-in where appropriate.
- Do not treat a missed day as failure or reset a member's identity, progress or worth.
- Never use shame, fear, humiliation, coercive “brainwashing”, manipulative streak pressure or claims that a member must obey Guru.
- Encourage sustainable effort, rest and safe modification. For health or exercise goals, avoid medical diagnosis and adapt recommendations to stated limitations.

### Required product surfaces

- **Mission:** Owns Goal, Aim, the purpose statement, milestones and commitments.
- **Guru:** Owns discovery prompts, personalised methodology guidance, habit coaching, purpose reconnection and reflective check-ins.
- **Activity:** Supplies verified movement and workout evidence when relevant; it does not define the member's purpose.
- **Home:** Shows one relevant next action and a concise, truthful progress summary.
- **Profile:** Provides controls for coaching preferences, consent, connected data and privacy.

### Acceptance criteria for the first vertical slice

The first implementation is not complete until:
1. A member can create and save a Goal and their own Aim/purpose statement.
2. The app preserves all six pillar names and their order in the member journey.
3. Guru can turn the saved Goal, baseline and constraints into a small actionable Train plan.
4. The member can accept, edit, skip or pause suggested actions.
5. A check-in can record completion, difficulty or a missed action without fabricating data.
6. Guru can reconnect the member to their saved purpose and suggest one manageable next action.
7. The member can review progress and change or retire a goal.
8. Data is account-scoped and survives app restart and supported sync paths.
9. Tests cover onboarding, persistence, plan generation states, check-ins, missed-action recovery, privacy boundaries and navigation.
10. CI passes for the exact proposed commit; physical-device testing is reported separately.

Implement this as a measured vertical slice. Do not represent a prompt, static card or mock response as a working Guru intelligence feature.

# GATIVX — Design & Product Ideas Backlog

**Purpose:** A durable parking place for every design reference, interface idea, feature concept, interaction, and product-model instruction shared by the founder. Capture first; prioritize and implement at the right time. Do not silently discard ideas because they are not in the current sprint.

**Product owner:** Param IT Solutions, Belgaum  
**Product:** GATIVX  
**Guiding rule:** Functionality and accuracy first. Design enhancements follow without compromising working features, member data, accessibility, or performance.

## How to manage incoming ideas

1. Record each new idea with the date, source/reference, intended benefit, and any explicit constraints.
2. Tag it as Approved, Backlog, Explore, Blocked, or Implemented.
3. Do not implement every new idea immediately. Compare it against current priorities, dependencies, effort, user value, and risk.
4. Preserve the original idea and wording even when a later version is refined; record the decision rather than overwriting the history.
5. Before implementation, decide what changes, where it belongs, when it is appropriate, how it works, and why it improves the member experience.
6. Never allow a design experiment to break GPS recording, step accuracy, HealthKit/cloud sync, saved records, or existing account access.
7. Review this backlog at each meaningful product milestone and when the founder asks to revisit ideas.

## Approved home-page direction — 9 November 2026

**Status: Approved direction; implementation under test**

Reference: Founder-provided iPhone Apple Fitness Summary screenshot shared in ChatGPT on 9 November 2026. Use it as a layout and information-hierarchy reference, not as a pixel-for-pixel copy.

### Visual principles
- Simple, premium, calm, powerful fitness-summary experience.
- Dark black/charcoal canvas and rounded charcoal cards.
- GATIVX's own palette: electric lime, cyan, violet, and warm orange.
- Clear typography, strong metric hierarchy, generous spacing, compact cards, easy one-handed iPhone use.
- Preserve GATIVX branding and the original cinematic intro; intro should lead into the summary home.
- Keep the page useful at a glance rather than crowded with every available metric.

### Home information architecture
- A clear daily activity summary/hero at the top.
- Compact metric cards for steps, walking distance, active calories, and daily wellness.
- Mission/progress card and focused quick actions below.
- A prominent GURU Mode entry on the home page.
- GURU is also a first-class bottom-navigation destination.
- Use honest unknown states: never fabricate steps, calories, distance, heart points, or other measurements. Identify the data source and freshness when available.

### GURU Mode direction
- A visible, welcoming guidance experience that helps a member move from goals to action.
- The home-page GURU card is an entry point, not a claim that the complete AI coach is already finished.
- Full conversational intelligence, personalized plans, and deeper coaching workflows remain future implementation work until built and tested.

### Implementation guardrails
- Keep the existing goals, journal, GPS tracking, route segmentation, saved walks, account access, and data model working.
- Preserve browser storage, legacy records, auth sessions, and cloud records. No destructive resets or migrations.
- Mobile-first layout, responsive on larger screens.
- Test intro-to-home routing, navigation, metric rendering, unknown-data states, GPS controls, storage preservation, and browser errors before deployment.
- Do not ask the founder to perform real-device testing until the core build and automated checks are ready. Real-device acceptance testing will still be required for HealthKit permissions, background delivery, GPS, and actual sensor readings.

## Future idea intake

Add every new founder idea below as a dated entry. Keep ideas here even when deferred.

| Date | Idea / reference | Intended benefit | Priority / status | Decision / dependencies |
|---|---|---|---|---|
| 2026-11-09 | Apple Fitness-inspired GATIVX summary home with GATIVX colors and GURU Mode | Simple yet powerful, glanceable home experience | Approved direction / Under test | Complete responsive/browser checks; retain original intro and all core functionality |

## Current design work

- PR #35: initial summary-home implementation and GURU entry. Browser checks passed on its head branch; integration into the latest main branch is being reconciled because the original PR branch is not cleanly mergeable.
- Current integration branch: feat/gativx/idea-backlog-and-summary-home.
- Do not mark this design as deployed until the integration branch passes its full checks, is merged, and the live Pages deployment is verified.

## Decision log

- 2026-11-09: Founder asked that new design ideas and models be safely retained for later selection, rather than implemented immediately simply because they are exciting. This backlog is the project-level source of truth for deferred ideas.

# GATIVX Final Design Lock — Day & Night

**Status:** Product-owner approved baseline  
**Decision date:** 2026-11-15  
**Scope:** iOS, Android, and Web  
**Product:** GATIVX — From Goals to Xcellence

## 1. Product decision

The GATIVX premium dashboard direction is FINAL and LOCKED. The approved direction is a unified hybrid of the premium visual concepts: athletic performance clarity, elegant wellness readability, and a powerful analytics command-centre experience.

There is one GATIVX product design system and one shared information architecture across iOS, Android, and Web. Day Mode and Night Mode are the only approved appearance variants.

Do not redesign, reinterpret, simplify, rearrange, or introduce a competing visual direction. Do not ask the product owner to choose again.

## 2. Non-negotiable design invariants

- Preserve the approved overall composition, hierarchy, navigation model, card language, activity-ring treatment, chart language, GURU coaching presence, and premium GATIVX brand identity.
- Preserve the same information architecture and feature hierarchy across platforms.
- Preserve the same component geometry, spacing scale, typography roles, icon style, corner treatment, and interaction patterns wherever the platform permits.
- Do not add/remove/reorder dashboard modules or change the visual concept as part of routine implementation.
- Do not substitute a generic template or clone another fitness brand.
- Do not introduce a third visual theme or platform-specific redesign.
- Any proposed design change requires explicit, fresh product-owner authorization. Routine engineering must work within this locked baseline.

## 3. Day Mode

- Bright, premium, calm, highly legible surface.
- White / soft-neutral backgrounds and refined card surfaces.
- GATIVX neon-lime / green brand accents used with restraint.
- Dark, high-contrast text and clear data hierarchy.
- Supporting semantic colours for sleep, hydration, recovery, and health indicators.
- No excessive gradients, shadows, decoration, or visual clutter.

## 4. Night Mode

- Deep charcoal / midnight surfaces, not flat harsh black everywhere.
- Same layout, components, hierarchy, spacing, and navigation as Day Mode.
- Neon-lime / green GATIVX accents, with restrained supporting colours.
- Comfortable contrast and readable muted text.
- No glow effects that reduce readability or distract from health data.

## 5. Shared dashboard information architecture

The dashboard retains the approved premium composition and includes:
- Brand header, profile and notifications.
- Today / Week / Month / Year context.
- Activity rings and goal progress.
- Steps, distance, calories, active minutes, and heart/activity points where supported.
- Latest workout and GPS route preview where a real route exists.
- Sleep, recovery, hydration, and sedentary insights where valid source data exists.
- Weekly and monthly progress analytics.
- GURU daily coaching, goals, and recommendations.
- Consistent primary navigation for Home, Activity, Workouts, Health/Progress, and Community.

The exact module content may be conditionally unavailable when a metric has no valid source data; the layout must show a clear empty, permission, or syncing state rather than fabricated values.

## 6. Cross-platform rules

- iOS, Android, and Web must share the same design tokens and component specifications.
- Responsive reflow is allowed only when required by screen size, safe areas, browser viewport, or platform conventions. Reflow must preserve the same hierarchy, module order, component identity, and visual intent; it is not permission to redesign.
- Use native accessibility and interaction conventions without changing the product's visual identity.
- Day/Night preference must persist per user and synchronize where appropriate; respect system appearance as the initial default unless the user has selected a preference.
- Theme changes must not alter data, calculations, permissions, tracking, or sync behaviour.

## 7. Data integrity and trust

All displayed metrics must come from validated GATIVX records or explicitly connected health sources. Mock figures in design mockups are illustrative only and must never appear as real member data.

- Never fabricate steps, calories, distance, sleep, recovery, heart points, hydration, routes, or progress.
- Clearly distinguish live, synced, estimated, and unavailable values.
- Show permission, stale-data, offline, and syncing states honestly.
- Respect source provenance, deduplication, and canonical metric reconciliation.
- Keep health data private and never expose raw health samples in logs or public UI.

## 8. Quality and release gates

The design is not considered implemented until:
- Day and Night modes are verified on iPhone, Android, and Web.
- Shared layout and module hierarchy are checked at supported viewport sizes.
- Text contrast, dynamic text sizing, screen readers, focus states, and reduced-motion behaviour are validated.
- Charts and rings use real data and correctly represent empty/loading/error states.
- Theme preference persists correctly.
- Cross-platform account data parity remains intact.
- Visual regression checks cover core screens in both themes.

## 9. Change control

This document is the authoritative design baseline. Any implementation that changes the approved layout, hierarchy, visual identity, or component language is out of scope unless the product owner explicitly reopens the design decision. Engineering may fix defects, improve accessibility, and adapt responsively only while preserving the approved design.

**Final directive:** Build the locked GATIVX design faithfully in Day and Night modes across iOS, Android, and Web. No further design-selection round.

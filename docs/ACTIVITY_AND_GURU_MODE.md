# GATIVX Activity, Heart Points and Guru Mode

Status: product implementation specification; not a claim that every connector or metric is live.

## Dashboard principles

- Keep the daily overview compact and readable on mobile.
- Show the user's mission and a small set of daily metrics first.
- Use detail tabs for logs, trends, coaching, GPS walks, and data settings.
- Missing values display as an em dash / "Not recorded", never as a measured zero.
- Every imported metric must expose its source and last successful sync time.
- Distinguish measured, manually entered, and estimated values.

## Daily activity metrics

1. Steps
2. GATIVX Heart Points
3. Active minutes
4. Distance
5. Water
6. Protein

Heart Points and active minutes must remain unavailable until a supported source provides sufficient activity-intensity evidence. Do not infer intensity from step count alone.

## GATIVX Heart Points: proposed scoring contract

- Moderate-intensity activity: 1 point per eligible minute.
- Vigorous-intensity activity: 2 points per eligible minute.
- Count only supported workout or activity intervals with reliable intensity classification.
- Do not award points from steps alone, passive heart-rate readings, or unverified manual claims.
- Deduplicate overlapping workout intervals across sources before scoring.
- Store source, source record identifier, interval start/end, intensity class, scoring-rule version, and calculation timestamp.
- Label the score "GATIVX Heart Points"; do not imply it is identical to Google Fit Heart Points.
- Explain the calculation in the app and let users inspect contributing sessions.
- This is a wellness engagement metric, not a medical measurement or diagnosis.

## Source and reconciliation rules

- iOS: use HealthKit aggregate step statistics and supported workout / exercise / heart-rate records, subject to permissions and iOS background limits.
- Android: use Health Connect aggregate APIs and supported exercise / heart-rate records.
- Use platform aggregate totals for steps; never sum overlapping phone and wearable step samples in app code.
- Match workouts by source identifiers where possible, then time overlap, activity type, duration, and distance.
- Never sum heart-rate or HRV samples across devices. Preserve source provenance.
- Keep raw imported records separate from canonical daily rollups.
- Missing, denied, delayed, and disconnected data are distinct states; do not convert them to zero.
- Show last sync time and a clear retry / reconnect path.

## Guru Mode

Guru Mode should provide one prioritized next action with:
- What the app observed (and its source / confidence).
- Why the suggestion is relevant.
- A small action the user can realistically take.
- A supportive alternative when data is incomplete or the user needs rest.

Guidance should adapt to the user's chosen mission and recorded habits. Avoid shame, streak pressure, diagnosis, treatment, medication advice, or unsupported health claims.

## Acceptance checks

- No activity metric displays zero when no record exists.
- A zero is shown only when a source explicitly reports a measured zero for that date.
- Repeated imports are idempotent.
- Two overlapping phone/watch records do not inflate steps, distance, workout minutes, or Heart Points.
- Manual entries remain labelled manual.
- Users can see source and sync status.
- Existing local and cloud records remain intact during rollout.
- Test with no data, one source, multiple overlapping sources, delayed sync, permission denied, and timezone/day-boundary cases.

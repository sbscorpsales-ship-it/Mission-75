# GATIVX Independent Activity Engine — v1.1.2

## Product rule
GATIVX owns its calculations. Apple Health, Health Connect, Strava and wearables
are optional measured-data providers and comparison sources, never prerequisites.
Every metric carries provenance: measured, estimated, or unavailable.

## Inputs
Required for a walking calorie estimate: member weight (kg), moving duration (minutes), and either average moving speed (km/h) or walking cadence (steps/min). Optional: average grade (decimal), heart rate (bpm), and activity type. Cadence-only walking estimates are available without GPS. This version supports walking only; running, hiking and other activities must return unavailable until validated activity-specific equations and golden fixtures are added. Never apply walking MET anchors to another activity type.
GPS distance is preferred for outdoor speed. Pedometer distance is fallback
using a member-calibrated stride length. Do not add GPS and pedometer distances.
Moving time excludes pauses/stops; keep elapsed time separately.

## Calorie method
For walking at 3–6 km/h, use the ACSM walking VO2 equation:
VO2 (ml/kg/min) = 0.1 × speed(m/min) + 1.8 × speed(m/min) × grade + 3.5.
For walking outside that band, interpolate level-walking MET anchors in the JS engine with a conservative grade correction. The 6.0 km/h interpolation anchor is pinned to the ACSM boundary value (13.5 / 3.5 MET) so the model does not jump when speed moves just above 6 km/h. MET = VO2 / 3.5. When speed is unavailable but cadence is available for walking, use the simple cadence metabolic equation from Moore et al. (2021): VO2 = 1.811 + 0.02014 × cadence + 0.0007427 × cadence² (ml/kg/min); MET = VO2 / 3.5. Use only 40–140 steps/min; outside this study-supported operating range, return unavailable rather than extrapolate. Cadence-derived estimates assume level walking and cannot infer hills.
Gross kcal = MET × 3.5 × weight(kg) × minutes / 200.
Active kcal = max(0, gross kcal − resting kcal), where resting kcal uses 1 MET
over the same duration. Retain full precision internally; round for display.
If a provider supplies active energy for the same period, select that measured
value for display; never sum it with the estimate. Keep both for comparison.

The ACSM equation is a model, not an individual calorimeter. Terrain, gait,
fitness, load, temperature and sensor error affect real expenditure. The 2024
Adult Compendium provides reference MET categories. Never promise universal
±1–2% accuracy without calorimetry validation.

## GATIVX Activity Points
Benchmark the GATIVX-branded score to Google's published guidance:
- Heart rate: estimated max HR = 205.8 − 0.685 × age.
  Moderate = 50% to <70% max HR; vigorous = ≥70%.
- Otherwise MET: moderate = 3.0–<6.0; vigorous = ≥6.0.
- If MET unavailable for walking: cadence 100–129 steps/min = moderate;
  ≥130 = vigorous.
- Moderate minute = 1 point; vigorous minute = 2 points; light = 0.
Do not label this as Google's official Heart Points. The engine supports interval-level classification so mixed-pace sessions do not receive one intensity score for the entire walk. Production tracking should store time-stamped intervals; session-average inputs remain a fallback.

## Rings
Progress arc = clamp(value / goal, 0, 1); display actual value above goal.
Goals are member settings. Show zero only for a real zero; use unavailable state
when inputs are missing.

## Data integrity
Use one canonical daily step total. GPS and step-derived distance are alternatives.
Deduplicate overlapping sessions/imports. Store raw inputs, engine version, output,
source and timestamp. Never silently rewrite historical estimates. Preserve UTC
timestamps and local-day boundaries.

## Validation gates
1. Golden unit tests pass on web, Swift and Kotlin ports.
2. Compare identical sessions against Apple, Google Fit/Health Connect and Strava.
3. Report MAPE, signed bias and limits of agreement for calories, distance,
moving time and activity points.
4. Initial calorie target: aim for ≤10% median absolute percentage error on a
controlled reference set; investigate >20% outliers. ±1–2% is not a defensible
universal promise for consumer estimates.
5. GPS distance target: ≤2% against a surveyed course in good sky conditions;
report poor GPS separately.
6. Activity points match the published rule exactly when inputs are identical.
7. Never calibrate global formulas to one person's weight or sessions.

## Platform plan
Web loads this engine when measured active energy is absent for supported walking sessions. Running, hiking and other activity types remain unavailable until activity-specific models are validated. iOS and Android receive equivalent Swift/Kotlin ports using the same constants and golden fixtures. HealthKit and Health Connect remain optional measured overrides.

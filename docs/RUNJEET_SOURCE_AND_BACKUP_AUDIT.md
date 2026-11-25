# RunJeet source and backup inspection — 18 November 2026

## Files received and inspected

The uploaded `RunJeet.zip` contains exactly:
- `index.html`
- `styles.css`
- `app.js`
- `manifest.webmanifest`
- `sw.js`
- `icon.svg`
- `README.md`

This is a standalone static PWA, not a native iOS project and not an IPA.

## Verified capabilities in this source

- Motion-event step estimation while the page is active.
- Browser Geolocation route sampling while the page is active.
- Start, pause/resume, finish, elapsed time, distance and pace.
- IndexedDB local persistence.
- JSON backup export/import.
- Service-worker app-shell caching.

## Verified limitations

- No Apple Health / HealthKit integration.
- Motion-based step detection is explicitly an estimate, not a hardware pedometer.
- The README warns that iOS may suspend browser GPS/motion in background or when locked.
- No cloud account or automatic cloud sync.
- Calories are intentionally unavailable rather than fabricated.
- Existing code uses its own IndexedDB database name `runjeet-fresh-v1`; GATIVX must not silently treat it as the same database.

## Backup inspection

Received file: `runjeet-backup-2026-11-18.json`

- App/schema: RunJeet / schema 1
- Export timestamp: 2026-11-18T07:10:00.883Z
- `stepsByDay`: empty object (no daily step totals in this export)
- `sessions`: one saved session
- Session ID: `c79090d9-9753-4fab-8183-426f2ceec150`
- Duration: 12 seconds
- Distance: 0 metres
- GPS points: empty
- Session steps: 0
- No active session

This backup is valid as a minimal migration test fixture, but it contains no recorded route or step history to populate the GATIVX dashboard.

## Safe integration approach

1. Keep this PWA source as a preserved reference until the consolidated GATIVX implementation has equivalent tested behavior.
2. Implement a versioned, non-destructive importer for RunJeet schema 1; preserve source session IDs and timestamps, deduplicate by ID, validate numeric fields, and never overwrite larger/previously imported totals.
3. Map RunJeet sessions into GATIVX's canonical activity model through an explicit adapter rather than copying the standalone UI or creating a second app.
4. Keep motion-event estimates visibly distinct from HealthKit-authoritative step totals.
5. Build native HealthKit, Core Motion and Core Location integration in the iOS app; do not claim the PWA provides those native capabilities.
6. Test import/export round trips and device-level start/pause/finish/save before retiring any existing app.

## Acceptance note

The supplied backup can verify importer behavior for an empty daily-step map and one zero-distance session. It cannot prove GPS tracking, HealthKit sync, background tracking, or non-zero step import.

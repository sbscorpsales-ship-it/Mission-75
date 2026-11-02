MISSION 75 — iPhone PWA starter

Files:
- index.html: working daily fitness tracker
- manifest.webmanifest: home-screen app metadata
- sw.js: basic offline cache
- icon.svg: app icon

To install on iPhone:
1. Host these files on an HTTPS static host (for example GitHub Pages).
2. Open the published HTTPS address in Safari.
3. Tap Share → Add to Home Screen → Add.
4. Launch MISSION 75 from the Home Screen.

Data is saved in Safari local storage on this device/browser. Export a JSON backup regularly. Clearing Safari website data may erase entries. This is not yet Apple Health, GPS background tracking, or Strava-connected.


GPS UPGRADE (v2):
- Adds foreground GPS walking sessions: Start, Pause/Resume, Finish & Save.
- GPS requires HTTPS and explicit browser location permission.
- Keep Mission 75 open and the screen active while recording; iOS may suspend browser GPS in the background.
- Completed GPS sessions are stored locally under mission75.gps.sessions.v1.
- Export backup includes both daily logs and GPS sessions.
- This is NOT native Apple Health/HealthKit integration and does NOT provide reliable background GPS.
- Existing daily log storage key mission75.logs.v1 is preserved.

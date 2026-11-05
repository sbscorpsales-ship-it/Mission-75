GATIVX — From Goals to Xcellence
Developed by Param IT Solutions, Belgaum, India.

PRODUCT TRACKS
- Web app: GitHub Pages PWA at https://sbscorpsales-ship-it.github.io/Mission-75/
- Native iPhone companion: SwiftUI + HealthKit in /ios. It is a separate iOS build and is not deployed by GitHub Pages.
- Shared cloud: Supabase Auth and account-scoped records.

WEB APP
- index.html: daily logs, mission dashboard, habits, GPS walk recorder and account/cloud controls.
- manifest.webmanifest and sw.js: home-screen install metadata and service-worker caching.
- GPS recording uses browser location while the page remains active. iOS may suspend Safari in the background; do not promise background GPS.
- Safari data is stored locally under mission75.logs.v1, mission75.gps.sessions.v1, mission75.settings.v1 and mission75.habits.v1. Export a JSON backup regularly. Clearing Safari website data can erase local records.
- Signing into Supabase does not automatically migrate data that has only ever existed in localStorage; use the app's supported sync/export flow.

HEALTH DATA
- Safari cannot read Apple Health / HealthKit directly.
- Apple Health step totals require the native iPhone companion and explicit user permission.
- The iOS HealthKit implementation is read-only and requests cumulative daily step totals. Background updates are best-effort, not real-time guarantees.
- HealthKit cloud sync depends on the SQL migrations in /supabase/migrations and matching Supabase RLS/RPC permissions. The migrations are not proof that the live Supabase project has been updated.

DEVELOPMENT AND RELEASE
- Web static and mobile-browser checks: node scripts/check-web.mjs and node scripts/browser-smoke.mjs (Playwright required for the browser smoke test).
- GitHub Actions runs the web checks and compiles the iOS app for the iPhone Simulator without signing.
- A successful simulator build does not prove HealthKit works on a physical iPhone.
- Before release, test GPS start/pause/resume/finish, saved-session persistence, account sync, HealthKit permissions, time-zone boundaries, offline recovery and data ownership on real devices.
- Never commit service-role keys, user data exports, passwords or signing secrets.
- Preserve the existing localStorage keys and provide backups before any destructive data migration.

This app provides fitness and habit guidance, not medical diagnosis or treatment.

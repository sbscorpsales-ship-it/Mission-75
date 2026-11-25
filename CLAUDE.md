# GATIVX — Claude Code Project Instructions

## Product and ownership
- Product: GATIVX (Mission-75 / RunJeet are the same product line).
- Product owner approves product direction and final release.
- Preserve the approved Design C dashboard and existing GATIVX visual identity. Do not redesign it.
- The intended delivery spans iOS, Android and the responsive Web Hub, backed by one coherent account/data architecture.
- Treat the repository and its CI evidence as the source of truth. Never claim a feature or test passed without evidence.

## Repository safety
- Current collaboration branch: `fix/gativx-ui-test-guest-reset`.
- Current working PR: #112. Keep it open and unmerged unless the owner explicitly instructs otherwise.
- Do not modify PR #107.
- Never force-push, rewrite shared history, delete branches, rotate secrets, change production data, or merge a PR without explicit owner approval.
- Before editing, inspect the current branch head and working tree. Preserve unrelated changes.
- Make focused, reviewable commits on the collaboration branch. Do not overwrite work that appeared after your inspection.
- Preserve existing accessibility identifiers, including `gativx-start-walk`, `gativx-home-dashboard`, and the Community tab identifier.
- Preserve the Finish & Save reconciliation fix introduced in commit `b2cc78a23d96cc0487b80fe4c07bfc3a7f934140`, unless a demonstrated defect requires a reviewed replacement.

## Roles in the two-agent workflow
- Claude: implementation engineer. Inspect architecture, implement agreed work, add tests, run builds and publish evidence in a pull request.
- ChatGPT: independent auditor / QA reviewer. Review diffs, challenge assumptions, inspect CI logs, reproduce issues where possible, and report release readiness.
- Product owner: approves scope, visual changes, destructive operations, PR merges and release.
- Neither agent may approve its own unverified claims. ChatGPT's review does not replace CI or physical-device verification.

## Handoff protocol
For every substantial task:
1. Create or update a GitHub issue or PR comment with a unique task heading, scope, acceptance criteria and branch.
2. Claude implements only on the agreed branch or a clearly named child branch and opens/updates a PR.
3. Claude posts a handoff comment containing commit SHA, changed files, implementation notes, test commands, exact pass/fail output, CI run URL, screenshots/artifacts, known risks and blockers.
4. ChatGPT reviews the actual diff and CI logs, then posts findings as comments or a separate review. It must not silently edit Claude's changes.
5. Claude addresses review findings and posts a new SHA plus rerun evidence.
6. Product owner decides whether to merge. No automatic merge.

Use labels or explicit headings: `READY_FOR_REVIEW`, `CHANGES_REQUESTED`, `READY_FOR_OWNER`, `BLOCKED`. Never use these labels to imply a test passed.

## Product completeness requirements
Do not stop at the dashboard. Inspect and implement the complete user journey and connected platform:
- Welcome, authentication and onboarding.
- Design C Home dashboard and navigation.
- Activity tracking, GPS, background behavior, pause/resume, Finish & Save, local history and recovery.
- Apple Health integration and reliable export retry.
- Goals, 30/90/180/365-day journeys and GATIVX Guru.
- Missions and milestones.
- Community feed, sharing and privacy controls.
- Profile, settings and notifications.
- Apps section and functional navigation.
- Responsive Web Hub and Android implementation or a clearly documented platform plan if the repository does not yet contain those targets.
- Shared backend contracts, authentication, member ownership, sync, offline queueing, conflict resolution, observability and migrations.

Do not fabricate health/activity metrics or use mock data in production. Clearly distinguish local, synced, unavailable and estimated values. Browser capabilities must not be represented as native background sensor capabilities.

## Engineering and release quality
- Inspect all relevant existing source before changing architecture.
- Prefer small, testable modules and reuse working project conventions.
- Add regression tests for every defect fixed.
- Run the full relevant test suite and build, not only a narrowed test target.
- Never hide failures with `continue-on-error`, skip tests to get green CI, or relabel cancelled tests as passed.
- Report separately: source review, unit tests, simulator/emulator tests, signed build, and physical-device tests.
- For iOS, disclose Xcode/signing/Apple Developer requirements. For Android, disclose signing/Play Console requirements. For web, verify the deployed URL and production backend.
- Never expose secrets in code, logs, PR comments or artifacts. Do not commit credentials or tokens.
- Do not claim deployment when only a local build or unsigned artifact exists.

## Required handoff report
1. Commit SHA and PR URL.
2. Screens/features implemented and still missing.
3. Files changed and architecture/data-flow notes.
4. Tests run with exact outcomes; include cancelled/skipped separately.
5. CI workflow run URL and artifacts.
6. Screenshots of all main screens.
7. Known risks and external dependencies.
8. Exact device installation/testing steps.
9. Honest verdict: not ready / ready for device testing / ready for beta / released.

## Current known gaps to verify, not assume unchanged
Previous review found Community and Notifications as placeholders, Apps absent from the five-tab navigation, Missions limited to a basic consistency mission, and no physical iPhone verification. Reinspect the current branch before acting; these may have changed.

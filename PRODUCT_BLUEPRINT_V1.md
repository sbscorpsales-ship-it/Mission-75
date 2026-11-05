# MISSION — Product Requirements & Commercial Blueprint V1.0

**Owner:** Param IT Solutions, Belgaum, India  
**Product promise:** Your Goal. Your Guide. Your Achievement.  
**Status:** Product vision and proposed requirements; not a statement that features are implemented.

## 1. Product vision

MISSION is a cross-platform fitness, wellness, habit-building and personal goal-achievement platform. It combines dependable activity tracking with personalised missions, practical guidance, progress insights, learning rewards and community motivation.

The product must be simple for beginners, useful to serious fitness users, accessible, privacy-conscious and reliable. Never claim medical diagnosis, treatment or replacement of a healthcare professional.

## 2. Product principles

- Easy installation from Google Play and Apple App Store; no customer-facing ZIP, GitHub or manual setup.
- First-time user should be able to register, create a mission and understand the dashboard in approximately five minutes.
- Clear language, accessible controls, readable text and guided onboarding.
- No critical known defects at release; test on supported devices and network conditions.
- Secure cloud sync, backup, account recovery, data export and account deletion.
- Ask permissions contextually and only when needed.
- Protect user health and location data; do not sell it or use it for advertising.
- Build in phases, with architecture ready for planned future modules.
- Product claims must match features that are actually implemented and tested.

## 3. Core product modules

### A. Account, onboarding and access
- Invitation/referral-code registration during controlled launch.
- Email verification and mobile OTP verification.
- Secure authentication, recovery and session management.
- Mission setup: personal goal, target, timeline, preferences and units.
- Consent, privacy controls, data export and account deletion.
- Optional future public waitlist/access route.

### B. Mission dashboard and goal engine
- Personal mission name/number (for example, Mission 75).
- Goal progress, milestones, daily actions and streaks.
- Weight/waist or other user-selected goal measures.
- Daily and weekly reviews, reminders and progress history.
- Flexible missions beyond weight goals.

### C. Activity tracking
- Walking, running and cycling.
- GPS route recording, start/pause/resume/finish.
- Moving time, elapsed time, distance, pace, average/max speed and splits.
- Route history, elevation gain/loss and activity summaries.
- Robust foreground and background recording where platform policies and permissions allow.
- Recovery from interruptions, low battery, app closure and poor connectivity.
- Clear accuracy limitations and GPS quality indicators.

### D. MISSION MOTION 3D
- Animated 3D replay/flyover of the user's recorded route.
- Terrain view and elevation profile.
- Speed/pace colour overlays and route playback.
- Elevation gain/loss and segment-level analysis.
- Exportable, branded activity video for sharing.
- Build after reliable GPS capture and route data are proven.
- Use properly licensed map/terrain data and manage API costs.

### E. Wellness and habits
- Food diary and nutrition estimates, including protein and calories.
- Water tracking and optional reminders.
- Sleep logging and habit tracking.
- Body measurements and progress charts.
- General wellness education only; no diagnosis or treatment.

### F. Strength and movement
- Home, bodyweight and gym workout libraries.
- Beginner-friendly instructions and progressions.
- Exercise history and personal consistency tracking.
- Accessibility and safety guidance.

### G. Mission Coach
- Personalised daily action plan based on user-entered goals and preferences.
- Check-ins, weekly reviews and practical habit suggestions.
- Motivational insights and next-step recommendations.
- Transparent estimates; no medical advice.

### H. Community
- Friends, groups, challenges, achievements and leaderboards.
- Optional activity sharing and privacy controls.
- User blocking/reporting and moderation tools before broad community launch.

### I. Discovery & Learning Rewards
- Product introduction and feature tutorial videos.
- Feature-based knowledge checks and retries with explanations.
- Verified completion, not merely opening or clicking a video.
- Discovery journey, learning badges and controlled Pro-day rewards.
- Do not condition rewards on public reviews, endorsements or artificial public video views.

### J. Referral Engine and Ambassador programme
- Unique referral code and invitation link per eligible member.
- Attribution locked to the new user's registration.
- Eligibility: member must have at least one successfully paid subscription (monthly or annual) before participating.
- Eligible referred person must be genuinely new and complete app registration, email verification and mobile OTP verification.
- One successful eligible verified registration earns the referrer one unrestricted MISSION Pro day; no purchase by the referred person is required for this registration reward.
- One new verified person can reward only one referrer.
- Exclude self-referrals, duplicates, fabricated identities and abuse.
- Referral ledger: pending, verified, rejected and rewarded.
- Rewards are non-cash, non-transferable and not redeemable for money.
- Milestone bonuses are lifetime cumulative and awarded once when each threshold is reached:
  - 50 verified referrals: 30 bonus Pro days.
  - 100 verified referrals: 90 bonus Pro days.
  - 200 verified referrals: 180 bonus Pro days.
  - 500 verified referrals: 365 bonus Pro days.
  - 1,000 verified referrals: 395 bonus Pro days.
- These milestone bonuses are additional to one Pro day per eligible verified referral.
- Final programme terms, reward caps, inactivity rules, reversals and tax treatment must be reviewed before launch.

### K. Subscription and trial model (proposed)
- Monthly MISSION Pro: ₹49 for 30 days.
- Annual MISSION Pro: ₹365 for 365 days plus 30 additional days (395 days total).
- Invitation-based new-user experience may include a 24-hour unrestricted Pro trial; final eligibility and interaction with subscriptions must be defined.
- No surprise auto-renewal; disclose billing, renewal, cancellation, refund and trial terms clearly.
- App-store and payment-provider fees, applicable taxes and consumer rules must be modelled.
- Referral eligibility requires at least one successful paid subscription. Confirm whether eligibility remains only while paid status is active; preserve already-earned reward balances under published rules.
- Do not advertise rewards or subscription entitlements until implemented and tested.

## 4. Admin and operations
- Secure admin dashboard with role-based access.
- User/account support and moderation tools.
- Subscription, payment and refund reconciliation.
- Referral fraud review and reward ledger.
- Feature engagement and onboarding analytics with privacy safeguards.
- Infrastructure cost alerts, logs, backups and incident monitoring.
- Customer support and published service/contact information.

## 5. Technical direction (to validate with a technical spike)
- Cross-platform mobile: Flutter.
- Backend: evaluate Firebase and Supabase against authentication, relational data, security rules, storage, notifications, costs and operational complexity before committing.
- GPS: native iOS Core Location and Android location/foreground-service capabilities through maintained Flutter plugins or native modules.
- Health integrations: Apple HealthKit and Android Health Connect, with granular consent.
- Maps: compare licensed providers and OpenStreetMap-compatible services; verify terms, attribution, tile/API limits and production suitability.
- 3D: select a provider only after route/GPS prototype and cost tests.
- Notifications: platform push services with user controls.
- Payments: choose compliant payment rails and store billing according to digital-goods rules and distribution channel.
- Keep production secrets server-side. Use private source repositories, protected branches, code review and automated builds.
- Own domain, cloud, app-store, signing and developer accounts under Param IT Solutions.

## 6. Phased delivery

### Phase 0 — Product and architecture
- Confirm product scope, data model, privacy map, screen flows and acceptance criteria.
- Create private production repository and development/staging/production environments.
- Build a clickable design prototype and technical proof-of-concept.
- Validate backend, GPS and app-store constraints before major spend.

### Phase 1 — Reliable MVP
- Registration, verification, secure cloud profiles.
- Mission setup and dashboard.
- Daily logs for activity, nutrition, water, sleep and habits.
- Basic foreground GPS activity recording and history.
- Backup/export, account deletion, accessibility and error handling.
- Admin basics and automated tests.

### Phase 2 — Activity quality
- Background GPS where permitted, route reliability and interruption recovery.
- Pace/speed, splits, elevation profile and historical comparisons.
- Device testing, battery and data-usage optimisation.
- HealthKit and Health Connect integrations.

### Phase 3 — Differentiators
- MISSION MOTION 3D and video export.
- Mission Coach, strength library and advanced insights.
- Discovery learning journey and rewards.

### Phase 4 — Commercial growth
- Subscriptions, referral engine, milestone rewards and anti-fraud.
- Community features, moderation and ambassador programme.
- Analytics, customer support and launch campaigns.

### Phase 5 — Public launch and scale
- Closed beta, staged rollout, crash/error monitoring and load/security testing.
- Store listing, privacy disclosures, support and review preparation.
- Scale infrastructure only against measured usage and retention.

## 7. Quality and release gates
- No unresolved critical or high-severity security issues.
- No known critical crash or data-loss defects.
- Test installation, upgrades, account recovery, sync, offline behaviour and data export.
- Test GPS on a representative device matrix, including screen lock, interruptions, poor signal and low battery.
- Test subscription purchase, cancellation, refunds and entitlement restoration.
- Test referral attribution, duplicate prevention, reward calculations and reversals.
- Accessibility, localisation and clear permission explanations.
- Privacy policy, terms, consent records and account deletion verified.
- Beta feedback reviewed and release candidate signed off.

## 8. Commercial and financial controls
- Start with a capped pilot and measured user cohort.
- Track cost per active user, cost per paying subscriber, retention, conversion, refunds and referral fraud.
- Monitor cloud, maps, OTP, storage, video processing and support costs.
- Model reward liabilities before enabling unlimited referral accumulation.
- Do not promise fixed operating costs or profit until actual usage is measured.
- Separate one-time development, annual maintenance, marketing, payment fees, taxes and staff costs.

## 9. Decisions still requiring confirmation
- Final product name/trademark clearance and brand identity.
- Android-first versus simultaneous iOS/Android launch.
- Final backend and maps/3D provider after technical evaluation.
- Trial rules and whether referral privileges require an active paid plan continuously.
- Reward caps, expiry/inactivity policy and referral milestone legal/tax review.
- Supported languages and initial device matrix.
- Final pricing after testing willingness to pay and unit economics.

**Document status:** Master product blueprint V1.0. This is a planning specification, not evidence that the listed features are already implemented.


## 10. Company brand signature standard — all products

Param IT Solutions is the consistent developer/publisher brand across every product it develops, owns, distributes or markets. This is a company-wide identity rule, not a GATIVX-only treatment.

- Use one approved company signature/wordmark consistently: **PARAM IT SOLUTIONS · BELGAUM, INDIA**.
- Keep the signature visually secondary to each product's own brand: small, restrained, legible and never competing with the product name or primary user task.
- Include the signature in appropriate product touchpoints: splash/about screen, settings or information area, website/product footer, help/support and product documentation. Include developer/publisher attribution in app-store listings and legal/privacy materials where appropriate.
- Use the approved logo artwork, clear space, minimum legible size, colour variants and contrast rules. Do not redraw, stretch, recolour arbitrarily or create a different company mark for each product.
- Product-specific branding remains primary; the Param IT Solutions signature is the consistent maker's mark across the portfolio.
- Maintain a shared brand asset pack and a short brand-use guide for every new product and marketing release.
- Use **™** only as an unregistered trademark claim where appropriate; use **®** only after the relevant mark is officially registered in the applicable jurisdiction. A logo/signature alone does not establish registration or prevent copying.
- Keep the attribution factual: do not claim ownership, development, certification or registration that has not been established.

**Standard signature text:** “Developed by Param IT Solutions · Belgaum, India”. Use a shorter “Param IT Solutions” maker's mark where space is limited.

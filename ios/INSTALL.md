# GATIVX iPhone app — build and install

The Safari dashboard cannot access iPhone motion sensors directly. Use this native iPhone app for direct Core Motion step counting.

## Build on a Mac

1. Install Xcode 16 or later and XcodeGen.
2. Clone this repository and open Terminal in the repository folder.
3. Run:
   `brew install xcodegen`
   `cd ios && xcodegen generate`
   `open GATIVX.xcodeproj`
4. In Xcode, select the GATIVX target → Signing & Capabilities. Select your Apple Developer team and enable the HealthKit capability. Keep the HealthKit entitlements.
5. Connect your iPhone, select it as the run destination, then Build and Run.
6. In GATIVX, today's primary step total and live activity-session steps are read directly from the iPhone's Core Motion pedometer. Apple Health is optional; it does not overwrite the primary Core Motion daily total. Sign in using the same GATIVX cloud account used on the web dashboard.

## What to expect

- The native app reads Apple Health's aggregated daily step totals and syncs them to the signed-in Supabase account.
- It refreshes when opened and registers best-effort hourly HealthKit background delivery. iOS controls when background updates are delivered; this is not guaranteed real-time syncing.
- Live activity-session steps use the iPhone motion sensor. This is separate from the Apple Health daily total.
- The GitHub Actions iOS build produces a **simulator-only** app artifact for compile verification. It cannot be installed on a physical iPhone. A device build must be signed with the owner's Apple Developer team.

## First-device verification

After installation, approve Motion & Fitness access if iOS prompts. Walk with the phone in your pocket, reopen GATIVX, and confirm today's total increases. Start and finish a short activity session and verify it remains saved after force-closing/reopening. Sign in and confirm cloud sync, then reload the Safari dashboard. Physical iPhone testing is required; simulator builds cannot verify sensor behavior.

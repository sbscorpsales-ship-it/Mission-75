# GATIVX iPhone app — build and install

The Safari dashboard cannot read Apple Health. Use this native iPhone app for HealthKit access.

## Build on a Mac

1. Install Xcode 16 or later and XcodeGen.
2. Clone this repository and open Terminal in the repository folder.
3. Run:
   `brew install xcodegen`
   `cd ios && xcodegen generate`
   `open GATIVX.xcodeproj`
4. In Xcode, select the GATIVX target → Signing & Capabilities. Select your Apple Developer team and enable the HealthKit capability. Keep the HealthKit entitlements.
5. Connect your iPhone, select it as the run destination, then Build and Run.
6. In GATIVX, tap **Connect Apple Health**, approve read access to Steps in the Health app prompt, then sign in using the same GATIVX cloud account used on the web dashboard.

## What to expect

- The native app reads Apple Health's aggregated daily step totals and syncs them to the signed-in Supabase account.
- It refreshes when opened and registers best-effort hourly HealthKit background delivery. iOS controls when background updates are delivered; this is not guaranteed real-time syncing.
- Live activity-session steps use the iPhone motion sensor. This is separate from the Apple Health daily total.
- The GitHub Actions iOS build produces a **simulator-only** app artifact for compile verification. It cannot be installed on a physical iPhone. A device build must be signed with the owner's Apple Developer team.

## First-device verification

After installation and permission approval, check that today's step total appears in the native app. Sign in and confirm its cloud status reports successful step sync. Then reload the Safari dashboard and check the Steps tile. A missing value should remain blank rather than being reported as zero.

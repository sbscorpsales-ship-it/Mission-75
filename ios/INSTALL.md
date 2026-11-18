# GATIVX iPhone app — build and install

The Safari dashboard cannot read Apple Health. Use this native iPhone app for HealthKit access when the installed build has a valid Apple-signed HealthKit entitlement.

## GitHub Actions build

The **GATIVX iOS CI** workflow now produces two separate outputs:

- **Simulator app:** for automated compile and simulator testing only. It cannot be installed on a physical iPhone.
- **iPhone Release IPA:** a Release-configuration, device-targeted IPA packaged with code signing disabled. It is an unsigned build artifact, not an installable app until it is signed with a valid Apple provisioning profile.

Open the successful workflow run in GitHub → Artifacts → download **GATIVX-iPhone-unsigned-IPA**. The downloaded artifact is a ZIP containing `GATIVX-unsigned.ipa`. Do not use the Simulator artifact for an iPhone.

The workflow runs on Xcode 26.3, generates the Xcode project with XcodeGen, runs the GATIVX unit tests, validates HealthKit and background-location configuration, builds the Simulator target, then builds the iPhone target in Release configuration.

## Install from Windows

For a personal development test install, use the Windows procedure in [ZERO-COST-IPHONE-INSTALL.md](ZERO-COST-IPHONE-INSTALL.md). It uses Sideloadly and an Apple ID controlled by the device owner.

Important:
- Never share an Apple ID password or verification code.
- Free personal-team provisioning is temporary and normally requires periodic re-signing.
- A free Apple ID may not be permitted to provision the HealthKit and HealthKit Background Delivery entitlements. Confirm the actual signing result; an unsigned source entitlement is not proof that Apple has granted it.
- If signing rejects HealthKit, do not describe HealthKit as working in that install. Use an Apple Developer team and provisioning profile that explicitly supports the required capability, or use the documented Shortcut import fallback.

## Build locally on a Mac

1. Install Xcode 16 or later and XcodeGen.
2. Clone this repository and run:
   `brew install xcodegen`
   `cd ios && xcodegen generate`
   `open GATIVX.xcodeproj`
3. In Xcode, select the GATIVX target → Signing & Capabilities. Select your Apple Developer team and verify that HealthKit is available for the App ID and provisioning profile.
4. Connect your iPhone, select it as the run destination, then Build and Run.
5. In GATIVX, tap **Connect Apple Health**, approve the requested access in the Health app prompt, then sign in using the same GATIVX cloud account used on the web dashboard.

## What to expect

- The native app reads Apple Health's aggregated daily step totals and syncs them to the signed-in Supabase account.
- It refreshes when opened and requests best-effort HealthKit background delivery. iOS controls when background updates are delivered; step updates may be batched and are not guaranteed to be real-time.
- Live activity-session steps use the iPhone motion sensor. This is separate from the Apple Health daily total.
- A started GPS activity can continue in supported background conditions with the required Always location permission and signed background-location configuration.
- Missing readings remain unavailable; the app must not invent zero values.

## First-device verification

After signed installation and permission approval:

1. Confirm the app launches and survives force-close/relaunch.
2. Compare today's displayed steps with Apple Health.
3. Start a short walk, lock the screen, then finish and save.
4. Confirm the activity and route are present in local history after relaunch.
5. Confirm the workout appears in Apple Health without duplicates after retry.
6. Confirm cloud sync reports success, then reload the Safari dashboard and check the Steps tile.

A successful simulator build or unsigned IPA package does not prove these physical-device behaviours. Record each device acceptance result in [GATIVX_IOS_FIRST_ACCEPTANCE.md](../docs/GATIVX_IOS_FIRST_ACCEPTANCE.md).

# GATIVX — zero-cost iPhone installation (Windows)

This is a development/test installation route, not App Store distribution.

## What the build provides

The GitHub Actions workflow builds:
- a Simulator app for automated compilation checks
- a separate unsigned, device-targeted IPA named `GATIVX-unsigned.ipa`

Download the **GATIVX-iPhone-unsigned-IPA** artifact from the successful **GATIVX iOS CI** run. Do not download the Simulator artifact for an iPhone.

## Install on Windows

1. Install Sideloadly only from its official website: https://sideloadly.io/
2. Install the Apple device support software requested by Sideloadly. Its Windows requirements can change; follow the current official instructions.
3. Connect the iPhone to the Windows PC with USB, unlock it, and tap **Trust This Computer** if prompted.
4. Open Sideloadly, select the connected iPhone, and load `GATIVX-unsigned.ipa`.
5. Sign using an Apple ID that you control. For security, consider a separate Apple ID used only for development testing. Never send the password or verification code to anyone.
6. Complete any iPhone prompts for Developer Mode and developer trust. The exact prompts depend on the iOS version.
7. Open GATIVX and sign in with the same existing GATIVX account to restore cloud-backed records.

## Important free-account limits

- Apple personal-team signing is temporary. Apple's current guidance says personal-team provisioning profiles expire after 7 days; the app must be re-signed/reinstalled periodically.
- Apple limits a free personal team to 3 active sideloaded apps on a device.
- Sideloadly documents the same 7-day free-account limit. Automatic refresh depends on the PC and device being available over USB or configured Wi-Fi.
- This is not a permanent installation and is not suitable for public distribution.

## HealthKit entitlement is a separate gate

A successful unsigned IPA build does **not** prove that a free Apple ID can provision the HealthKit and HealthKit Background Delivery entitlements. Apple lists supported capabilities by developer-program membership. This must be verified during signing and on the physical iPhone.

If Apple's provisioning service rejects HealthKit for a free personal team, the native HealthKit connection cannot be represented as working on that free install. The web dashboard's Apple Shortcut import remains the no-cost fallback for steps and active energy; it is scheduled/user-triggered, not a continuous HealthKit stream.

## Background behavior

- Background GPS is intended only during an explicitly started activity and requires the appropriate iOS location permission, including **Always** for background route updates.
- iOS controls background execution. A simulator build cannot prove GPS or HealthKit background behavior.
- HealthKit step background delivery is limited by iOS to at most hourly. Opening GATIVX refreshes current totals.

## Protect existing data

Use the same bundle identifier and the same Apple ID when refreshing the sideloaded app. Sign in to the existing GATIVX account before relying on cloud backup. Do not delete the existing web app or clear browser storage as part of native installation.

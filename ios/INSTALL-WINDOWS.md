# GATIVX iPhone build and installation

## Current build artifact

The GitHub Actions workflow produces:

- `GATIVX-iPhone-unsigned-IPA` — device-targeted, arm64 iPhone app package
- `GATIVX-iOS-Simulator` — simulator build for automated validation

The current device artifact uses bundle ID `com.paramitsolutions.gativx` and minimum iOS 17.0. It is **unsigned** and is not directly installable until it is signed with a valid Apple development certificate and provisioning profile.

## Signing requirements

GATIVX requests the HealthKit capability and HealthKit background-delivery entitlement. The App ID and provisioning profile used to sign the app must permit those capabilities. Apple controls which capabilities are available to each developer membership; a free Personal Team may not be able to provision all capabilities required by GATIVX.

For a physical iPhone test with HealthKit enabled:

1. Use an Apple Developer Program team that has HealthKit enabled for the App ID.
2. Register the test iPhone with that team.
3. Create/download an Apple Development certificate and a development provisioning profile for `com.paramitsolutions.gativx`.
4. Sign the unsigned IPA with those credentials using a trusted local signing tool on macOS or Windows.
5. Install the signed app and grant Health and Location permissions on the iPhone.

Do not send Apple ID passwords, private signing keys, certificate passwords or provisioning-profile secrets to ChatGPT. Enter them only in the trusted signing tool or store them in the appropriate protected developer secrets.

## Windows and iPhone

A Mac is not required for the final signing step if a Windows-compatible signing tool is used and you already have the correct Apple development certificate and provisioning profile. The IPA produced by CI is the unsigned input package.

A free Personal Team can install limited development builds, but Apple states that personal-team app IDs, registered devices and provisioning profiles expire after seven days. HealthKit capability availability may also be restricted. For dependable HealthKit testing and eventual TestFlight/App Store distribution, use an Apple Developer Program team.

## Zero-cost fallback

Until the native app is signed with the required HealthKit capability, the deployed GATIVX web app can continue using the documented Apple Health Shortcuts import path. That keeps measured steps and active energy available without pretending that the unsigned native IPA is installed or that background GPS has been physically verified.

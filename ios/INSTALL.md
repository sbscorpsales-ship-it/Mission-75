# WALKON iPhone build and first-device verification

WALKON is a native iOS app. Its simulator build is for compile and automated-test validation only; it cannot be installed on a physical iPhone.

## Build locally on a Mac

1. Install Xcode 16 or later and XcodeGen.
2. From the repository root, run:
   `brew install xcodegen`
   `xcodegen generate --spec ios/project.yml --project ios`
3. Open `ios/WALKON.xcodeproj` in Xcode.
4. Select the WALKON target and set your Apple Developer team under **Signing & Capabilities**. Enable **HealthKit** and its **Background Delivery** option. The project includes both required HealthKit entitlements; retain them when configuring signing. Keep the location and motion usage descriptions.
5. Connect the iPhone, select it as the run destination, then build and run.
6. Approve Health access for Steps and allow the location permissions requested while starting a walk. For locked-screen route recording, iOS must grant **Always** location access.

## Build through GitHub Actions

The WALKON iOS workflow generates the Xcode project, runs unit tests on an iPhone Simulator, compiles the simulator app, and uploads the simulator artifact.

A simulator artifact is not a device-installable app. A physical-device build must be signed with the owner's Apple Developer team and a matching provisioning profile. Signing credentials must be configured securely in the repository's GitHub Actions secrets; never paste certificates, passwords, private keys, or API keys into chat or source files.

For TestFlight distribution, configure an Apple Distribution certificate, an App Store provisioning profile, and an App Store Connect API key for the same team. The bundle identifier is `com.paramitsolutions.walkon`.

## First-device verification checklist

1. Confirm today's Apple Health step total appears and matches the Health app's daily total.
2. Start a walk and compare live session steps with the iPhone's motion-based step count.
3. Walk outdoors with location enabled; verify route points and distance are recorded.
4. Lock the screen for a short section and verify location updates continue with Always permission.
5. Finish the walk; confirm the activity appears in History.
6. Force-close and reopen the app during a test walk; verify the saved checkpoint is restored. iOS cannot supply tracking samples for time when the app process was terminated.
7. Repeat with low-power mode and after a normal device restart to observe battery and recovery behavior.

## Current implementation boundaries

- Apple Health daily steps and live walk-session steps are separate readings. Do not add them together; they can represent overlapping activity.
- HealthKit background delivery is best-effort and controlled by iOS, not guaranteed to refresh in real time.
- Completed walks and active-walk recovery checkpoints are stored locally on the iPhone. Cloud account sync is not currently implemented in this native target.
- A simulator build cannot validate real HealthKit permissions, actual step counts, GPS accuracy, locked-screen behavior, or battery use. Those require a signed build on a physical iPhone.

# WALKON

A fresh native SwiftUI iPhone fitness app.

- Six-letter name; Chaldean numerology: W(6)+A(1)+L(3)+K(2)+O(7)+N(5) = 24 → 6.
- Reads the daily step total from Apple Health.
- Records new walks with Core Motion and GPS.
- Saves only activities started in WALKON on this device.
- No cloud account, cloud sync, old activity import, or legacy data migration in this first build.

## Build

```sh
brew install xcodegen
xcodegen generate --spec ios/project.yml
xcodebuild -project ios/WALKON.xcodeproj -scheme WALKON -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Real-device validation is required for HealthKit permissions, background location, and sensor accuracy before release.

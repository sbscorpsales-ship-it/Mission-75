# WALKON

A fresh native SwiftUI iPhone fitness app. This target is intentionally separate from the legacy GATIVX implementation in this repository.

## First-release engineering contract

- Native iPhone app, iOS 26.0+.
- Daily step total is read from Apple Health.
- New workouts are owned by WALKON and recorded only after the user starts a walk.
- Local persistence is the source of truth; network access is not required to record or save a walk.
- HealthKit workout and route export is separate from the durable local save.
- No old GATIVX/Mission-75 activity, user, credential or schema import.
- No cloud account or cloud sync in the initial local-core milestone.

## Generate and build

Run from the repository root on a Mac with Xcode 26 and XcodeGen:

```sh
brew install xcodegen
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -list -project ios/WALKON.xcodeproj
xcodebuild -project ios/WALKON.xcodeproj -scheme WALKON -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/WALKON.xcodeproj -scheme WALKON -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions runs the simulator build and unit-test target on a macOS runner. Real-device validation remains mandatory for HealthKit, Core Motion, background location, battery behaviour and sensor accuracy before release.

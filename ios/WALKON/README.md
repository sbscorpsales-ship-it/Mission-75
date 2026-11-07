# WALKON

A native SwiftUI iPhone fitness app.

- Reads the daily step total from Apple Health.
- Records walks with Core Motion and GPS.
- Saves activity history and active-walk recovery checkpoints locally first.
- Signs in to the existing cloud account with a six-digit email OTP; new account creation is disabled in the app.
- Backs up daily Apple Health totals through the authenticated `sync_healthkit_daily_steps` RPC.
- Backs up completed walk-session steps, duration, distance and GPS route points through the authenticated `sync_walk_session_route` RPC.
- Keeps walks on the iPhone when offline and retries pending uploads after the account is connected and the app returns online.
- Uses the Supabase publishable key only. No service-role or secret key is embedded in the app.
- Cloud session tokens use the SDK's iOS Keychain storage.

## Build

```sh
brew install xcodegen
xcodegen generate --spec ios/project.yml --project ios
xcodebuild -project ios/WALKON.xcodeproj -scheme WALKON -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Real-device validation is required for Apple Health authorization, background delivery, motion accuracy, background GPS, Keychain persistence, and cloud account sign-in.

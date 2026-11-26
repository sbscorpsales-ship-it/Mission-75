import SwiftUI

// Keep the app's iOS 17 entry path while opting the iOS 18+ primary scene
// into the system's principal full-screen window role.
@main
struct GATIVXAppLauncher {
    @MainActor
    static func main() {
        if #available(iOS 18.0, *) {
            GATIVXModernApp.main()
        } else {
            GATIVXLegacyApp.main()
        }
    }
}

private enum GATIVXAppBootstrap {
    static func configure() {
        #if DEBUG
        // UI tests need a deterministic first-run state. Do not use a
        // -key value UserDefaults launch argument here: NSArgumentDomain
        // overrides writes made by @AppStorage for the lifetime of the process.
        if ProcessInfo.processInfo.arguments.contains("-gativx-ui-test-reset-local-mode") {
            UserDefaults.standard.removeObject(forKey: "gativx.localModeEntered")
        }
        #endif
    }
}

struct GATIVXLegacyApp: App {
    init() {
        GATIVXAppBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

@available(iOS 18.0, *)
struct GATIVXModernApp: App {
    init() {
        GATIVXAppBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowManagerRole(.principal)
    }
}

import SwiftUI

@main
struct GATIVXApp: App {
    init() {
        #if DEBUG
        // UI tests need a deterministic first-run state. Do not use a
        // -key value UserDefaults launch argument here: NSArgumentDomain
        // overrides writes made by @AppStorage for the lifetime of the process.
        if ProcessInfo.processInfo.arguments.contains("-gativx-ui-test-reset-local-mode") {
            UserDefaults.standard.removeObject(forKey: "gativx.localModeEntered")
        }
        #endif
    }

    @SceneBuilder
    var body: some Scene {
        if #available(iOS 18.0, *) {
            WindowGroup {
                ContentView()
            }
            .windowManagerRole(.principal)
        } else {
            WindowGroup {
                ContentView()
            }
        }
    }
}

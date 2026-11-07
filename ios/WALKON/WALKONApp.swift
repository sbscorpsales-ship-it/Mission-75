import SwiftUI

@main
struct WALKONApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
                .preferredColorScheme(.dark)
        }
    }
}

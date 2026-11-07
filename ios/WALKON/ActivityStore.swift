import Foundation
import Combine
import CoreLocation

struct WalkSession: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var steps: Int
    var distanceMeters: Double
    var route: [Coordinate]

    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
    }
}

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []
    private let key = "walkon.sessions.v1"

    init() { load() }

    func save(_ session: WalkSession) {
        sessions.insert(session, at: 0)
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WalkSession].self, from: data) else { return }
        sessions = decoded
    }
}

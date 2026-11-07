import Foundation
import Combine

struct WalkSession: Identifiable, Codable {
    struct RoutePoint: Codable {
        let latitude: Double
        let longitude: Double
        let timestamp: Date
        let horizontalAccuracy: Double
    }

    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let steps: Int
    let distanceMeters: Double
    let route: [RoutePoint]

    var duration: TimeInterval { max(endedAt.timeIntervalSince(startedAt), 0) }
}

@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []
    @Published private(set) var storageStatus = "Preparing local activity storage"

    private let fileName = "walkon-activities-v1.json"
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys]
        return value
    }()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    init() { load() }

    @discardableResult
    func save(_ session: WalkSession) -> Bool {
        guard !sessions.contains(where: { $0.id == session.id }) else { return true }
        let previous = sessions
        sessions.insert(session, at: 0)
        do {
            try persist()
            storageStatus = "Saved securely on this iPhone"
            return true
        } catch {
            sessions = previous
            storageStatus = "Could not save walk: \(error.localizedDescription)"
            return false
        }
    }

    private var storageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("WALKON", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func load() {
        guard let url = storageURL else {
            storageStatus = "Local storage is unavailable"
            return
        }
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                storageStatus = "Ready — walks are saved on this iPhone"
                return
            }
            let data = try Data(contentsOf: url)
            sessions = try decoder.decode([WalkSession].self, from: data)
            storageStatus = "Loaded \(sessions.count) saved walks"
        } catch {
            storageStatus = "Activity history needs recovery: \(error.localizedDescription)"
        }
    }

    private func persist() throws {
        guard let url = storageURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(sessions)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

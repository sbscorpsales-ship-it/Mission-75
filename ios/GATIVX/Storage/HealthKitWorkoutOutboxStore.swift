import Foundation

struct PendingHealthWorkout: Codable, Identifiable {
    let id: UUID
    let activity: String
    let startedAt: Date
    let finishedAt: Date
    let steps: Int?
    let distanceMeters: Double?
}

protocol HealthKitWorkoutOutboxPersistence {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data, forKey key: String)
}

private struct UserDefaultsHealthKitWorkoutOutboxPersistence: HealthKitWorkoutOutboxPersistence {
    let defaults: UserDefaults

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func setData(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

/// Durable, idempotent local queue for workouts awaiting Apple Health export.
struct HealthKitWorkoutOutboxStore {
    private let persistence: HealthKitWorkoutOutboxPersistence
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "gativx.healthkit.workout-export-outbox.v1"
    ) {
        self.persistence = UserDefaultsHealthKitWorkoutOutboxPersistence(defaults: userDefaults)
        self.key = key
    }

    init(persistence: HealthKitWorkoutOutboxPersistence, key: String = "gativx.healthkit.workout-export-outbox.v1") {
        self.persistence = persistence
        self.key = key
    }

    func load() throws -> [PendingHealthWorkout] {
        guard let data = persistence.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([PendingHealthWorkout].self, from: data)
        } catch {
            throw NSError(
                domain: "GATIVXHealthKitOutbox",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Apple Health export queue could not be decoded. Original data was preserved."]
            )
        }
    }

    private func save(_ items: [PendingHealthWorkout]) throws {
        let data = try JSONEncoder().encode(items)
        persistence.setData(data, forKey: key)
        guard let saved = persistence.data(forKey: key),
              saved == data,
              let verified = try? JSONDecoder().decode([PendingHealthWorkout].self, from: saved),
              verified.map(\.id) == items.map(\.id) else {
            throw NSError(
                domain: "GATIVXHealthKitOutbox",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Apple Health export queue could not be read back and verified."]
            )
        }
    }

    @discardableResult
    func enqueue(_ item: PendingHealthWorkout) throws -> [PendingHealthWorkout] {
        var items = try load()
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
        }
        try save(items)
        return items
    }

    @discardableResult
    func acknowledge(_ id: UUID) throws -> [PendingHealthWorkout] {
        let remaining = try load().filter { $0.id != id }
        try save(remaining)
        return remaining
    }
}

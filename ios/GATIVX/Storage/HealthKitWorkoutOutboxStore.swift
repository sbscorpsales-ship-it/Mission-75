import Foundation

struct PendingHealthWorkout: Codable, Identifiable {
    let id: UUID
    let activity: String
    let startedAt: Date
    let finishedAt: Date
    let steps: Int?
    let distanceMeters: Double?
}

/// Durable, idempotent local queue for workouts awaiting Apple Health export.
struct HealthKitWorkoutOutboxStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "gativx.healthkit.workout-export-outbox.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() throws -> [PendingHealthWorkout] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
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

    func save(_ items: [PendingHealthWorkout]) throws {
        let data = try JSONEncoder().encode(items)
        userDefaults.set(data, forKey: key)
        guard let saved = userDefaults.data(forKey: key),
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

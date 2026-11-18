import Foundation

/// Durable, testable outbox for measured daily sensor writes awaiting Supabase acknowledgement.
/// A newer reading replaces only the same member/kind/local-day revision.
struct HealthSyncOutboxStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "com.paramitsolutions.gativx.health-sync-outbox.v1"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() throws -> [PendingHealthSync] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([PendingHealthSync].self, from: data)
        } catch {
            throw NSError(
                domain: "GATIVXHealthSyncOutbox",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The sensor sync queue could not be decoded. Original data was preserved."]
            )
        }
    }

    func save(_ items: [PendingHealthSync]) throws {
        let data = try JSONEncoder().encode(items)
        userDefaults.set(data, forKey: key)
        guard let saved = userDefaults.data(forKey: key),
              saved == data,
              let verified = try? JSONDecoder().decode([PendingHealthSync].self, from: saved),
              verified.count == items.count,
              verified.map(\\.id) == items.map(\\.id),
              verified.map(\\.revisionID) == items.map(\\.revisionID) else {
            throw NSError(
                domain: "GATIVXHealthSyncOutbox",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The sensor sync queue could not be read back and verified."]
            )
        }
    }

    @discardableResult
    func enqueue(_ item: PendingHealthSync) throws -> [PendingHealthSync] {
        var items = try load()
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort { $0.queuedAt < $1.queuedAt }
        try save(items)
        return items
    }

    @discardableResult
    func acknowledge(_ item: PendingHealthSync) throws -> [PendingHealthSync] {
        let items = try load()
        let remaining = items.filter {
            !($0.id == item.id && $0.revisionID == item.revisionID)
        }
        try save(remaining)
        return remaining
    }
}

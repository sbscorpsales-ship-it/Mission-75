import Foundation

/// Durable, testable outbox for measured daily sensor writes awaiting Supabase acknowledgement.
/// A newer reading replaces only the same member/kind/local-day revision.
struct HealthSyncOutboxStore {
    private let userDefaults: UserDefaults
    private let key: String

    /// Strictly parse a local YYYY-MM-DD date. Calendar.date(from:) can
    /// normalize impossible dates (for example February 30), so verify the
    /// resulting components before allowing a queued sensor write to proceed.
    static func dateForLocalDay(_ value: String, timeZone: TimeZone = .current) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year > 0, (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

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
              verified.map(\.id) == items.map(\.id),
              verified.map(\.revisionID) == items.map(\.revisionID) else {
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

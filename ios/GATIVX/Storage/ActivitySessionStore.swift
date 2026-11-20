import Foundation

/// Persists completed activities in Application Support using atomic file replacement.
/// The legacy UserDefaults payload is migrated only after the new file is read back.
struct ActivitySessionStore {
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let directoryOverride: URL?
    private let legacyKey = "gativx.activitySessions.v1"
    private let fileName = "activity-history.json"

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        directoryOverride: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.directoryOverride = directoryOverride
    }

    func load() throws -> [ActivitySessionRecord] {
        let url = try fileURL()

        if fileManager.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ActivitySessionRecord].self, from: data)
        }

        guard let legacyData = userDefaults.data(forKey: legacyKey) else {
            return []
        }

        let records = try JSONDecoder().decode([ActivitySessionRecord].self, from: legacyData)
        try write(records, to: url)
        // Keep the legacy copy until the atomic file write and read-back verification pass.
        userDefaults.removeObject(forKey: legacyKey)
        return records
    }

    func save(_ records: [ActivitySessionRecord]) throws {
        try write(records, to: fileURL())
    }

    /// Idempotently inserts or reconciles a session by its stable UUID.
    /// Existing position and identity are preserved; richer recovered sensor data is merged.
    func upserting(_ record: ActivitySessionRecord, into records: [ActivitySessionRecord]) -> [ActivitySessionRecord] {
        var updated = records
        if let index = updated.firstIndex(where: { $0.id == record.id && $0.ownerID == record.ownerID }) {
            updated[index] = updated[index].mergingRecovery(record)
        } else {
            updated.insert(record, at: 0)
        }
        return updated
    }

    private func fileURL() throws -> URL {
        if let directoryOverride {
            return directoryOverride.appendingPathComponent(fileName, isDirectory: false)
        }

        guard let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "GATIVXActivityStorage",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "The iPhone Application Support directory is unavailable."]
            )
        }

        return supportDirectory
            .appendingPathComponent("GATIVX", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func write(_ records: [ActivitySessionRecord], to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)

        let savedData = try Data(contentsOf: url)
        guard savedData == data else {
            throw NSError(
                domain: "GATIVXActivityStorage",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "The activity history file does not match the data written to disk."]
            )
        }

        let savedRecords = try JSONDecoder().decode([ActivitySessionRecord].self, from: savedData)
        guard savedRecords.count == records.count,
              savedRecords.map(\.id) == records.map(\.id) else {
            throw NSError(
                domain: "GATIVXActivityStorage",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "The activity history file could not be read back and verified."]
            )
        }
    }
}

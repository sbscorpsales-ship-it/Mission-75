import Foundation

/// A separate, local-only archive for daily totals imported from RunJeet.
/// These historical totals are never added to Apple Health's all-source total.
struct RunJeetDailyStepsArchiveStore {
    struct MergeResult: Equatable {
        let addedDays: Int
        let preservedExistingDays: Int
        let totalDays: Int
    }

    private struct Payload: Codable, Equatable {
        let schemaVersion: Int
        let stepsByDay: [String: Int]
    }

    private let fileManager: FileManager
    private let directoryOverride: URL?
    private let fileName = "runjeet-daily-steps-archive.json"

    init(fileManager: FileManager = .default, directoryOverride: URL? = nil) {
        self.fileManager = fileManager
        self.directoryOverride = directoryOverride
    }

    func load() throws -> [String: Int] {
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.schemaVersion == 1,
              payload.stepsByDay.allSatisfy({ Self.isValidDay($0.key) && (0...1_000_000).contains($0.value) }) else {
            throw NSError(
                domain: "GATIVXRunJeetArchive",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The imported daily-step archive is invalid. The original file was preserved."]
            )
        }
        return payload.stepsByDay
    }

    /// Existing dates win on conflict. Re-importing the same backup is idempotent.
    func merge(_ incoming: [String: Int]) throws -> MergeResult {
        guard incoming.allSatisfy({ Self.isValidDay($0.key) && (0...1_000_000).contains($0.value) }) else {
            throw NSError(
                domain: "GATIVXRunJeetArchive",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The RunJeet daily-step archive contains invalid values."]
            )
        }

        var merged = try load()
        let originalCount = merged.count
        for (day, steps) in incoming where merged[day] == nil {
            merged[day] = steps
        }

        try write(merged, to: fileURL())
        let verified = try load()
        guard verified == merged else {
            throw NSError(
                domain: "GATIVXRunJeetArchive",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The imported daily-step archive did not pass read-back verification."]
            )
        }

        let added = merged.count - originalCount
        return MergeResult(
            addedDays: added,
            preservedExistingDays: incoming.count - added,
            totalDays: merged.count
        )
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
                domain: "GATIVXRunJeetArchive",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "The iPhone Application Support directory is unavailable."]
            )
        }
        return supportDirectory
            .appendingPathComponent("GATIVX", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func write(_ stepsByDay: [String: Int], to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = Payload(schemaVersion: 1, stepsByDay: stepsByDay)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
        let saved = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(Payload.self, from: saved)
        guard saved == data, decoded == payload else {
            throw NSError(
                domain: "GATIVXRunJeetArchive",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "The imported daily-step archive could not be verified after saving."]
            )
        }
    }

    private static func isValidDay(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }
}

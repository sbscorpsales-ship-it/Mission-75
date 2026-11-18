import Foundation

/// Imports RunJeet schema-1 JSON backups into GATIVX's canonical activity model.
/// Daily step totals are returned separately: they are not merged into HealthKit totals.
struct RunJeetBackupImport {
    let activities: [ActivitySessionRecord]
    let dailyStepsByDay: [String: Int]
}

enum RunJeetBackupImportError: LocalizedError {
    case invalidBackup
    case unsupportedSchema
    case invalidDailySteps(String)
    case invalidSession(String)

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "This file is not a valid RunJeet backup."
        case .unsupportedSchema:
            return "This RunJeet backup version is not supported."
        case .invalidDailySteps(let day):
            return "The RunJeet backup contains an invalid step total for \(day)."
        case .invalidSession(let id):
            return "The RunJeet backup contains an invalid activity session: \(id)."
        }
    }
}

struct RunJeetBackupImporter {
    func decode(_ data: Data) throws -> RunJeetBackupImport {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["app"] as? String == "RunJeet" else {
            throw RunJeetBackupImportError.invalidBackup
        }
        guard (root["schema"] as? NSNumber)?.intValue == 1,
              let state = root["state"] as? [String: Any],
              let rawDailySteps = state["stepsByDay"] as? [String: Any],
              let rawSessions = state["sessions"] as? [[String: Any]] else {
            throw RunJeetBackupImportError.unsupportedSchema
        }

        var dailySteps: [String: Int] = [:]
        for (day, rawValue) in rawDailySteps {
            guard Self.isValidDay(day),
                  let number = rawValue as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite,
                  number.doubleValue >= 0,
                  number.doubleValue.rounded(.towardZero) == number.doubleValue,
                  number.doubleValue <= Double(Int.max) else {
                throw RunJeetBackupImportError.invalidDailySteps(day)
            }
            dailySteps[day] = number.intValue
        }

        let activities = try rawSessions.map { try decodeSession($0) }
        return RunJeetBackupImport(activities: activities, dailyStepsByDay: dailySteps)
    }

    /// Merge imported sessions without overwriting existing records. Existing IDs win.
    func merging(_ imported: [ActivitySessionRecord], into existing: [ActivitySessionRecord]) -> [ActivitySessionRecord] {
        var merged = existing
        var knownIDs = Set(existing.map(\.id))
        for record in imported where knownIDs.insert(record.id).inserted {
            merged.append(record)
        }
        return merged.sorted { $0.finishedAt > $1.finishedAt }
    }

    private func decodeSession(_ raw: [String: Any]) throws -> ActivitySessionRecord {
        let identifier = raw["id"] as? String ?? "(missing id)"
        guard let id = UUID(uuidString: identifier),
              let startedAt = millisecondsDate(raw["startedAt"]),
              let finishedAt = millisecondsDate(raw["endedAt"]),
              finishedAt >= startedAt,
              let duration = integer(raw["durationSec"]), duration >= 0,
              let rawPoints = raw["points"] as? [[String: Any]],
              let rawDistance = raw["distanceM"] as? NSNumber,
              rawDistance.doubleValue.isFinite, rawDistance.doubleValue >= 0 else {
            throw RunJeetBackupImportError.invalidSession(identifier)
        }

        let points = try rawPoints.map { point -> GATIVXRoutePoint in
            guard let latitude = finiteDouble(point["lat"]),
                  let longitude = finiteDouble(point["lon"]),
                  (-90...90).contains(latitude),
                  (-180...180).contains(longitude),
                  let timestamp = millisecondsDate(point["ts"]),
                  let accuracy = finiteDouble(point["accuracy"]),
                  accuracy >= 0 else {
                throw RunJeetBackupImportError.invalidSession(identifier)
            }
            return GATIVXRoutePoint(
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                horizontalAccuracy: accuracy,
                breakBefore: false
            )
        }

        let rawSteps = integer(raw["sessionSteps"])
        // RunJeet's MVP initializes sessionSteps to zero even when no step source
        // was connected. Preserve only positive readings as measured session steps.
        let measuredSteps = (rawSteps ?? 0) > 0 ? rawSteps : nil
        let measuredDistance = rawDistance.doubleValue > 0 ? rawDistance.doubleValue : nil

        return ActivitySessionRecord(
            id: id,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: measuredSteps,
            routePoints: points.isEmpty ? nil : points,
            motionDistanceMeters: measuredDistance,
            ownerID: nil
        )
    }

    private func millisecondsDate(_ value: Any?) -> Date? {
        guard let milliseconds = finiteDouble(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private func finiteDouble(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue >= Double(Int.min),
              number.doubleValue <= Double(Int.max) else { return nil }
        return number.intValue
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

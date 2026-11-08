import Foundation
import Combine
import SQLite3

struct WalkSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var steps: Int
    var distanceMeters: Double
    var route: [Coordinate]
    /// Separate GPS continuity runs. Nil means a legacy session with no segment metadata.
    var routeSegments: [[Coordinate]]? = nil

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
    }
}

struct WorkoutDraft: Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let lastUpdatedAt: Date
    let steps: Int
    let distanceMeters: Double
    let routePointCount: Int
}

struct JournalRoutePoint: Equatable {
    let sequence: Int
    let segment: Int
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

enum ActivityStoreError: LocalizedError {
    case databaseOpen(String)
    case database(String)
    case encoding

    var errorDescription: String? {
        switch self {
        case .databaseOpen(let message): return "Could not open local walk history: \(message)"
        case .database(let message): return "Local walk history error: \(message)"
        case .encoding: return "Could not encode this walk for local storage."
        }
    }
}

/// Local-first store. Draft and route writes commit before returning; a successful
/// call means SQLite accepted the write under WAL + synchronous FULL durability.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []
    @Published private(set) var recoverableDrafts: [WorkoutDraft] = []
    @Published private(set) var storageStatus = "Local history ready"

    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let configuredDatabaseURL: URL?

    init(databaseURL: URL? = nil) {
        configuredDatabaseURL = databaseURL
        do {
            try openDatabase()
            try load()
            try loadDrafts()
        } catch {
            storageStatus = error.localizedDescription
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    @discardableResult
    func beginDraft(id: UUID = UUID(), startedAt: Date = Date()) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            try execute("BEGIN IMMEDIATE;")
            do {
                var statement: OpaquePointer?
                try prepare("INSERT INTO workout_drafts (id, started_at, updated_at, steps, distance_meters) VALUES (?, ?, ?, 0, 0) ON CONFLICT(id) DO NOTHING;", into: &statement, database: database)
                defer { sqlite3_finalize(statement) }
                bind(id.uuidString, to: 1, in: statement)
                sqlite3_bind_double(statement, 2, startedAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 3, startedAt.timeIntervalSince1970)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw ActivityStoreError.database(lastError(database)) }
                guard sqlite3_changes(database) == 1 else {
                    throw ActivityStoreError.database("A walk with this identifier already exists; no new draft was created.")
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
            try loadDrafts()
            storageStatus = "Walk draft saved on this iPhone"
            return true
        } catch {
            storageStatus = error.localizedDescription
            return false
        }
    }

    /// Appends one accepted GPS observation. Sequence numbers make retries idempotent.
    @discardableResult
    func appendRoutePoint(workoutID: UUID, point: JournalRoutePoint) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            try execute("BEGIN IMMEDIATE;")
            do {
                var statement: OpaquePointer?
                try prepare("""
                    INSERT INTO route_points (workout_id, sequence, segment, timestamp, latitude, longitude, horizontal_accuracy)
                    SELECT ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (
                        SELECT 1 FROM workout_drafts WHERE id = ?
                    ) ON CONFLICT(workout_id, sequence) DO NOTHING;
                    """, into: &statement, database: database)
                defer { sqlite3_finalize(statement) }
                bind(workoutID.uuidString, to: 1, in: statement)
                sqlite3_bind_int64(statement, 2, sqlite3_int64(point.sequence))
                sqlite3_bind_int64(statement, 3, sqlite3_int64(point.segment))
                sqlite3_bind_double(statement, 4, point.timestamp.timeIntervalSince1970)
                sqlite3_bind_double(statement, 5, point.latitude)
                sqlite3_bind_double(statement, 6, point.longitude)
                sqlite3_bind_double(statement, 7, point.horizontalAccuracy)
                bind(workoutID.uuidString, to: 8, in: statement)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw ActivityStoreError.database(lastError(database)) }
                let inserted = sqlite3_changes(database) == 1
                if !inserted {
                    // A retry is successful only when this exact workout still exists
                    // and its sequence was already journaled. A missing draft must fail.
                    var check: OpaquePointer?
                    try prepare("""
                        SELECT EXISTS(SELECT 1 FROM workout_drafts WHERE id = ?)
                           AND EXISTS(
                               SELECT 1 FROM route_points
                               WHERE workout_id = ? AND sequence = ? AND segment = ?
                                 AND timestamp = ? AND latitude = ? AND longitude = ?
                                 AND horizontal_accuracy = ?
                           );
                        """, into: &check, database: database)
                    defer { sqlite3_finalize(check) }
                    bind(workoutID.uuidString, to: 1, in: check)
                    bind(workoutID.uuidString, to: 2, in: check)
                    sqlite3_bind_int64(check, 3, sqlite3_int64(point.sequence))
                    sqlite3_bind_int64(check, 4, sqlite3_int64(point.segment))
                    sqlite3_bind_double(check, 5, point.timestamp.timeIntervalSince1970)
                    sqlite3_bind_double(check, 6, point.latitude)
                    sqlite3_bind_double(check, 7, point.longitude)
                    sqlite3_bind_double(check, 8, point.horizontalAccuracy)
                    guard sqlite3_step(check) == SQLITE_ROW,
                          sqlite3_column_int(check, 0) == 1 else {
                        throw ActivityStoreError.database("The active draft is missing or this sequence belongs to a different route point.")
                    }
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
            try loadDrafts()
            storageStatus = "Walk route checkpoint saved"
            return true
        } catch {
            storageStatus = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateDraftMetrics(workoutID: UUID, steps: Int, distanceMeters: Double, at date: Date = Date()) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            var statement: OpaquePointer?
            try prepare("UPDATE workout_drafts SET updated_at = ?, steps = ?, distance_meters = ? WHERE id = ?;", into: &statement, database: database)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, sqlite3_int64(max(0, steps)))
            sqlite3_bind_double(statement, 3, max(0, distanceMeters))
            bind(workoutID.uuidString, to: 4, in: statement)
            guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1 else {
                throw ActivityStoreError.database("The active walk draft no longer exists.")
            }
            try loadDrafts()
            return true
        } catch {
            storageStatus = error.localizedDescription
            return false
        }
    }

    func routePoints(for workoutID: UUID) throws -> [JournalRoutePoint] {
        guard let database else { throw ActivityStoreError.database("Database is not open.") }
        var statement: OpaquePointer?
        try prepare("SELECT sequence, segment, timestamp, latitude, longitude, horizontal_accuracy FROM route_points WHERE workout_id = ? ORDER BY sequence;", into: &statement, database: database)
        defer { sqlite3_finalize(statement) }
        bind(workoutID.uuidString, to: 1, in: statement)
        var result: [JournalRoutePoint] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(JournalRoutePoint(
                sequence: Int(sqlite3_column_int64(statement, 0)),
                segment: Int(sqlite3_column_int64(statement, 1)),
                timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                latitude: sqlite3_column_double(statement, 3),
                longitude: sqlite3_column_double(statement, 4),
                horizontalAccuracy: sqlite3_column_double(statement, 5)
            ))
        }
        return result
    }

    @discardableResult
    func discardDraft(_ id: UUID) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            try execute("BEGIN IMMEDIATE;")
            do {
                for sql in ["DELETE FROM route_points WHERE workout_id = ?;", "DELETE FROM workout_drafts WHERE id = ?;"] {
                    var statement: OpaquePointer?
                    try prepare(sql, into: &statement, database: database)
                    defer { sqlite3_finalize(statement) }
                    bind(id.uuidString, to: 1, in: statement)
                    guard sqlite3_step(statement) == SQLITE_DONE else { throw ActivityStoreError.database(lastError(database)) }
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
            try loadDrafts()
            return true
        } catch {
            storageStatus = error.localizedDescription
            return false
        }
    }

    /// Finalization writes the completed workout and removes its draft/points atomically.
    @discardableResult
    func finalizeDraft(_ id: UUID, endedAt: Date = Date()) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            guard let draft = recoverableDrafts.first(where: { $0.id == id }) else {
                throw ActivityStoreError.database("The recoverable walk draft was not found.")
            }
            let points = try routePoints(for: id)
            let grouped = Dictionary(grouping: points, by: \.segment)
            let segments = grouped.keys.sorted().compactMap { segment in
                grouped[segment]?.sorted { $0.sequence < $1.sequence }.map {
                    WalkSession.Coordinate(latitude: $0.latitude, longitude: $0.longitude)
                }
            }.filter { !$0.isEmpty }
            let flattened = segments.flatMap { $0 }
            let session = WalkSession(
                id: id, startedAt: draft.startedAt, endedAt: endedAt,
                steps: draft.steps, distanceMeters: draft.distanceMeters,
                route: flattened, routeSegments: segments
            )
            let payload = try encoder.encode(session)
            try execute("BEGIN IMMEDIATE;")
            do {
                var statement: OpaquePointer?
                try prepare("INSERT INTO walks (id, started_at, ended_at, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET ended_at=excluded.ended_at, payload=excluded.payload;", into: &statement, database: database)
                defer { sqlite3_finalize(statement) }
                bind(id.uuidString, to: 1, in: statement)
                sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 3, endedAt.timeIntervalSince1970)
                payload.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), sqliteTransient) }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw ActivityStoreError.database(lastError(database)) }
                for sql in ["DELETE FROM route_points WHERE workout_id = ?;", "DELETE FROM workout_drafts WHERE id = ?;"] {
                    var cleanup: OpaquePointer?
                    try prepare(sql, into: &cleanup, database: database)
                    defer { sqlite3_finalize(cleanup) }
                    bind(id.uuidString, to: 1, in: cleanup)
                    guard sqlite3_step(cleanup) == SQLITE_DONE else { throw ActivityStoreError.database(lastError(database)) }
                }
                try execute("COMMIT;")
            } catch {
                try? execute("ROLLBACK;")
                throw error
            }
            try load()
            try loadDrafts()
            storageStatus = "Saved on this iPhone"
            return true
        } catch {
            storageStatus = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func save(_ session: WalkSession) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            let payload = try encoder.encode(session)
            var statement: OpaquePointer?
            try prepare("INSERT INTO walks (id, started_at, ended_at, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET ended_at=excluded.ended_at, payload=excluded.payload;", into: &statement, database: database)
            defer { sqlite3_finalize(statement) }
            bind(session.id.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
            if let endedAt = session.endedAt { sqlite3_bind_double(statement, 3, endedAt.timeIntervalSince1970) } else { sqlite3_bind_null(statement, 3) }
            payload.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), sqliteTransient) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw ActivityStoreError.database(lastError(database)) }
            try load()
            storageStatus = "Saved on this iPhone"
            return true
        } catch {
            storageStatus = error.localizedDescription
            return false
        }
    }

    private func openDatabase() throws {
        let manager = FileManager.default
        let url: URL
        if let configuredDatabaseURL {
            url = configuredDatabaseURL
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else {
            let directory = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("WALKON", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("walk-history.sqlite")
        }
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed (\(result))."
            if let handle { sqlite3_close(handle) }
            throw ActivityStoreError.databaseOpen(message)
        }
        database = handle
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=FULL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("""
            CREATE TABLE IF NOT EXISTS walks (
                id TEXT PRIMARY KEY NOT NULL, started_at REAL NOT NULL, ended_at REAL, payload BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS workout_drafts (
                id TEXT PRIMARY KEY NOT NULL, started_at REAL NOT NULL, updated_at REAL NOT NULL,
                steps INTEGER NOT NULL DEFAULT 0, distance_meters REAL NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS route_points (
                workout_id TEXT NOT NULL REFERENCES workout_drafts(id) ON DELETE CASCADE,
                sequence INTEGER NOT NULL, segment INTEGER NOT NULL, timestamp REAL NOT NULL,
                latitude REAL NOT NULL, longitude REAL NOT NULL, horizontal_accuracy REAL NOT NULL,
                PRIMARY KEY (workout_id, sequence)
            );
            CREATE INDEX IF NOT EXISTS route_points_workout_sequence ON route_points(workout_id, sequence);
            """)
        try execute("PRAGMA user_version=2;")
    }

    private func load() throws {
        guard let database else { throw ActivityStoreError.database("Database is not open.") }
        var statement: OpaquePointer?
        try prepare("SELECT payload FROM walks ORDER BY started_at DESC;", into: &statement, database: database)
        defer { sqlite3_finalize(statement) }
        var loaded: [WalkSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            loaded.append(try decoder.decode(WalkSession.self, from: data))
        }
        sessions = loaded
    }

    private func loadDrafts() throws {
        guard let database else { throw ActivityStoreError.database("Database is not open.") }
        var statement: OpaquePointer?
        try prepare("""
            SELECT d.id, d.started_at, d.updated_at, d.steps, d.distance_meters,
                   (SELECT COUNT(*) FROM route_points p WHERE p.workout_id = d.id)
            FROM workout_drafts d ORDER BY d.started_at;
            """, into: &statement, database: database)
        defer { sqlite3_finalize(statement) }
        var loaded: [WorkoutDraft] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: rawID)) else { continue }
            loaded.append(WorkoutDraft(
                id: id,
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                lastUpdatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                steps: Int(sqlite3_column_int64(statement, 3)),
                distanceMeters: sqlite3_column_double(statement, 4),
                routePointCount: Int(sqlite3_column_int64(statement, 5))
            ))
        }
        recoverableDrafts = loaded
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw ActivityStoreError.database("Database is not open.") }
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastError(database)
            sqlite3_free(errorMessage)
            throw ActivityStoreError.database(message)
        }
    }

    private func prepare(_ sql: String, into statement: inout OpaquePointer?, database: OpaquePointer) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ActivityStoreError.database(lastError(database))
        }
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer?) {
        value.withCString { sqlite3_bind_text(statement, index, $0, -1, sqliteTransient) }
    }

    private func lastError(_ database: OpaquePointer) -> String { String(cString: sqlite3_errmsg(database)) }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

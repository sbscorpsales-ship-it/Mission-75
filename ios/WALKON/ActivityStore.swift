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

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double
    }
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

/// Local-first durable store. A successful save means SQLite committed the workout
/// with synchronous durability; it does not imply HealthKit export or cloud sync.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var sessions: [WalkSession] = []
    @Published private(set) var storageStatus = "Local history ready"

    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        do {
            try openDatabase()
            try load()
        } catch {
            storageStatus = error.localizedDescription
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    @discardableResult
    func save(_ session: WalkSession) -> Bool {
        do {
            guard let database else { throw ActivityStoreError.database("Database is not open.") }
            guard let payload = try? encoder.encode(session) else { throw ActivityStoreError.encoding }
            let sql = "INSERT INTO walks (id, started_at, ended_at, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET ended_at=excluded.ended_at, payload=excluded.payload;"
            var statement: OpaquePointer?
            try prepare(sql, into: &statement, database: database)
            defer { sqlite3_finalize(statement) }
            bind(session.id.uuidString, to: 1, in: statement)
            sqlite3_bind_double(statement, 2, session.startedAt.timeIntervalSince1970)
            if let endedAt = session.endedAt {
                sqlite3_bind_double(statement, 3, endedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            payload.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActivityStoreError.database(lastError(database))
            }
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
        let directory = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("WALKON", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("walk-history.sqlite")
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
                id TEXT PRIMARY KEY NOT NULL,
                started_at REAL NOT NULL,
                ended_at REAL,
                payload BLOB NOT NULL
            );
            """)
        try execute("PRAGMA user_version=1;")
    }

    private func load() throws {
        guard let database else { throw ActivityStoreError.database("Database is not open.") }
        var statement: OpaquePointer?
        try prepare("SELECT payload FROM walks ORDER BY started_at DESC;", into: &statement, database: database)
        defer { sqlite3_finalize(statement) }
        var loaded: [WalkSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            let data = Data(bytes: bytes, count: count)
            loaded.append(try decoder.decode(WalkSession.self, from: data))
        }
        sessions = loaded
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
        value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient)
        }
    }

    private func lastError(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

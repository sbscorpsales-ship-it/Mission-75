import XCTest
@testable import WALKON

final class WALKONTests: XCTestCase {
    @MainActor
    func testSQLitePersistsWalkAndDeduplicatesRetry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let first = WalkSession(
            id: id,
            startedAt: started,
            endedAt: started.addingTimeInterval(600),
            steps: 812,
            distanceMeters: 523.4,
            route: [.init(latitude: 15.85, longitude: 74.50)]
        )
        let store = ActivityStore(databaseURL: databaseURL)
        XCTAssertTrue(store.save(first))
        XCTAssertEqual(store.sessions.count, 1)

        var retried = first
        retried.steps = 813
        XCTAssertTrue(store.save(retried))
        XCTAssertEqual(store.sessions.count, 1, "Retry with same workout ID must not create a duplicate.")
        XCTAssertEqual(store.sessions.first?.steps, 813)

        let reopened = ActivityStore(databaseURL: databaseURL)
        XCTAssertEqual(reopened.sessions.count, 1)
        XCTAssertEqual(reopened.sessions.first?.id, id)
        XCTAssertEqual(reopened.sessions.first?.steps, 813)
        XCTAssertEqual(reopened.sessions.first?.route.count, 1)
    }

    func testWalkSessionCodableRoundTrip() throws {
        let session = WalkSession(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: nil,
            steps: 0,
            distanceMeters: 0,
            route: []
        )
        let data = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(WalkSession.self, from: data), session)
    }
}

import XCTest
@testable import WALKON

final class ActivityModelTests: XCTestCase {
    func testWalkSessionDurationAndCodableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let route = [
            WalkSession.RoutePoint(latitude: 15.85, longitude: 74.50,
                                   timestamp: start.addingTimeInterval(10),
                                   horizontalAccuracy: 6)
        ]
        let session = WalkSession(id: UUID(), startedAt: start,
                                  endedAt: start.addingTimeInterval(90),
                                  steps: 125, distanceMeters: 82.5, route: route)
        XCTAssertEqual(session.duration, 90, accuracy: 0.001)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WalkSession.self, from: encoder.encode(session))

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.steps, 125)
        XCTAssertEqual(decoded.distanceMeters, 82.5, accuracy: 0.001)
        XCTAssertEqual(decoded.route.count, 1)
        XCTAssertEqual(decoded.route[0].latitude, 15.85, accuracy: 0.000001)
    }

    func testNegativeDurationIsClampedToZero() {
        let now = Date()
        let session = WalkSession(id: UUID(), startedAt: now,
                                  endedAt: now.addingTimeInterval(-5),
                                  steps: 0, distanceMeters: 0, route: [])
        XCTAssertEqual(session.duration, 0)
    }

    func testActiveWalkSnapshotRoundTripsRecoveryState() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = start.addingTimeInterval(300)
        let point = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.50,
                                           timestamp: saved, horizontalAccuracy: 8)
        let snapshot = ActiveWalkSnapshot(startedAt: start, savedAt: saved,
                                          steps: 420, distanceMeters: 310,
                                          route: [point])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ActiveWalkSnapshot.self, from: encoder.encode(snapshot))

        XCTAssertEqual(decoded.startedAt, start)
        XCTAssertEqual(decoded.savedAt, saved)
        XCTAssertEqual(decoded.steps, 420)
        XCTAssertEqual(decoded.distanceMeters, 310, accuracy: 0.001)
        XCTAssertEqual(decoded.route.count, 1)
    }
    func testRouteDistanceAcceptsPlausibleWalkingMovement() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.50,
                                              timestamp: start, horizontalAccuracy: 5)
        let next = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.5001,
                                          timestamp: start.addingTimeInterval(5),
                                          horizontalAccuracy: 7)
        let distance = WalkSession.acceptedDistance(from: previous, to: next)
        XCTAssertNotNil(distance)
        XCTAssertGreaterThan(distance ?? 0, 0)
    }

    func testRouteDistanceRejectsLongGpsGapAndImplausibleJump() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.50,
                                              timestamp: start, horizontalAccuracy: 5)
        let longGap = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.5001,
                                             timestamp: start.addingTimeInterval(31),
                                             horizontalAccuracy: 5)
        let fastJump = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.501,
                                              timestamp: start.addingTimeInterval(5),
                                              horizontalAccuracy: 5)
        XCTAssertNil(WalkSession.acceptedDistance(from: previous, to: longGap))
        XCTAssertNil(WalkSession.acceptedDistance(from: previous, to: fastJump))
    }

    func testRouteDistanceRejectsPoorGpsAccuracy() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.50,
                                              timestamp: start, horizontalAccuracy: 5)
        let inaccurate = WalkSession.RoutePoint(latitude: 15.85, longitude: 74.5001,
                                                timestamp: start.addingTimeInterval(5),
                                                horizontalAccuracy: 50)
        XCTAssertNil(WalkSession.acceptedDistance(from: previous, to: inaccurate))
    }


    @MainActor func testExpiredActiveWalkCheckpointIsDiscarded() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKON-expired-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ActivityStore(storageDirectory: directory)
        store.checkpoint(startedAt: Date().addingTimeInterval(-60),
                         steps: 90, distanceMeters: 75, route: [])

        let expiredTime = Date().addingTimeInterval(24 * 60 * 60 + 1)
        XCTAssertNil(store.recoverActiveWalk(now: expiredTime))
    }

}


final class ActivityStorePersistenceTests: XCTestCase {
    @MainActor func testSavedWalkLoadsFromLocalStorage() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKON-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ActivityStore(storageDirectory: directory)
        let start = Date().addingTimeInterval(-120)
        let session = WalkSession(id: UUID(), startedAt: start,
                                  endedAt: start.addingTimeInterval(120),
                                  steps: 250, distanceMeters: 180, route: [])
        XCTAssertTrue(store.save(session))

        let reloaded = ActivityStore(storageDirectory: directory)
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions.first?.id, session.id)
        XCTAssertEqual(reloaded.sessions.first?.steps ?? -1, 250)
    }

    @MainActor func testActiveWalkCheckpointCanBeRecovered() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKON-recovery-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ActivityStore(storageDirectory: directory)
        let start = Date().addingTimeInterval(-60)
        store.checkpoint(startedAt: start, steps: 90, distanceMeters: 75, route: [])

        let recovered = ActivityStore(storageDirectory: directory).recoverActiveWalk()
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered?.steps, 90)
        XCTAssertEqual(recovered?.distanceMeters ?? -1, 75, accuracy: 0.001)
    }
}

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
}

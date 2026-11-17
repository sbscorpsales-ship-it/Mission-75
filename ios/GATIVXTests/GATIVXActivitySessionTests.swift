import XCTest
import CoreLocation
@testable import GATIVX

final class GATIVXActivitySessionTests: XCTestCase {
    func testRouteDistanceDoesNotBridgeGPSSegmentBreaks() {
        let points = [
            routePoint(latitude: 15.8500, longitude: 74.5000, breakBefore: true),
            routePoint(latitude: 15.8510, longitude: 74.5000),
            routePoint(latitude: 16.0000, longitude: 74.7000, breakBefore: true),
            routePoint(latitude: 16.0010, longitude: 74.7000)
        ]

        let record = activityRecord(routePoints: points)
        let firstLeg = location(points[0]).distance(from: location(points[1]))
        let secondLeg = location(points[2]).distance(from: location(points[3]))

        XCTAssertEqual(record.gpsDistanceMeters, firstLeg + secondLeg, accuracy: 0.01)
    }

    func testLegacyRoutePointWithoutSegmentMarkerStillDecodes() throws {
        let json = """
        {
          "latitude": 15.85,
          "longitude": 74.50,
          "timestamp": 1800000000,
          "horizontalAccuracy": 4
        }
        """

        let point = try JSONDecoder().decode(GATIVXRoutePoint.self, from: Data(json.utf8))

        XCTAssertFalse(point.breakBefore)
        XCTAssertEqual(point.latitude, 15.85, accuracy: 0.000001)
        XCTAssertEqual(point.longitude, 74.50, accuracy: 0.000001)
    }

    func testUnavailableStepCountRemainsNilAfterPersistenceRoundTrip() throws {
        let record = activityRecord(steps: nil)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ActivitySessionRecord.self, from: encoded)

        XCTAssertNil(decoded.steps)
    }

    func testDurationUsesMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let record = activityRecord(
            startedAt: start,
            finishedAt: start.addingTimeInterval(125)
        )

        XCTAssertEqual(record.durationText, "2:05")
    }

    private func routePoint(
        latitude: Double,
        longitude: Double,
        breakBefore: Bool = false
    ) -> GATIVXRoutePoint {
        GATIVXRoutePoint(
            latitude: latitude,
            longitude: longitude,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            horizontalAccuracy: 4,
            breakBefore: breakBefore
        )
    }

    private func location(_ point: GATIVXRoutePoint) -> CLLocation {
        CLLocation(latitude: point.latitude, longitude: point.longitude)
    }

    private func activityRecord(
        steps: Int? = 120,
        routePoints: [GATIVXRoutePoint]? = nil,
        startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        finishedAt: Date = Date(timeIntervalSince1970: 1_800_000_060)
    ) -> ActivitySessionRecord {
        ActivitySessionRecord(
            id: UUID(),
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: steps,
            routePoints: routePoints,
            motionDistanceMeters: nil
        )
    }
}

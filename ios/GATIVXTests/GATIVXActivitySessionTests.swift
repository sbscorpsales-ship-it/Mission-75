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

    func testActivityOwnerIDSurvivesPersistenceRoundTrip() throws {
        let record = activityRecord(ownerID: "account-123")
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ActivitySessionRecord.self, from: encoded)

        XCTAssertEqual(decoded.ownerID, "account-123")
    }

    func testLegacyActivityWithoutOwnerIDDecodesAsUnassigned() throws {
        let record = activityRecord()
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ActivitySessionRecord.self, from: encoded)

        XCTAssertNil(decoded.ownerID)
    }

    func testMetadataOnlyImportedSessionIsNotCloudSyncEligible() {
        let metadataOnly = activityRecord(steps: nil)
        let withMeasuredSteps = activityRecord(steps: 12)
        let withGPSRoute = activityRecord(
            steps: nil,
            routePoints: [routePoint(latitude: 15.85, longitude: 74.50)]
        )

        XCTAssertFalse(metadataOnly.hasCloudSyncPayload)
        XCTAssertTrue(withMeasuredSteps.hasCloudSyncPayload)
        XCTAssertTrue(withGPSRoute.hasCloudSyncPayload)
    }

    func testDurationUsesMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let record = activityRecord(
            startedAt: start,
            finishedAt: start.addingTimeInterval(125)
        )

        XCTAssertEqual(record.durationText, "2:05")
    }

    func testActivityStoreAtomicallySavesAndReadsBackHistory() throws {
        let (store, directory, defaults, suiteName) = makeActivityStore()
        defer { cleanUpActivityStore(directory, defaults: defaults, suiteName: suiteName) }

        let record = activityRecord()
        try store.save([record])

        let restored = try store.load()
        XCTAssertEqual(restored.map(\.id), [record.id])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("activity-history.json").path
        ))
    }

    func testActivityStoreMigratesLegacyDefaultsAfterFileVerification() throws {
        let (store, directory, defaults, suiteName) = makeActivityStore()
        defer { cleanUpActivityStore(directory, defaults: defaults, suiteName: suiteName) }

        let record = activityRecord()
        defaults.set(
            try JSONEncoder().encode([record]),
            forKey: "gativx.activitySessions.v1"
        )

        let restored = try store.load()

        XCTAssertEqual(restored.map(\.id), [record.id])
        XCTAssertNil(defaults.data(forKey: "gativx.activitySessions.v1"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("activity-history.json").path
        ))
    }

    func testCorruptActivityFileIsPreservedAndDoesNotFallBackToLegacyData() throws {
        let (store, directory, defaults, suiteName) = makeActivityStore()
        defer { cleanUpActivityStore(directory, defaults: defaults, suiteName: suiteName) }

        let fileURL = directory.appendingPathComponent("activity-history.json")
        let corruptData = Data("not-json".utf8)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try corruptData.write(to: fileURL)
        defaults.set(
            try JSONEncoder().encode([activityRecord()]),
            forKey: "gativx.activitySessions.v1"
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: fileURL), corruptData)
        XCTAssertNotNil(defaults.data(forKey: "gativx.activitySessions.v1"))
    }

    func testActivityStorePreservesLegacyDataWhenMigrationWriteFails() throws {
        let suiteName = "GATIVXTests.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let blockingFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: false)
        let blockingData = Data("not-a-directory".utf8)
        try blockingData.write(to: blockingFile)
        defer {
            try? FileManager.default.removeItem(at: blockingFile)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let record = activityRecord()
        let legacyData = try JSONEncoder().encode([record])
        defaults.set(legacyData, forKey: "gativx.activitySessions.v1")
        let store = ActivitySessionStore(
            userDefaults: defaults,
            directoryOverride: blockingFile
        )

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(
            defaults.data(forKey: "gativx.activitySessions.v1"),
            legacyData
        )
        XCTAssertEqual(try Data(contentsOf: blockingFile), blockingData)
    }

    func testMemberProfilePhotoStoreSavesAndReadsBackData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXPhotoTests.\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemberProfilePhotoStore(directoryOverride: directory)
        let photoData = Data([0xFF, 0xD8, 0xFF, 0xD9])

        try store.save(photoData)

        XCTAssertEqual(try store.load(), photoData)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("member-profile-photo.jpg").path
        ))
    }

    func testMemberProfilePhotoStoreRejectsEmptyDataWithoutReplacingExistingPhoto() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXPhotoTests.\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemberProfilePhotoStore(directoryOverride: directory)
        let existingPhoto = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try store.save(existingPhoto)

        XCTAssertThrowsError(try store.save(Data()))
        XCTAssertEqual(try store.load(), existingPhoto)
    }

    func testMemberProfilePhotoStoreDeletesPhoto() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXPhotoTests.\\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemberProfilePhotoStore(directoryOverride: directory)
        try store.save(Data([0xFF, 0xD8, 0xFF, 0xD9]))

        try store.delete()

        XCTAssertNil(try store.load())
    }

    private func makeActivityStore() -> (ActivitySessionStore, URL, UserDefaults, String) {
        let suiteName = "GATIVXTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let store = ActivitySessionStore(
            userDefaults: defaults,
            directoryOverride: directory
        )
        return (store, directory, defaults, suiteName)
    }

    private func cleanUpActivityStore(
        _ directory: URL,
        defaults: UserDefaults,
        suiteName: String
    ) {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
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
        finishedAt: Date = Date(timeIntervalSince1970: 1_800_000_060),
        ownerID: String? = nil
    ) -> ActivitySessionRecord {
        ActivitySessionRecord(
            id: UUID(),
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: steps,
            routePoints: routePoints,
            motionDistanceMeters: nil,
            ownerID: ownerID
        )
    }
}

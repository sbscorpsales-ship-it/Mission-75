import XCTest
@testable import GATIVX

final class GPSRouteDraftPersistenceTests: XCTestCase {
    func testWriteAtomicallyReadsBackSessionOwnerAndRoute() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXGPSDraftTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("active-route-draft.json")
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID()
        let points = [
            GATIVXRoutePoint(latitude: 15.85, longitude: 74.50, timestamp: startedAt, horizontalAccuracy: 5, breakBefore: true),
            GATIVXRoutePoint(latitude: 15.851, longitude: 74.501, timestamp: startedAt.addingTimeInterval(5), horizontalAccuracy: 4)
        ]
        let draft = GATIVXActiveRouteDraft(
            startedAt: startedAt,
            activity: "Walking",
            points: points,
            sessionID: sessionID,
            ownerID: "member-original"
        )

        try GPSRouteDraftPersistence.write(draft, to: url)

        let savedData = try Data(contentsOf: url)
        let restored = try JSONDecoder().decode(GATIVXActiveRouteDraft.self, from: savedData)
        XCTAssertEqual(restored.sessionID, sessionID)
        XCTAssertEqual(restored.ownerID, "member-original")
        XCTAssertEqual(restored.startedAt, startedAt)
        XCTAssertEqual(restored.activity, "Walking")
        XCTAssertEqual(restored.points.count, 2)
        XCTAssertEqual(restored.points.map(\.latitude), points.map(\.latitude))
        XCTAssertEqual(restored.points.map(\.breakBefore), [true, false])
    }

    func testWriteFailureDoesNotReplaceExistingData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXGPSDraftBlocker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let blocker = directory.appendingPathComponent("not-a-directory")
        let original = Data("preserve-existing-data".utf8)
        try original.write(to: blocker)
        let impossibleURL = blocker.appendingPathComponent("active-route-draft.json")
        let draft = GATIVXActiveRouteDraft(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            activity: "Walking",
            points: [],
            sessionID: UUID(),
            ownerID: "member-original"
        )

        XCTAssertThrowsError(try GPSRouteDraftPersistence.write(draft, to: impossibleURL))
        XCTAssertEqual(try Data(contentsOf: blocker), original)
    }
}

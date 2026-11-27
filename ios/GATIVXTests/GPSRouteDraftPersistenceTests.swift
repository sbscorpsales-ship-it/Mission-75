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

    func testUnreadableExistingDraftBlocksNewWalkAndPreservesOriginalData() async throws {
        try await MainActor.run {
            let suite = "GATIVXGPSUnreadableDraftTests-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(suite, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            // A directory at the draft-file path makes Data(contentsOf:) fail
            // while fileExists(atPath:) still confirms that an entry is present.
            let unreadableDraft = directory.appendingPathComponent("active-route-draft.json", isDirectory: true)
            try FileManager.default.createDirectory(at: unreadableDraft, withIntermediateDirectories: true)
            let sentinel = unreadableDraft.appendingPathComponent("preserve-me.txt")
            let original = Data("do-not-overwrite-this-draft".utf8)
            try original.write(to: sentinel)

            let recorder = GPSRouteRecorder(
                fileManager: .default,
                userDefaults: defaults,
                directoryOverride: directory
            )

            XCTAssertTrue(recorder.hasUnreadableDraft)
            XCTAssertTrue(recorder.status.contains("preserved"))
            recorder.start(activity: "Walking", ownerID: "member-original")
            XCTAssertNil(recorder.activitySessionID, "A new session must not replace an unreadable existing draft.")
            XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
            XCTAssertEqual(try Data(contentsOf: sentinel), original)
        }
    }
#if DEBUG
    @MainActor
    func testDebugUITestRouteFixturePersistsAndClearsOnlyItsOwnSession() throws {
        let suite = "GATIVXGPSUITestFixture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }

        let recorder = GPSRouteRecorder(
            fileManager: .default,
            userDefaults: defaults,
            directoryOverride: directory
        )
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID(uuidString: "00000000-0000-4000-8000-000000000124")!
        let points = [
            GATIVXRoutePoint(
                latitude: 0,
                longitude: 0,
                timestamp: startedAt,
                horizontalAccuracy: 4,
                breakBefore: true
            ),
            GATIVXRoutePoint(
                latitude: 0,
                longitude: 0.0002,
                timestamp: startedAt.addingTimeInterval(18),
                horizontalAccuracy: 4
            )
        ]

        XCTAssertTrue(recorder.installUITestRoute(
            activity: "Walking",
            startedAt: startedAt,
            points: points,
            sessionID: sessionID
        ))
        XCTAssertEqual(recorder.points, points)
        XCTAssertEqual(recorder.activitySessionID, sessionID)
        XCTAssertFalse(recorder.isRecording,
                       "A deterministic UI fixture must not claim live Core Location recording.")

        let draftURL = directory.appendingPathComponent("active-route-draft.json")
        let persisted = try JSONDecoder().decode(
            GATIVXActiveRouteDraft.self,
            from: Data(contentsOf: draftURL)
        )
        XCTAssertEqual(persisted.sessionID, sessionID)
        XCTAssertEqual(persisted.points, points)

        recorder.clearUITestRouteAfterVerifiedSave(sessionID: sessionID)
        XCTAssertTrue(recorder.points.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
    }
#endif

}

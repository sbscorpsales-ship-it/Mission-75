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

    @MainActor
    func testStartingNewActivityCannotReplaceRecoveredGPSDraft() throws {
        let suiteName = "GATIVXGPSDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID()
        let draft: [String: Any] = [
            "startedAt": startedAt.timeIntervalSinceReferenceDate,
            "activity": "Walking",
            "sessionID": sessionID.uuidString,
            "ownerID": "account-original",
            "points": [[
                "latitude": 15.85,
                "longitude": 74.50,
                "timestamp": startedAt.timeIntervalSinceReferenceDate,
                "horizontalAccuracy": 5.0,
                "breakBefore": true
            ]]
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: draft), forKey: "gativx.activeRouteDraft.v1")

        let recorder = GPSRouteRecorder(
            userDefaults: defaults,
            directoryOverride: directory
        )
        XCTAssertEqual(recorder.recoveredStartedAt, startedAt)
        XCTAssertEqual(recorder.recoveredActivity, "Walking")
        XCTAssertEqual(recorder.points.count, 1)
        XCTAssertEqual(recorder.activitySessionID, sessionID)
        XCTAssertEqual(recorder.activityOwnerID, "account-original")

        recorder.start(activity: "Running", ownerID: "account-new")

        XCTAssertEqual(recorder.recoveredStartedAt, startedAt)
        XCTAssertEqual(recorder.recoveredActivity, "Walking")
        XCTAssertEqual(recorder.points.count, 1)
        XCTAssertEqual(recorder.activitySessionID, sessionID)
        XCTAssertEqual(recorder.activityOwnerID, "account-original")
    }

    @MainActor
    func testStartingNewActivityCannotOverwriteUnreadableGPSDraft() throws {
        let suiteName = "GATIVXUnreadableGPSDraftTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let draftURL = directory.appendingPathComponent("active-route-draft.json")
        let corruptData = Data("preserve-this-route".utf8)
        try corruptData.write(to: draftURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let recorder = GPSRouteRecorder(
            userDefaults: defaults,
            directoryOverride: directory
        )
        XCTAssertTrue(recorder.hasUnreadableDraft)
        XCTAssertNil(recorder.recoveredStartedAt)

        recorder.start(activity: "Running", ownerID: "new-account")

        XCTAssertTrue(recorder.hasUnreadableDraft)
        XCTAssertEqual(try Data(contentsOf: draftURL), corruptData)
        XCTAssertTrue(recorder.status.contains("remains preserved"))
    }

    func testRecoveryUpsertMergesLongerRouteAndPreservesKnownStepsAndOwner() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let pointA = routePoint(latitude: 15.8500, longitude: 74.5000, breakBefore: true)
        let pointB = routePoint(latitude: 15.8501, longitude: 74.5000)
        let pointC = routePoint(latitude: 15.8510, longitude: 74.5000)
        let existing = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: 120,
            routePoints: [pointA, pointB],
            motionDistanceMeters: 12,
            ownerID: "account-original"
        )
        let recovered = ActivitySessionRecord(
            id: sessionID,
            activity: "Running",
            startedAt: startedAt.addingTimeInterval(5),
            finishedAt: startedAt.addingTimeInterval(120),
            steps: 118,
            routePoints: [pointA, pointC],
            motionDistanceMeters: 10,
            ownerID: "account-original"
        )
        let store = ActivitySessionStore()

        let merged = store.upserting(recovered, into: [existing])

        XCTAssertEqual(merged.count, 1, "Recovery must not create a duplicate session")
        XCTAssertEqual(merged[0].id, sessionID)
        XCTAssertEqual(merged[0].activity, "Walking")
        XCTAssertEqual(merged[0].startedAt, startedAt)
        XCTAssertEqual(merged[0].finishedAt, recovered.finishedAt)
        XCTAssertEqual(merged[0].steps, 120, "A recovered lower count must not replace a known count")
        XCTAssertEqual(merged[0].routePoints?.count, 2)
        XCTAssertGreaterThan(merged[0].gpsDistanceMeters, existing.gpsDistanceMeters)
        XCTAssertEqual(merged[0].ownerID, "account-original", "Recovery must not transfer an owned session")
        XCTAssertEqual(merged[0].motionDistanceMeters, 12)

        let repeatedRecovery = store.upserting(merged[0], into: merged)
        XCTAssertEqual(repeatedRecovery.count, 1, "Repeating recovery must remain idempotent")
        XCTAssertEqual(repeatedRecovery[0].id, sessionID)
        XCTAssertEqual(repeatedRecovery[0].steps, 120)
        XCTAssertEqual(repeatedRecovery[0].routePoints?.count, 2)
        XCTAssertEqual(repeatedRecovery[0].ownerID, "account-original")
    }

    func testRecoveryUpsertDoesNotAssignOwnerToLocalOnlySession() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: 120,
            routePoints: nil,
            motionDistanceMeters: nil,
            ownerID: nil
        )
        let recovered = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(90),
            steps: 125,
            routePoints: nil,
            motionDistanceMeters: nil,
            ownerID: "newly-signed-in-account"
        )

        let merged = ActivitySessionStore().upserting(recovered, into: [existing])

        XCTAssertEqual(merged.count, 2, "A different owner must receive a separate record rather than merging into local-only history.")
        XCTAssertEqual(merged.first(where: { $0.ownerID == nil })?.steps, 120)
        XCTAssertEqual(merged.first(where: { $0.ownerID == "newly-signed-in-account" })?.steps, 125)
        XCTAssertNil(
            existing.mergingRecovery(recovered).ownerID,
            "The existing local-only record must retain its nil owner even if a different-owner recovery is presented."
        )
    }

    func testRecoveryUpsertKeepsSameUUIDIsolatedAcrossOwners() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: 120,
            routePoints: nil,
            motionDistanceMeters: nil,
            ownerID: "account-A"
        )
        let recovered = ActivitySessionRecord(
            id: sessionID,
            activity: "Running",
            startedAt: startedAt.addingTimeInterval(5),
            finishedAt: startedAt.addingTimeInterval(90),
            steps: 250,
            routePoints: nil,
            motionDistanceMeters: nil,
            ownerID: "account-B"
        )

        let records = ActivitySessionStore().upserting(recovered, into: [existing])

        XCTAssertEqual(records.count, 2, "The same UUID under different owners must not be merged.")
        XCTAssertEqual(records.first(where: { $0.ownerID == "account-A" })?.steps, 120)
        XCTAssertEqual(records.first(where: { $0.ownerID == "account-B" })?.steps, 250)
        XCTAssertEqual(records.first(where: { $0.ownerID == "account-A" })?.activity, "Walking")
        XCTAssertEqual(records.first(where: { $0.ownerID == "account-B" })?.activity, "Running")
    }

    func testRecoveryUpsertFillsMissingStepsAndKeepsLongerExistingRoute() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let pointA = routePoint(latitude: 15.8500, longitude: 74.5000, breakBefore: true)
        let pointB = routePoint(latitude: 15.8510, longitude: 74.5000)
        let pointC = routePoint(latitude: 15.8520, longitude: 74.5000)
        let existing = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: nil,
            routePoints: [pointA, pointB, pointC],
            motionDistanceMeters: nil,
            ownerID: "account-original"
        )
        let recovered = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(90),
            steps: 95,
            routePoints: [pointA, pointB],
            motionDistanceMeters: 20,
            ownerID: "account-original"
        )
        let store = ActivitySessionStore()

        let merged = store.upserting(recovered, into: [existing])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].steps, 95, "A verified recovered step count should fill a missing value")
        XCTAssertEqual(merged[0].routePoints?.count, 3, "The longer previously saved route must win")
        XCTAssertEqual(merged[0].ownerID, "account-original")
        XCTAssertEqual(merged[0].motionDistanceMeters, 20)
    }

    func testActivityOutboxMergesRecoveredRouteAndPreservesNewerRevision() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let pointA = routePoint(latitude: 15.8500, longitude: 74.5000, breakBefore: true)
        let pointB = routePoint(latitude: 15.8501, longitude: 74.5000)
        let pointC = routePoint(latitude: 15.8510, longitude: 74.5000)
        let existing = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: 250,
            routePoints: [pointA, pointB],
            motionDistanceMeters: 18,
            ownerID: "account-original"
        )
        let recovered = ActivitySessionRecord(
            id: sessionID,
            activity: "Running",
            startedAt: startedAt.addingTimeInterval(5),
            finishedAt: startedAt.addingTimeInterval(120),
            steps: nil,
            routePoints: [pointA, pointC],
            motionDistanceMeters: 12,
            ownerID: "account-original"
        )
        let queuedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let firstRevision = UUID()
        let newerRevision = UUID()
        let queued = ActivitySessionOutboxQueue.upserting(
            existing,
            ownerID: "account-original",
            into: [],
            revisionID: firstRevision,
            queuedAt: queuedAt
        )

        let updated = ActivitySessionOutboxQueue.upserting(
            recovered,
            ownerID: "account-original",
            into: queued,
            revisionID: newerRevision
        )

        XCTAssertEqual(updated.count, 1, "Recovery must update the pending session instead of creating a duplicate")
        XCTAssertEqual(updated[0].ownerID, "account-original")
        XCTAssertEqual(updated[0].record.ownerID, "account-original")
        XCTAssertEqual(updated[0].record.steps, 250, "A recovered draft must not discard the known step count")
        XCTAssertEqual(updated[0].record.routePoints, recovered.routePoints, "The improved route must replace the stale queued route")
        XCTAssertEqual(updated[0].record.finishedAt, recovered.finishedAt)
        XCTAssertEqual(updated[0].queuedAt, queuedAt)
        XCTAssertEqual(updated[0].revisionID, newerRevision)
        XCTAssertNotEqual(updated[0].revisionID, firstRevision)

        let staleAcknowledgement = ActivitySessionOutboxQueue.acknowledging(queued[0], from: updated)
        XCTAssertEqual(staleAcknowledgement, updated, "An older in-flight upload must not acknowledge the recovered revision")

        let repeatedRecovery = ActivitySessionOutboxQueue.upserting(
            recovered,
            ownerID: "account-original",
            into: updated,
            revisionID: UUID()
        )
        XCTAssertEqual(repeatedRecovery, updated, "Retrying the same recovery must remain idempotent")
    }

    func testActivityOutboxKeepsSameSessionUUIDIsolatedByOwner() {
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let memberA = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: 100,
            routePoints: nil,
            motionDistanceMeters: nil,
            ownerID: "member-a"
        )
        let memberB = ActivitySessionRecord(
            id: sessionID,
            activity: "Running",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(90),
            steps: 200,
            routePoints: nil,
            motionDistanceMeters: nil,
            ownerID: "member-b"
        )
        let first = ActivitySessionOutboxQueue.upserting(memberA, ownerID: "member-a", into: [])
        let both = ActivitySessionOutboxQueue.upserting(memberB, ownerID: "member-b", into: first)

        XCTAssertEqual(both.count, 2, "Identical session UUIDs owned by different accounts must not collide")
        XCTAssertEqual(Set(both.map(\.ownerID)), Set(["member-a", "member-b"]))
        XCTAssertEqual(both.first(where: { $0.ownerID == "member-a" })?.record.steps, 100)
        XCTAssertEqual(both.first(where: { $0.ownerID == "member-b" })?.record.steps, 200)
    }

    func testCrashAfterHistoryWriteBeforeDraftClearRecoversSameSessionOnDisk() throws {
        let (store, directory, defaults, suiteName) = makeActivityStore()
        defer { cleanUpActivityStore(directory, defaults: defaults, suiteName: suiteName) }

        let sessionID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let pointA = routePoint(latitude: 15.8500, longitude: 74.5000, breakBefore: true)
        let shortPoint = routePoint(latitude: 15.8501, longitude: 74.5000)
        let longerPoint = routePoint(latitude: 15.8510, longitude: 74.5000)
        let alreadyWritten = ActivitySessionRecord(
            id: sessionID,
            activity: "Walking",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(60),
            steps: 250,
            routePoints: [pointA, shortPoint],
            motionDistanceMeters: 18,
            ownerID: "account-original"
        )
        try store.save([alreadyWritten])

        // Simulate a crash after the history write succeeded but before the GPS draft was cleared.
        let recoveredDraft = ActivitySessionRecord(
            id: sessionID,
            activity: "Running",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(120),
            steps: nil,
            routePoints: [pointA, longerPoint],
            motionDistanceMeters: 12,
            ownerID: "account-original"
        )
        let recoveredHistory = store.upserting(recoveredDraft, into: try store.load())
        try store.save(recoveredHistory)

        // A second relaunch/retry must not append another copy or lose the better measurements.
        let repeatedHistory = store.upserting(recoveredDraft, into: try store.load())
        try store.save(repeatedHistory)
        let persisted = try store.load()

        XCTAssertEqual(persisted.count, 1)
        let restored = try XCTUnwrap(persisted.first)
        XCTAssertEqual(restored.id, sessionID)
        XCTAssertEqual(restored.activity, "Walking")
        XCTAssertEqual(restored.startedAt, startedAt)
        XCTAssertEqual(restored.finishedAt, recoveredDraft.finishedAt)
        XCTAssertEqual(restored.steps, 250)
        XCTAssertEqual(restored.routePoints?.count, 2)
        XCTAssertGreaterThan(restored.gpsDistanceMeters, alreadyWritten.gpsDistanceMeters)
        XCTAssertEqual(restored.motionDistanceMeters, 18)
        XCTAssertEqual(restored.ownerID, "account-original")
    }

    func testDurationUsesMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let record = activityRecord(
            startedAt: start,
            finishedAt: start.addingTimeInterval(125)
        )

        XCTAssertEqual(record.durationText, "2:05")
    }

    func testActivityStoreCanRetryAfterTransientSaveFailure() throws {
        let suiteName = "GATIVXRetrySaveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let blockingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: false)
        let blockingData = Data("temporary-storage-blocker".utf8)
        try blockingData.write(to: blockingPath)
        defer {
            try? FileManager.default.removeItem(at: blockingPath)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = ActivitySessionStore(
            userDefaults: defaults,
            directoryOverride: blockingPath
        )
        let record = activityRecord(ownerID: "account-retry")

        XCTAssertThrowsError(try store.save([record]))
        XCTAssertEqual(try Data(contentsOf: blockingPath), blockingData)

        // Once storage becomes available, the same activity can be retried and verified.
        try FileManager.default.removeItem(at: blockingPath)
        try store.save([record])
        let restored = try store.load()

        XCTAssertEqual(restored.map(\.id), [record.id])
        XCTAssertEqual(restored.first?.ownerID, "account-retry")
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
        let suiteName = "GATIVXTests.\(UUID().uuidString)"
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
            .appendingPathComponent("GATIVXPhotoTests.\(UUID().uuidString)", isDirectory: true)
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
            .appendingPathComponent("GATIVXPhotoTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemberProfilePhotoStore(directoryOverride: directory)
        let existingPhoto = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try store.save(existingPhoto)

        XCTAssertThrowsError(try store.save(Data()))
        XCTAssertEqual(try store.load(), existingPhoto)
    }

    func testMemberProfilePhotoStoreDeletesPhoto() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXPhotoTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MemberProfilePhotoStore(directoryOverride: directory)
        try store.save(Data([0xFF, 0xD8, 0xFF, 0xD9]))

        try store.delete()

        XCTAssertNil(try store.load())
    }

    func testDistanceUsesGPSThenPedometerThenStrideFallback() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let gpsPoints = [
            GATIVXRoutePoint(latitude: 15.8500, longitude: 74.5000, timestamp: start, horizontalAccuracy: 4, breakBefore: true),
            GATIVXRoutePoint(latitude: 15.8510, longitude: 74.5000, timestamp: start.addingTimeInterval(10), horizontalAccuracy: 4)
        ]
        let gps = ActivitySessionRecord(id: UUID(), activity: "Walking", startedAt: start, finishedAt: start.addingTimeInterval(60), steps: 100, routePoints: gpsPoints, motionDistanceMeters: 50)
        XCTAssertEqual(gps.distance(heightCm: 176).source, .gps)
        let motion = ActivitySessionRecord(id: UUID(), activity: "Walking", startedAt: start, finishedAt: start.addingTimeInterval(60), steps: 100, routePoints: nil, motionDistanceMeters: 50)
        XCTAssertEqual(motion.distance(heightCm: 176).meters, 50)
        XCTAssertEqual(motion.distance(heightCm: 176).source, .pedometer)
        let stride = ActivitySessionRecord(id: UUID(), activity: "Walking", startedAt: start, finishedAt: start.addingTimeInterval(60), steps: 100, routePoints: nil, motionDistanceMeters: nil)
        XCTAssertEqual(stride.distance(heightCm: 176).meters!, 73.04, accuracy: 0.001)
        XCTAssertEqual(stride.distance(heightCm: 176).source, .strideEstimate)
        XCTAssertNil(stride.distance(heightCm: nil).meters)
    }

    func testActiveTimeCountsMovingGPSIntervalsOnly() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [
            GATIVXRoutePoint(latitude: 15.8500, longitude: 74.5000, timestamp: start, horizontalAccuracy: 4, breakBefore: true),
            GATIVXRoutePoint(latitude: 15.8501, longitude: 74.5000, timestamp: start.addingTimeInterval(10), horizontalAccuracy: 4),
            GATIVXRoutePoint(latitude: 15.8501, longitude: 74.5000, timestamp: start.addingTimeInterval(20), horizontalAccuracy: 4),
            GATIVXRoutePoint(latitude: 15.8502, longitude: 74.5000, timestamp: start.addingTimeInterval(30), horizontalAccuracy: 4),
            GATIVXRoutePoint(latitude: 15.8503, longitude: 74.5000, timestamp: start.addingTimeInterval(90), horizontalAccuracy: 4, breakBefore: true)
        ]
        let record = ActivitySessionRecord(id: UUID(), activity: "Walking", startedAt: start, finishedAt: start.addingTimeInterval(120), steps: 100, routePoints: points, motionDistanceMeters: nil)
        XCTAssertEqual(record.activeDurationSeconds, 20)
        XCTAssertEqual(record.activeDurationText, "0:20")
    }

    func testActiveTimeIsUnavailableWhenGPSHasNoMovingIntervals() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let points = [
            GATIVXRoutePoint(latitude: 15.8500, longitude: 74.5000, timestamp: start, horizontalAccuracy: 4, breakBefore: true),
            GATIVXRoutePoint(latitude: 15.8500, longitude: 74.5000, timestamp: start.addingTimeInterval(10), horizontalAccuracy: 4)
        ]
        let record = ActivitySessionRecord(id: UUID(), activity: "Walking", startedAt: start, finishedAt: start.addingTimeInterval(60), steps: 100, routePoints: points, motionDistanceMeters: nil)
        XCTAssertNil(record.activeDurationSeconds)
        XCTAssertEqual(record.activeDurationText, "—")
    }

    func testCanonicalActivityEngineMatchesSharedGoldenValues() {
        let brisk = GATIVXActivityCalculationEngine.estimate(
            weightKg: 70,
            movingMinutes: 30,
            speedKmh: 5,
            grade: 0,
            cadenceSpm: 112
        )
        XCTAssertEqual(brisk.status, .estimated)
        XCTAssertEqual(brisk.engineVersion, "1.1.2")
        XCTAssertEqual(brisk.met!, 3.38, accuracy: 0.02)
        XCTAssertEqual(brisk.activeCaloriesKcal!, 88, accuracy: 1)
        XCTAssertEqual(brisk.activityPoints, 30)
        XCTAssertEqual(brisk.intensitySource, .metEstimate)
        XCTAssertEqual(brisk.calculationMethod, .speedGradeMET)

        let cadenceOnly = GATIVXActivityCalculationEngine.estimate(
            weightKg: 70,
            movingMinutes: 30,
            speedKmh: nil,
            cadenceSpm: 100
        )
        XCTAssertEqual(cadenceOnly.status, .estimated)
        XCTAssertEqual(cadenceOnly.met!, 3.21, accuracy: 0.02)
        XCTAssertEqual(cadenceOnly.activeCaloriesKcal!, 81.4, accuracy: 1)
        XCTAssertEqual(cadenceOnly.calculationMethod, .cadenceMET)

        let heartRate = GATIVXActivityCalculationEngine.estimate(
            weightKg: 70,
            movingMinutes: 12,
            speedKmh: 5,
            heartRateBpm: 120,
            ageYears: 40
        )
        XCTAssertEqual(heartRate.activityPoints, 12)
        XCTAssertEqual(heartRate.intensitySource, .heartRate)

        let atBoundary = GATIVXActivityCalculationEngine.estimateMET(speedKmh: 6)!
        let belowBoundary = GATIVXActivityCalculationEngine.estimateMET(speedKmh: 5.9999)!
        let aboveBoundary = GATIVXActivityCalculationEngine.estimateMET(speedKmh: 6.0001)!
        XCTAssertEqual(atBoundary, 13.5 / 3.5, accuracy: 0.001)
        XCTAssertEqual(belowBoundary, atBoundary, accuracy: 0.001)
        XCTAssertEqual(aboveBoundary, atBoundary, accuracy: 0.002)

        let unsupported = GATIVXActivityCalculationEngine.estimate(
            weightKg: 70,
            movingMinutes: 30,
            speedKmh: 5,
            activityType: "running"
        )
        XCTAssertEqual(unsupported.status, .insufficientData)
        XCTAssertNil(unsupported.activeCaloriesKcal)

        let missing = GATIVXActivityCalculationEngine.estimate(
            weightKg: 70,
            movingMinutes: 30,
            speedKmh: nil
        )
        XCTAssertEqual(missing.status, .insufficientData)
        XCTAssertNil(missing.activeCaloriesKcal)
    }

    func testCaloriesUseCanonicalFormulaAndRequireMovingTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let latitudeStep = 25.0 / 111_195.0
        let points = (0...40).map { index in
            GATIVXRoutePoint(
                latitude: 15.8500 + Double(index) * latitudeStep,
                longitude: 74.5000,
                timestamp: start.addingTimeInterval(Double(index) * 30),
                horizontalAccuracy: 4,
                breakBefore: index == 0
            )
        }
        let record = ActivitySessionRecord(
            id: UUID(),
            activity: "Walking",
            startedAt: start,
            finishedAt: start.addingTimeInterval(1_200),
            steps: 1_000,
            routePoints: points,
            motionDistanceMeters: nil
        )
        XCTAssertEqual(record.activeDurationSeconds, 1_200)
        XCTAssertEqual(record.estimatedCaloriesKcal(weightKg: 80, heightCm: nil)!, 42, accuracy: 0.5)
        XCTAssertEqual(record.estimatedActivityPoints(weightKg: 80, heightCm: nil), 20)

        let pedometerOnly = ActivitySessionRecord(
            id: UUID(),
            activity: "Walking",
            startedAt: start,
            finishedAt: start.addingTimeInterval(1_200),
            steps: 1_000,
            routePoints: nil,
            motionDistanceMeters: 1_000
        )
        XCTAssertNil(pedometerOnly.estimatedCaloriesKcal(weightKg: 80, heightCm: nil))
        XCTAssertNil(record.estimatedCaloriesKcal(weightKg: 0, heightCm: nil))

        let empty = ActivitySessionRecord(
            id: UUID(),
            activity: "Walking",
            startedAt: start,
            finishedAt: start.addingTimeInterval(60),
            steps: nil,
            routePoints: nil,
            motionDistanceMeters: nil
        )
        XCTAssertNil(empty.estimatedCaloriesKcal(weightKg: 80, heightCm: nil))
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

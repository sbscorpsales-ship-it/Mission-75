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

    @MainActor
    func testDraftAndRouteJournalRecoverAfterReopenAndFinalizeExactlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONDraftTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_800_000_100)
        let store = ActivityStore(databaseURL: databaseURL)
        XCTAssertTrue(store.beginDraft(id: id, startedAt: started))
        XCTAssertTrue(store.updateDraftMetrics(workoutID: id, steps: 240, distanceMeters: 125.5))

        let point = JournalRoutePoint(
            sequence: 1, segment: 0, timestamp: started.addingTimeInterval(30),
            latitude: 15.85, longitude: 74.50, horizontalAccuracy: 4
        )
        XCTAssertTrue(store.appendRoutePoint(workoutID: id, point: point))
        XCTAssertTrue(store.appendRoutePoint(workoutID: id, point: point), "Duplicate sequence retry must be idempotent.")

        let reopened = ActivityStore(databaseURL: databaseURL)
        XCTAssertEqual(reopened.recoverableDrafts.count, 1)
        XCTAssertEqual(reopened.recoverableDrafts.first?.id, id)
        XCTAssertEqual(reopened.recoverableDrafts.first?.routePointCount, 1)
        XCTAssertEqual(try reopened.routePoints(for: id), [point])

        XCTAssertTrue(reopened.finalizeDraft(id, endedAt: started.addingTimeInterval(60)))
        XCTAssertEqual(reopened.sessions.count, 1)
        XCTAssertEqual(reopened.sessions.first?.steps, 240)
        XCTAssertEqual(reopened.sessions.first?.route.count, 1)
        XCTAssertTrue(reopened.recoverableDrafts.isEmpty)
        XCTAssertTrue(reopened.finalizeDraft(id) == false, "Finalization of a missing draft must not create another workout.")
        XCTAssertEqual(reopened.sessions.count, 1)
    }

    func testLegacyWalkPayloadDecodesWithoutRouteSegments() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "startedAt": 1800000000,
          "endedAt": null,
          "steps": 12,
          "distanceMeters": 40.0,
          "route": [{"latitude": 15.85, "longitude": 74.50}]
        }
        """
        let session = try JSONDecoder().decode(WalkSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.id, id)
        XCTAssertNil(session.routeSegments, "Legacy records must remain readable.")
        XCTAssertEqual(session.route.count, 1)
    }

    @MainActor
    func testRouteSequenceRetryRejectsDifferentPayload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONSequenceCollision-\\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_150)
        let store = ActivityStore(databaseURL: databaseURL)
        XCTAssertTrue(store.beginDraft(id: id))
        let original = JournalRoutePoint(sequence: 0, segment: 0, timestamp: timestamp,
            latitude: 15.85, longitude: 74.50, horizontalAccuracy: 4)
        let conflicting = JournalRoutePoint(sequence: 0, segment: 0, timestamp: timestamp,
            latitude: 15.86, longitude: 74.51, horizontalAccuracy: 4)

        XCTAssertTrue(store.appendRoutePoint(workoutID: id, point: original))
        XCTAssertFalse(store.appendRoutePoint(workoutID: id, point: conflicting),
            "A sequence collision with different coordinates must not be accepted as an idempotent retry.")
        XCTAssertEqual(try store.routePoints(for: id), [original])
    }

    @MainActor
    func testFinalizedWalkPreservesSeparateGPSSegments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONSegments-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_800_000_200)
        let store = ActivityStore(databaseURL: databaseURL)
        XCTAssertTrue(store.beginDraft(id: id, startedAt: started))
        let first = JournalRoutePoint(sequence: 0, segment: 0, timestamp: started,
            latitude: 15.85, longitude: 74.50, horizontalAccuracy: 4)
        let second = JournalRoutePoint(sequence: 1, segment: 1, timestamp: started.addingTimeInterval(90),
            latitude: 15.86, longitude: 74.51, horizontalAccuracy: 4)
        XCTAssertTrue(store.appendRoutePoint(workoutID: id, point: first))
        XCTAssertTrue(store.appendRoutePoint(workoutID: id, point: second))
        XCTAssertTrue(store.finalizeDraft(id, endedAt: started.addingTimeInterval(120)))

        let saved = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(saved.route.count, 2)
        XCTAssertEqual(saved.routeSegments?.count, 2)
        XCTAssertEqual(saved.routeSegments?.map(\.count), [1, 1],
            "A GPS gap must remain a discontinuity, not a connecting line.")
    }

    @MainActor
    func testBeginDraftRejectsDuplicateIdentifierWithoutOverwritingOriginal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONDuplicateDraft-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let originalStart = Date(timeIntervalSince1970: 1_800_000_300)
        let store = ActivityStore(databaseURL: databaseURL)
        XCTAssertTrue(store.beginDraft(id: id, startedAt: originalStart))
        XCTAssertTrue(store.updateDraftMetrics(workoutID: id, steps: 42, distanceMeters: 18))
        XCTAssertFalse(store.beginDraft(id: id, startedAt: originalStart.addingTimeInterval(500)))
        XCTAssertEqual(store.recoverableDrafts.count, 1)
        XCTAssertEqual(store.recoverableDrafts.first?.startedAt, originalStart)
        XCTAssertEqual(store.recoverableDrafts.first?.steps, 42)
        XCTAssertEqual(store.recoverableDrafts.first?.distanceMeters, 18)
    }

    @MainActor
    func testRoutePointWriteFailsWhenDraftDoesNotExist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONMissingDraft-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ActivityStore(databaseURL: databaseURL)
        let missingWorkoutID = UUID()
        let point = JournalRoutePoint(
            sequence: 0, segment: 0, timestamp: Date(),
            latitude: 15.85, longitude: 74.50, horizontalAccuracy: 5
        )

        XCTAssertFalse(store.appendRoutePoint(workoutID: missingWorkoutID, point: point))
        XCTAssertTrue(try store.routePoints(for: missingWorkoutID).isEmpty)
        XCTAssertTrue(store.recoverableDrafts.isEmpty)
    }

    @MainActor
    func testDiscardDraftRemovesJournaledRoutePoints() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WALKONDiscardTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("walk-history.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let store = ActivityStore(databaseURL: databaseURL)
        XCTAssertTrue(store.beginDraft(id: id))
        XCTAssertTrue(store.appendRoutePoint(workoutID: id, point: JournalRoutePoint(
            sequence: 0, segment: 0, timestamp: Date(), latitude: 15.85,
            longitude: 74.50, horizontalAccuracy: 5
        )))
        XCTAssertTrue(store.discardDraft(id))
        XCTAssertTrue(store.recoverableDrafts.isEmpty)
        XCTAssertTrue(try store.routePoints(for: id).isEmpty)
    }

}

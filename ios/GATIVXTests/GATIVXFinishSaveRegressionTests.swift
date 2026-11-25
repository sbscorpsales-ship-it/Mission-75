import XCTest
@testable import GATIVX

/// Regression tests for the Finish & Save path.
///
/// The Finish orchestration lives inside a SwiftUI view and HealthKitManager owns a
/// concrete HKHealthStore, so neither can be driven directly from XCTest. These tests
/// cover the pure rules and durable stores those paths depend on.
final class GATIVXFinishSaveRegressionTests: XCTestCase {

    // MARK: - ActivitySessionFinishPolicy

    func testNormalSessionEndsAtCurrentTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(900)

        let finish = ActivitySessionFinishPolicy.effectiveFinishDate(
            now: now,
            startedAt: start,
            lastRoutePointAt: start.addingTimeInterval(300),
            recoveredWithoutResume: false
        )

        XCTAssertEqual(finish, now)
    }

    func testRecoveredSessionSavedWithoutResumeEndsAtLastGPSFix() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let lastFix = start.addingTimeInterval(1_200)
        let now = start.addingTimeInterval(10 * 3_600)

        let finish = ActivitySessionFinishPolicy.effectiveFinishDate(
            now: now,
            startedAt: start,
            lastRoutePointAt: lastFix,
            recoveredWithoutResume: true
        )

        XCTAssertEqual(finish, lastFix)
        XCTAssertEqual(finish.timeIntervalSince(start), 1_200, accuracy: 0.001)
    }

    func testRecoveredSessionWithoutGPSFixFallsBackToCurrentTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(600)

        let finish = ActivitySessionFinishPolicy.effectiveFinishDate(
            now: now,
            startedAt: start,
            lastRoutePointAt: nil,
            recoveredWithoutResume: true
        )

        XCTAssertEqual(finish, now)
    }

    func testRecoveredSessionNeverEndsBeforeItStarted() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(600)

        let finish = ActivitySessionFinishPolicy.effectiveFinishDate(
            now: now,
            startedAt: start,
            lastRoutePointAt: start.addingTimeInterval(-30),
            recoveredWithoutResume: true
        )

        XCTAssertEqual(finish, start)
    }

    func testRecoveredSessionNeverEndsInTheFuture() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = start.addingTimeInterval(600)

        let finish = ActivitySessionFinishPolicy.effectiveFinishDate(
            now: now,
            startedAt: start,
            lastRoutePointAt: now.addingTimeInterval(120),
            recoveredWithoutResume: true
        )

        XCTAssertEqual(finish, now)
    }

    // MARK: - HealthKitWorkoutExportCoalescer

    func testFirstExportRequestOwnsTheExportAndSecondIsParked() {
        var coalescer = HealthKitWorkoutExportCoalescer()
        let id = UUID()

        let firstOwnsExport = coalescer.begin(id: id) { _ in }
        let secondOwnsExport = coalescer.begin(id: id) { _ in }

        XCTAssertTrue(firstOwnsExport)
        XCTAssertFalse(secondOwnsExport)
        XCTAssertTrue(coalescer.isInFlight(id))
    }

    func testFinishReturnsEveryParkedCompletionInArrivalOrderExactlyOnce() {
        var coalescer = HealthKitWorkoutExportCoalescer()
        let id = UUID()
        var calls: [String] = []

        _ = coalescer.begin(id: id) { _ in calls.append("finish") }
        _ = coalescer.begin(id: id) { _ in calls.append("retry") }

        let parked = coalescer.finish(id: id)
        parked.forEach { $0(.success(())) }
        let secondFinish = coalescer.finish(id: id)

        XCTAssertEqual(calls, ["finish", "retry"])
        XCTAssertTrue(secondFinish.isEmpty)
        XCTAssertFalse(coalescer.isInFlight(id))
    }

    func testNewRequestAfterCompletionStartsAFreshExport() {
        var coalescer = HealthKitWorkoutExportCoalescer()
        let id = UUID()

        XCTAssertTrue(coalescer.begin(id: id) { _ in })
        _ = coalescer.finish(id: id)

        // A failed export must remain retryable: the next request owns a new export.
        XCTAssertTrue(coalescer.begin(id: id) { _ in })
    }

    func testDifferentSessionsAreExportedIndependently() {
        var coalescer = HealthKitWorkoutExportCoalescer()
        let first = UUID()
        let second = UUID()

        XCTAssertTrue(coalescer.begin(id: first) { _ in })
        XCTAssertTrue(coalescer.begin(id: second) { _ in })
        _ = coalescer.finish(id: first)

        XCTAssertFalse(coalescer.isInFlight(first))
        XCTAssertTrue(coalescer.isInFlight(second))
    }

    // MARK: - Finish & Save durability invariants

    func testRepeatedFinishOfSameSessionKeepsSingleHistoryRecord() throws {
        let (store, directory, defaults, suiteName) = makeStore()
        defer { cleanUp(directory, defaults: defaults, suiteName: suiteName) }
        let record = makeRecord(ownerID: "account-a")

        var history = store.upserting(record, into: try store.load())
        try store.save(history)
        // A second Finish (or a crash-recovered copy) reuses the same session UUID.
        history = store.upserting(record, into: try store.load())
        try store.save(history)

        let restored = try store.load()
        XCTAssertEqual(restored.map(\.id), [record.id])
    }

    func testLocalSessionSurvivesHealthKitQueueFailureAndExportRemainsRetryable() throws {
        let (history, directory, defaults, suiteName) = makeStore()
        defer { cleanUp(directory, defaults: defaults, suiteName: suiteName) }
        let persistence = ToggleableOutboxPersistence()
        let outbox = HealthKitWorkoutOutboxStore(persistence: persistence)
        let record = makeRecord(ownerID: nil)
        let pending = PendingHealthWorkout(
            id: record.id,
            activity: record.activity,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            steps: record.steps,
            distanceMeters: record.motionDistanceMeters
        )

        try history.save(history.upserting(record, into: try history.load()))

        // The Apple Health queue cannot be written; the local activity must be unaffected.
        persistence.rejectWrites = true
        XCTAssertThrowsError(try outbox.enqueue(pending))
        XCTAssertEqual(try history.load().map(\.id), [record.id])

        // Once the queue can be written again the same session UUID can be exported and acknowledged.
        persistence.rejectWrites = false
        XCTAssertEqual(try outbox.enqueue(pending).map(\.id), [record.id])
        XCTAssertEqual(try outbox.enqueue(pending).map(\.id), [record.id])
        XCTAssertTrue(try outbox.acknowledge(record.id).isEmpty)
        XCTAssertEqual(try history.load().map(\.id), [record.id])
    }

    func testSavedSessionIsRestoredByAFreshStoreAfterRelaunch() throws {
        let (beforeRelaunch, directory, defaults, suiteName) = makeStore()
        defer { cleanUp(directory, defaults: defaults, suiteName: suiteName) }
        let record = makeRecord(ownerID: "account-a")

        try beforeRelaunch.save([record])

        // A new store instance over the same directory models a cold launch.
        let afterRelaunch = ActivitySessionStore(userDefaults: defaults, directoryOverride: directory)
        let restored = try afterRelaunch.load()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, record.id)
        XCTAssertEqual(restored.first?.ownerID, "account-a")
        XCTAssertEqual(restored.first?.steps, 321)
        XCTAssertEqual(restored.first?.durationText, record.durationText)
    }

    // MARK: - Helpers

    private func makeStore() -> (ActivitySessionStore, URL, UserDefaults, String) {
        let suiteName = "GATIVXFinishSaveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let store = ActivitySessionStore(userDefaults: defaults, directoryOverride: directory)
        return (store, directory, defaults, suiteName)
    }

    private func cleanUp(_ directory: URL, defaults: UserDefaults, suiteName: String) {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeRecord(ownerID: String?) -> ActivitySessionRecord {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return ActivitySessionRecord(
            id: UUID(),
            activity: "Walking",
            startedAt: start,
            finishedAt: start.addingTimeInterval(600),
            steps: 321,
            routePoints: nil,
            motionDistanceMeters: 250,
            ownerID: ownerID
        )
    }
}

private final class ToggleableOutboxPersistence: HealthKitWorkoutOutboxPersistence {
    private var values: [String: Data] = [:]
    var rejectWrites = false

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func setData(_ data: Data, forKey key: String) {
        if rejectWrites { return }
        values[key] = data
    }
}

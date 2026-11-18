import XCTest
@testable import GATIVX

final class HealthKitWorkoutOutboxStoreTests: XCTestCase {
    func testEnqueueIsIdempotentByStableWorkoutID() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let workout = makeWorkout()

        XCTAssertEqual(try store.enqueue(workout).count, 1)
        XCTAssertEqual(try store.enqueue(workout).count, 1)
        XCTAssertEqual(try store.load().map(\.id), [workout.id])
    }

    func testAcknowledgeRemovesOnlyTheConfirmedWorkout() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = makeWorkout()
        let second = makeWorkout()
        _ = try store.enqueue(first)
        _ = try store.enqueue(second)

        let remaining = try store.acknowledge(first.id)

        XCTAssertEqual(remaining.map(\.id), [second.id])
        XCTAssertEqual(try store.load().map(\.id), [second.id])
    }

    func testCorruptOutboxIsPreservedAndCannotBeReplacedByEnqueue() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "gativx.healthkit.workout-export-outbox.v1"
        let corrupt = Data("preserve-original-healthkit-queue".utf8)
        defaults.set(corrupt, forKey: key)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.enqueue(makeWorkout()))
        XCTAssertThrowsError(try store.acknowledge(UUID()))
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
    }

    func testOutboxRoundTripPreservesUnavailableStepsAndMeasuredDistance() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let workout = makeWorkout(steps: nil, distanceMeters: 842.5)

        _ = try store.enqueue(workout)
        let restored = try XCTUnwrap(store.load().first)

        XCTAssertEqual(restored.id, workout.id)
        XCTAssertNil(restored.steps)
        XCTAssertEqual(try XCTUnwrap(restored.distanceMeters), 842.5, accuracy: 0.001)
        XCTAssertEqual(restored.activity, "Walking")
    }

    private func makeStore() -> (HealthKitWorkoutOutboxStore, UserDefaults, String) {
        let suite = "GATIVXHealthKitOutboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (HealthKitWorkoutOutboxStore(userDefaults: defaults), defaults, suite)
    }

    private func makeWorkout(steps: Int? = 123, distanceMeters: Double? = 900) -> PendingHealthWorkout {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return PendingHealthWorkout(
            id: UUID(),
            activity: "Walking",
            startedAt: start,
            finishedAt: start.addingTimeInterval(600),
            steps: steps,
            distanceMeters: distanceMeters
        )
    }
}

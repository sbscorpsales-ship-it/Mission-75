import XCTest
@testable import GATIVX

final class HealthSyncOutboxStoreTests: XCTestCase {
    func testEnqueueReplacesOnlyTheSameMemberKindAndLocalDay() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = makeItem(ownerID: "member-a", kind: .healthSteps, steps: 100, queuedAt: Date(timeIntervalSince1970: 100))
        let newer = makeItem(ownerID: "member-a", kind: .healthSteps, steps: 250, queuedAt: Date(timeIntervalSince1970: 200))
        let otherMember = makeItem(ownerID: "member-b", kind: .healthSteps, steps: 75)
        let motionSource = makeItem(ownerID: "member-a", kind: .motionSteps, steps: 90)

        _ = try store.enqueue(first)
        _ = try store.enqueue(newer)
        _ = try store.enqueue(otherMember)
        _ = try store.enqueue(motionSource)

        let restored = try store.load()
        XCTAssertEqual(restored.count, 3)
        XCTAssertEqual(restored.first(where: { $0.id == newer.id })?.revisionID, newer.revisionID)
        XCTAssertEqual(restored.first(where: { $0.id == newer.id })?.steps, 250)
        XCTAssertTrue(restored.contains(where: { $0.id == otherMember.id }))
        XCTAssertTrue(restored.contains(where: { $0.id == motionSource.id }))
    }

    func testAcknowledgingAnOlderRevisionCannotDeleteANewerReading() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let older = makeItem(ownerID: "member-a", kind: .healthSteps, steps: 100)
        let newer = makeItem(ownerID: "member-a", kind: .healthSteps, steps: 400)
        _ = try store.enqueue(older)
        _ = try store.enqueue(newer)

        let remaining = try store.acknowledge(older)

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.revisionID, newer.revisionID)
        XCTAssertEqual(remaining.first?.steps, 400)
    }

    func testOutboxRoundTripPreservesMeasuredValuesAndQueuedOwner() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = makeItem(
            ownerID: "member-verified",
            kind: .motionSteps,
            steps: 1_245,
            distanceMeters: 875.5
        )

        _ = try store.enqueue(item)
        let restored = try XCTUnwrap(store.load().first)

        XCTAssertEqual(restored.ownerID, "member-verified")
        XCTAssertEqual(restored.revisionID, item.revisionID)
        XCTAssertEqual(restored.steps, 1_245)
        XCTAssertEqual(try XCTUnwrap(restored.distanceMeters), 875.5, accuracy: 0.001)
        XCTAssertEqual(restored.localDay, item.localDay)
    }

    func testCorruptOutboxIsPreservedAndBlocksEnqueueAndAcknowledgement() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "com.paramitsolutions.gativx.health-sync-outbox.v1"
        let corrupt = Data("preserve-original-sensor-queue".utf8)
        defaults.set(corrupt, forKey: key)
        let item = makeItem(ownerID: "member-a", kind: .healthSteps, steps: 10)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.enqueue(item))
        XCTAssertThrowsError(try store.acknowledge(item))
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
    }

    func testAcknowledgingMemberAReadingDoesNotRemoveMemberBReadingForSameDay() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let memberA = makeItem(ownerID: "member-a", kind: .healthSteps, steps: 500)
        let memberB = makeItem(ownerID: "member-b", kind: .healthSteps, steps: 800)
        _ = try store.enqueue(memberA)
        _ = try store.enqueue(memberB)

        let remaining = try store.acknowledge(memberA)

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.ownerID, "member-b")
        XCTAssertEqual(remaining.first?.steps, 800)
        XCTAssertEqual(try store.load().map(\.ownerID), ["member-b"])
    }

    private func makeStore() -> (HealthSyncOutboxStore, UserDefaults, String) {
        let suite = "GATIVXHealthSyncOutboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            HealthSyncOutboxStore(
                userDefaults: defaults,
                key: "com.paramitsolutions.gativx.health-sync-outbox.v1"
            ),
            defaults,
            suite
        )
    }

    private func makeItem(
        ownerID: String,
        kind: PendingHealthSyncKind,
        steps: Int?,
        distanceMeters: Double? = nil,
        queuedAt: Date = Date()
    ) -> PendingHealthSync {
        PendingHealthSync(
            ownerID: ownerID,
            revisionID: UUID(),
            kind: kind,
            localDay: "2026-11-19",
            steps: steps,
            activeEnergyKcal: nil,
            distanceMeters: distanceMeters,
            queuedAt: queuedAt
        )
    }
    func testLocalDayParserRejectsImpossibleCalendarDates() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertNil(HealthSyncOutboxStore.dateForLocalDay("2026-02-30", timeZone: utc))
        XCTAssertNil(HealthSyncOutboxStore.dateForLocalDay("2026-13-01", timeZone: utc))
        XCTAssertNil(HealthSyncOutboxStore.dateForLocalDay("2026-2-03", timeZone: utc))
        XCTAssertNil(HealthSyncOutboxStore.dateForLocalDay("2026-11-00", timeZone: utc))
    }

    func testLocalDayParserPreservesValidGregorianDate() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let date = HealthSyncOutboxStore.dateForLocalDay("2026-11-19", timeZone: utc)
        XCTAssertNotNil(date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 19)
    }

}

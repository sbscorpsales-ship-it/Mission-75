import XCTest
@testable import GATIVX

final class RunJeetBackupImporterTests: XCTestCase {
    private let importer = RunJeetBackupImporter()

    func testImportsRunJeetSchemaOneWithoutInventingZeroStepsOrGPS() throws {
        let data = Data("""
        {
          "app": "RunJeet",
          "schema": 1,
          "state": {
            "stepsByDay": {},
            "sessions": [{
              "id": "c79090d9-9753-4fab-8183-426f2ceec150",
              "startedAt": 1794985731513,
              "endedAt": 1794985743724,
              "durationSec": 12,
              "distanceM": 0,
              "points": [],
              "sessionSteps": 0
            }]
          }
        }
        """.utf8)

        let result = try importer.decode(data)

        XCTAssertEqual(result.activities.count, 1)
        XCTAssertEqual(result.activities[0].id.uuidString.lowercased(), "c79090d9-9753-4fab-8183-426f2ceec150")
        XCTAssertEqual(result.activities[0].durationText, "0:12")
        XCTAssertNil(result.activities[0].steps)
        XCTAssertNil(result.activities[0].routePoints)
        XCTAssertNil(result.activities[0].motionDistanceMeters)
        XCTAssertTrue(result.dailyStepsByDay.isEmpty)
    }

    func testImportsValidDailyTotalsAndGPSPoints() throws {
        let data = Data("""
        {
          "app": "RunJeet",
          "schema": 1,
          "state": {
            "stepsByDay": {"2026-11-18": 1234},
            "sessions": [{
              "id": "c79090d9-9753-4fab-8183-426f2ceec150",
              "startedAt": 1794985731513,
              "endedAt": 1794985743724,
              "durationSec": 12,
              "distanceM": 15.5,
              "points": [{
                "lat": 15.85,
                "lon": 74.5,
                "accuracy": 5,
                "ts": 1794985732000
              }],
              "sessionSteps": 42
            }]
          }
        }
        """.utf8)

        let result = try importer.decode(data)

        XCTAssertEqual(result.dailyStepsByDay["2026-11-18"], 1234)
        XCTAssertEqual(result.activities[0].steps, 42)
        XCTAssertEqual(result.activities[0].routePoints?.count, 1)
        XCTAssertEqual(result.activities[0].motionDistanceMeters, 15.5)
    }

    func testImportedRecordsReceiveAccountOwnershipOnlyWhenExplicitlySelected() throws {
        let data = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513,"endedAt":1794985743724,
          "durationSec":12,"distanceM":0,"points":[],"sessionSteps":0
        }]}}
        """.utf8)
        let imported = try importer.decode(data).activities

        let localOnly = importer.assigningOwnerID(nil, to: imported)
        let accountOwned = importer.assigningOwnerID("account-42", to: imported)

        XCTAssertNil(localOnly[0].ownerID)
        XCTAssertEqual(accountOwned[0].ownerID, "account-42")
        XCTAssertEqual(accountOwned[0].id, imported[0].id)
    }

    func testRejectsBooleanDistanceAndNegativeSessionSteps() {
        let booleanDistance = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513,"endedAt":1794985743724,
          "durationSec":12,"distanceM":true,"points":[],"sessionSteps":0
        }]}}
        """.utf8)
        let negativeSteps = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513,"endedAt":1794985743724,
          "durationSec":12,"distanceM":0,"points":[],"sessionSteps":-1
        }]}}
        """.utf8)
        let malformedSteps = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513,"endedAt":1794985743724,
          "durationSec":12,"distanceM":0,"points":[],"sessionSteps":true
        }]}}
        """.utf8)

        XCTAssertThrowsError(try importer.decode(booleanDistance))
        XCTAssertThrowsError(try importer.decode(negativeSteps))
        XCTAssertThrowsError(try importer.decode(malformedSteps))
    }

    func testRejectsFractionalOutOfRangeAndOverlongSessionTimestamps() {
        let fractionalTimestamp = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513.5,"endedAt":1794985743724,
          "durationSec":12,"distanceM":0,"points":[],"sessionSteps":0
        }]}}
        """.utf8)
        let outOfRangeTimestamp = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":99999999999999,"endedAt":99999999999999,
          "durationSec":0,"distanceM":0,"points":[],"sessionSteps":0
        }]}}
        """.utf8)
        let overlongSession = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513,"endedAt":1795072131513,
          "durationSec":86401,"distanceM":0,"points":[],"sessionSteps":0
        }]}}
        """.utf8)

        XCTAssertThrowsError(try importer.decode(fractionalTimestamp))
        XCTAssertThrowsError(try importer.decode(outOfRangeTimestamp))
        XCTAssertThrowsError(try importer.decode(overlongSession))
    }

    func testRejectsUnreasonableAndOverflowingStepCounts() {
        let excessiveDailySteps = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{"2026-11-18":1000001},"sessions":[]}}
        """.utf8)
        let overflowingDailySteps = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{"2026-11-18":9223372036854775808},"sessions":[]}}
        """.utf8)
        let excessiveSessionSteps = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{},"sessions":[{
          "id":"c79090d9-9753-4fab-8183-426f2ceec150",
          "startedAt":1794985731513,"endedAt":1794985743724,
          "durationSec":12,"distanceM":0,"points":[],"sessionSteps":200001
        }]}}
        """.utf8)

        XCTAssertThrowsError(try importer.decode(excessiveDailySteps))
        XCTAssertThrowsError(try importer.decode(overflowingDailySteps))
        XCTAssertThrowsError(try importer.decode(excessiveSessionSteps))
    }

    func testDuplicateImportDoesNotDuplicateExistingActivity() throws {
        let data = Data("""
        {
          "app": "RunJeet", "schema": 1,
          "state": {"stepsByDay": {}, "sessions": [{
            "id": "c79090d9-9753-4fab-8183-426f2ceec150",
            "startedAt": 1794985731513, "endedAt": 1794985743724,
            "durationSec": 12, "distanceM": 0, "points": [], "sessionSteps": 0
          }]}
        }
        """.utf8)
        let imported = try importer.decode(data).activities
        let existing = imported

        XCTAssertEqual(importer.merging(imported, into: existing).count, 1)
    }

    func testRejectsWrongAppAndInvalidStepDay() {
        let wrongApp = Data("""
        {"app":"Other","schema":1,"state":{"stepsByDay":{},"sessions":[]}}
        """.utf8)
        let booleanSchema = Data("""
        {"app":"RunJeet","schema":true,"state":{"stepsByDay":{},"sessions":[]}}
        """.utf8)
        XCTAssertThrowsError(try importer.decode(wrongApp))
        XCTAssertThrowsError(try importer.decode(booleanSchema))

        let invalidDay = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{"2026-02-30":12},"sessions":[]}}
        """.utf8)
        XCTAssertThrowsError(try importer.decode(invalidDay))
    }
}


final class RunJeetDailyStepsArchiveStoreTests: XCTestCase {
    func testMergeIsIdempotentAndExistingDatesWin() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXRunJeetArchiveTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunJeetDailyStepsArchiveStore(directoryOverride: directory)

        let first = try store.merge(["2026-11-18": 1234])
        XCTAssertEqual(first.addedDays, 1)
        XCTAssertEqual(first.preservedExistingDays, 0)
        XCTAssertEqual(try store.load(), ["2026-11-18": 1234])

        let second = try store.merge([
            "2026-11-18": 9999,
            "2026-11-19": 2000
        ])
        XCTAssertEqual(second.addedDays, 1)
        XCTAssertEqual(second.preservedExistingDays, 1)
        XCTAssertEqual(second.totalDays, 2)
        XCTAssertEqual(try store.load(), [
            "2026-11-18": 1234,
            "2026-11-19": 2000
        ])

        let repeated = try store.merge(["2026-11-18": 1234, "2026-11-19": 2000])
        XCTAssertEqual(repeated.addedDays, 0)
        XCTAssertEqual(repeated.preservedExistingDays, 2)
        XCTAssertEqual(try store.load().count, 2)
    }

    func testCorruptArchiveIsPreservedAndNeverTreatedAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXRunJeetArchiveCorrupt.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("runjeet-daily-steps-archive.json")
        let corrupt = Data("keep-original-archive".utf8)
        try corrupt.write(to: file)
        let store = RunJeetDailyStepsArchiveStore(directoryOverride: directory)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.merge(["2026-11-18": 100]))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testInvalidDailyTotalsAreRejectedBeforeArchiveCreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GATIVXRunJeetArchiveInvalid.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RunJeetDailyStepsArchiveStore(directoryOverride: directory)

        XCTAssertThrowsError(try store.merge(["2026-02-30": 100]))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("runjeet-daily-steps-archive.json").path
        ))
    }
}

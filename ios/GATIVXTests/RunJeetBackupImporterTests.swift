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
        XCTAssertThrowsError(try importer.decode(wrongApp))

        let invalidDay = Data("""
        {"app":"RunJeet","schema":1,"state":{"stepsByDay":{"2026-02-30":12},"sessions":[]}}
        """.utf8)
        XCTAssertThrowsError(try importer.decode(invalidDay))
    }
}

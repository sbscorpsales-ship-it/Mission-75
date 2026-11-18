import XCTest

final class GATIVXDashboardUITests: XCTestCase {
    func testDashboardSectionsMetricsAndPrimaryNavigation() {
        let app = XCUIApplication()
        app.launch()

        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10), "The app should launch directly into the Home dashboard.")

        let approvedLabels = [
            "TODAY'S STEPS",
            "TODAY'S MISSION",
            "TODAY'S ACTIVITY",
            "ACTIVITY TRACKER",
            "START WALK",
            "GATI GURU",
            "MY JOURNEY",
            "COMMUNITY GATI"
        ]
        for label in approvedLabels {
            XCTAssertTrue(app.staticTexts[label].firstMatch.exists, "Missing approved dashboard content: \(label)")
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GATIVX-Home-Dashboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let metricIdentifiers = [
            "gativx-metric-distance",
            "gativx-metric-active-time",
            "gativx-metric-calories",
            "gativx-metric-average-heart-rate"
        ]
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<4 {
            if metricIdentifiers.allSatisfy({ app.descendants(matching: .any)[$0].exists }) {
                break
            }
            if scrollView.exists {
                scrollView.swipeUp()
            }
        }
        for identifier in metricIdentifiers {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                "Missing approved dashboard metric: \(identifier)"
            )
        }

        let notifications = app.buttons["Notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        for _ in 0..<4 where !notifications.isHittable {
            scrollView.swipeDown()
        }
        XCTAssertTrue(notifications.isHittable, "The dashboard header should remain reachable after scrolling.")
        notifications.tap()
        XCTAssertTrue(app.staticTexts["You're all caught up"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GATIVX notifications are not active in this build yet. Your walking records and health data are unaffected."].exists)
        app.buttons["Done"].tap()

        let guruEntry = app.buttons["gativx-guru-entry"]
        XCTAssertTrue(guruEntry.waitForExistence(timeout: 5))
        for _ in 0..<6 where !guruEntry.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(guruEntry.isHittable, "The GATIVX Guru entry should remain reachable from Home.")
        guruEntry.tap()
        XCTAssertTrue(app.staticTexts["YOUR GOAL JOURNEY"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gativx-journey-duration"].exists)
        XCTAssertTrue(app.staticTexts["ONE PRACTICAL NEXT ACTION"].exists)
        app.buttons["Done"].tap()

        let activityTab = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))

        let communityTab = app.tabBars.buttons["Community"]
        XCTAssertTrue(communityTab.exists)
        communityTab.tap()
        XCTAssertTrue(app.staticTexts["NOT ACTIVE IN THIS BUILD"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Community feed and shared missions are not available yet. Your personal activity remains private and is not shared with other members."].exists)

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.exists)
        profileTab.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }
}

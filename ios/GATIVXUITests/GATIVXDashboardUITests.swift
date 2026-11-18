import XCTest

final class GATIVXDashboardUITests: XCTestCase {
    func testHomeDashboardLaunchesWithApprovedSections() {
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

        for metric in ["Distance", "Active time", "Calories", "Avg. heart rate"] {
            XCTAssertTrue(app.staticTexts[metric].firstMatch.exists, "Missing dashboard metric: \(metric)")
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "GATIVX-Home-Dashboard"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNotificationBellOpensNotificationsSheet() {
        let app = XCUIApplication()
        app.launch()

        let notifications = app.buttons["Notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 10))
        notifications.tap()

        XCTAssertTrue(app.staticTexts["You're all caught up"].waitForExistence(timeout: 5))
    }

    func testBottomNavigationCanOpenActivityAndProfile() {
        let app = XCUIApplication()
        app.launch()

        let activityTab = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activityTab.waitForExistence(timeout: 10))
        activityTab.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.exists)
        profileTab.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
    }
}

import XCTest

final class GATIVXDashboardUITests: XCTestCase {
    /// Use short deterministic drags so lazy dashboard sections are not skipped
    /// by a full-screen swipe before XCTest can query their accessibility nodes.
    private func scrollTowardBottom(_ scrollView: XCUIElement) {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.76))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func scrollTowardTop(_ scrollView: XCUIElement) {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.46))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

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

        let scrollView = app.scrollViews["gativx-home-dashboard"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))

        // The metrics are in a LazyVGrid. Advance in short increments and query
        // after every drag, rather than allowing a full-screen swipe to skip a row.
        let distanceMetric = app.descendants(matching: .any)["gativx-metric-distance"].firstMatch
        let activeTimeMetric = app.descendants(matching: .any)["gativx-metric-active-time"].firstMatch
        for _ in 0..<20 {
            if distanceMetric.exists && activeTimeMetric.exists { break }
            scrollTowardBottom(scrollView)
        }
        XCTAssertTrue(distanceMetric.waitForExistence(timeout: 2), "Missing approved dashboard metric: distance")
        XCTAssertTrue(activeTimeMetric.waitForExistence(timeout: 2), "Missing approved dashboard metric: active time")

        let caloriesMetric = app.descendants(matching: .any)["gativx-metric-calories"].firstMatch
        let averageHeartRateMetric = app.descendants(matching: .any)["gativx-metric-average-heart-rate"].firstMatch
        for _ in 0..<20 {
            if caloriesMetric.exists && averageHeartRateMetric.exists { break }
            scrollTowardBottom(scrollView)
        }
        XCTAssertTrue(caloriesMetric.waitForExistence(timeout: 2), "Missing approved dashboard metric: calories")
        XCTAssertTrue(averageHeartRateMetric.waitForExistence(timeout: 2), "Missing approved dashboard metric: average heart rate")

        let notifications = app.buttons["Notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        for _ in 0..<20 where !notifications.isHittable {
            scrollTowardTop(scrollView)
        }
        XCTAssertTrue(notifications.isHittable, "The dashboard header should remain reachable after scrolling.")
        notifications.tap()
        XCTAssertTrue(app.staticTexts["Notifications aren't active yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gativx-notifications-gated"].exists)
        app.buttons["Done"].tap()

        let guruEntry = app.buttons["gativx-guru-entry"]
        XCTAssertTrue(guruEntry.waitForExistence(timeout: 5))
        for _ in 0..<20 where !guruEntry.isHittable {
            scrollTowardBottom(scrollView)
        }
        XCTAssertTrue(guruEntry.isHittable, "The GATIVX Guru entry should remain reachable from Home.")
        guruEntry.tap()
        XCTAssertTrue(app.staticTexts["YOUR GOAL JOURNEY"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["gativx-journey-duration"].exists)
        XCTAssertTrue(app.staticTexts["ONE PRACTICAL NEXT ACTION"].exists)

        let guruScrollViews = app.scrollViews
        XCTAssertGreaterThan(guruScrollViews.count, 0, "The Guru sheet should expose its scrollable form.")
        let guruScrollView = guruScrollViews.element(boundBy: guruScrollViews.count - 1)
        let goalField = app.textFields["What do you want to achieve?"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 5))
        goalField.tap()
        goalField.typeText("Walk consistently")

        // Dismiss the multiline goal editor using Guru's explicit keyboard toolbar action.
        let keyboardDone = app.buttons["gativx-guru-keyboard-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        keyboardDone.tap()
        let keyboard = app.keyboards.firstMatch
        let keyboardDismissed = NSPredicate(format: "exists == false")
        expectation(for: keyboardDismissed, evaluatedWith: keyboard)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(keyboard.exists, "The keyboard should be dismissed before using the Guru journey controls.")

        let durationPicker = app.segmentedControls["gativx-journey-duration"]
        XCTAssertTrue(durationPicker.waitForExistence(timeout: 5))
        let oneEightyDays = durationPicker.buttons["180 days"]
        XCTAssertTrue(oneEightyDays.waitForExistence(timeout: 5))
        oneEightyDays.tap() // XCTest scrolls the control into view if required.

        let startJourney = app.buttons["gativx-start-journey"]
        XCTAssertTrue(startJourney.waitForExistence(timeout: 5))
        startJourney.tap() // XCTest scrolls the start action into view if required.
        XCTAssertTrue(app.staticTexts["DAY 1 OF 180"].waitForExistence(timeout: 5))
        durationPicker.buttons["30 days"].tap()

        XCTAssertTrue(app.staticTexts["DAY 1 OF 180"].exists, "Changing the next selection must not change the active 180-day journey.")
        XCTAssertFalse(app.staticTexts["DAY 1 OF 30"].exists)
        app.buttons["gativx-guru-close"].tap()

        let activityTab = app.tabBars.buttons["Activity"]
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))

        let communityTab = app.tabBars.buttons["Community"]
        XCTAssertTrue(communityTab.exists)
        communityTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["gativx-community-gated"].waitForExistence(timeout: 5))

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected, "Selecting Profile should switch the active tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-profile-screen"].waitForExistence(timeout: 5), "The Profile form should be visible after selecting its tab.")
    }
}
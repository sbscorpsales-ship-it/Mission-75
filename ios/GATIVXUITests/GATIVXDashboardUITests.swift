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

        XCTAssertTrue(app.staticTexts["CREATE YOUR GATIVX ACCOUNT"].waitForExistence(timeout: 10),
                      "First launch must show registration/sign-in before the member dashboard.")
        XCTAssertTrue(app.textFields["gativx-email-field"].exists)
        XCTAssertTrue(app.secureTextFields["gativx-password-field"].exists)
        let authModeToggle = app.buttons["gativx-auth-mode-toggle"]
        XCTAssertTrue(authModeToggle.exists)
        authModeToggle.tap()
        XCTAssertTrue(app.staticTexts["WELCOME BACK TO GATIVX"].waitForExistence(timeout: 5),
                      "Existing members must have a real sign-in form.")
        XCTAssertTrue(app.buttons["Forgot password?"].exists,
                      "Existing members must be able to start password recovery.")
        authModeToggle.tap()
        XCTAssertTrue(app.staticTexts["CREATE YOUR GATIVX ACCOUNT"].exists)
        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.exists, "Local-only access must be an explicit choice.")
        guestEntry.tap()

        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10), "The Home dashboard should appear after an explicit entry choice.")
        let appWindow = app.windows.firstMatch
        XCTAssertTrue(appWindow.waitForExistence(timeout: 5), "The app window must be measurable for device-bound layout checks.")
        let dashboardHeader = app.descendants(matching: .any)["gativx-dashboard-header"].firstMatch
        XCTAssertTrue(dashboardHeader.exists, "The dashboard header must expose a measurable layout container.")
        XCTAssertGreaterThan(dashboardHeader.frame.width, appWindow.frame.width * 0.9,
                             "The header must use the available device width instead of expanding beyond it.")
        XCTAssertLessThanOrEqual(dashboardHeader.frame.maxX, appWindow.frame.maxX + 1,
                                 "The header must not be clipped off the right edge.")
        let notificationControl = app.buttons["gativx-header-notifications"]
        let profileControl = app.buttons["gativx-header-profile"]
        XCTAssertTrue(notificationControl.exists, "The notification control must remain visible in the header.")
        XCTAssertTrue(profileControl.exists, "The member profile control must remain visible in the header.")
        XCTAssertGreaterThanOrEqual(notificationControl.frame.minX, appWindow.frame.minX - 1)
        XCTAssertLessThanOrEqual(notificationControl.frame.maxX, appWindow.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(profileControl.frame.minX, appWindow.frame.minX - 1)
        XCTAssertLessThanOrEqual(profileControl.frame.maxX, appWindow.frame.maxX + 1,
                                 "The member profile control must not be clipped at the right edge.")

        let dashboardIdentity = app.staticTexts["gativx-dashboard-member-identity"]
        XCTAssertTrue(dashboardIdentity.exists)
        XCTAssertEqual(dashboardIdentity.label, "LOCAL-ONLY MEMBER",
                       "A guest dashboard must clearly identify its local-only account state.")

        // Catch the compressed/overlapping mission-card defect from the member screenshot.
        let missionCard = app.descendants(matching: .any)["gativx-todays-mission"].firstMatch
        XCTAssertTrue(missionCard.waitForExistence(timeout: 5), "Today's mission must render as a real dashboard card.")
        XCTAssertGreaterThan(missionCard.frame.width, appWindow.frame.width * 0.82,
                             "Today's mission card must use the available dashboard width.")
        XCTAssertGreaterThan(missionCard.frame.height, 90,
                             "Today's mission card must retain enough height for readable content.")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        if missionCard.isHittable {
            XCTAssertLessThanOrEqual(missionCard.frame.maxY, tabBar.frame.minY + 1,
                                     "The visible mission card must not be covered by bottom navigation.")
        }

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
        let goalField = app.textFields["gativx-guru-goal"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 5))
        // The intro card sits above the goal form on a phone-sized sheet. Scroll
        // the Guru form itself until the first input is inside the visible viewport.
        for _ in 0..<12 where !goalField.isHittable {
            scrollTowardBottom(guruScrollView)
        }
        XCTAssertTrue(goalField.isHittable, "The Guru goal field must be scrolled into view before editing.")
        goalField.tap()
        let inputKeyboard = app.keyboards.firstMatch
        XCTAssertTrue(inputKeyboard.waitForExistence(timeout: 5),
                      "Tapping the Guru goal field must focus it and open text input.")
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
        XCTAssertTrue(app.staticTexts["ACTIVITY TRACKER"].waitForExistence(timeout: 5), "Selecting Activity should show the Activity Tracker screen.")

        let communityTab = app.tabBars.buttons["Community"]
        XCTAssertTrue(communityTab.exists)
        communityTab.tap()
        XCTAssertTrue(app.descendants(matching: .any)["gativx-community-gated"].waitForExistence(timeout: 5))

        let profileTab = app.tabBars.buttons["Profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected, "Selecting Profile should switch the active tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-profile-screen"].waitForExistence(timeout: 5), "The Profile form should be visible after selecting its tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-member-login-id"].exists,
                      "Profile must show the current member identity or explicit local-only status.")
    }
}
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

    private func launchFreshGuestApp(_ app: XCUIApplication) {
        // UserDefaults persist between XCTest methods on the same simulator.
        // Force the local-only entry flag off so every test starts at Welcome,
        // independent of a guest choice made by an earlier test run.
        app.launchArguments += ["-gativx-ui-test-reset-local-mode"]
        app.launch()
    }

    private func tabButton(_ app: XCUIApplication, label: String) -> XCUIElement {
        // SwiftUI exposes tab items as Buttons whose identifiers can be SF
        // Symbols (for example "figure.walk"), not the visible tab title.
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func testDashboardSectionsMetricsAndPrimaryNavigation() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        XCTAssertTrue(app.staticTexts["CREATE YOUR GATIVX ACCOUNT"].waitForExistence(timeout: 10),
                      "First launch must show registration/sign-in before the member dashboard.")
        XCTAssertTrue(app.textFields["gativx-email-field"].exists)
        XCTAssertTrue(app.secureTextFields["gativx-password-field"].exists)
        let authModeToggle = app.buttons["gativx-auth-mode-toggle"]
        XCTAssertTrue(authModeToggle.exists)
        authModeToggle.tap()
        XCTAssertTrue(app.staticTexts["WELCOME BACK TO GATIVX"].waitForExistence(timeout: 5),
                      "Existing members must have a real sign-in form.")
        let forgotPassword = app.buttons["gativx-forgot-password"]
        XCTAssertTrue(forgotPassword.waitForExistence(timeout: 5),
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
        XCTAssertLessThanOrEqual(profileControl.frame.maxX, appWindow.frame.maxX - 6,
                                 "The member profile control must retain a visible trailing inset.")

        let homeTab = tabButton(app, label: "Home")
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(homeTab.isSelected, "The Home tab must be selected after member entry.")

        let dashboardIdentity = app.staticTexts["gativx-dashboard-member-identity"]
        XCTAssertTrue(dashboardIdentity.exists)
        XCTAssertEqual(dashboardIdentity.label, "LOCAL-ONLY MEMBER",
                       "A guest dashboard must clearly identify its local-only account state.")

        let calorieRing = app.descendants(matching: .any)["gativx-ring-active-calories"].firstMatch
        XCTAssertTrue(calorieRing.waitForExistence(timeout: 5),
                      "Home must render the Active Calories progress ring.")
        XCTAssertEqual(calorieRing.label, "Active Calories progress")
        let heartPointsRing = app.descendants(matching: .any)["gativx-ring-heart-points"].firstMatch
        XCTAssertTrue(heartPointsRing.waitForExistence(timeout: 5),
                      "Home must render the Heart Points progress ring.")
        XCTAssertEqual(heartPointsRing.label, "Heart Points progress")

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
        let keyboardDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: keyboard
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [keyboardDismissed], timeout: 10),
            .completed,
            "The Guru Done action must dismiss the keyboard before journey navigation."
        )
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

        // A tab bar button can remain queryable behind a sheet while its
        // dismissal animation is still running. Never tap through the modal:
        // wait until Guru has actually left the accessibility hierarchy first.
        let guruCloseButton = app.buttons["gativx-guru-close"]
        let guruSheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: guruCloseButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [guruSheetDismissed], timeout: 10),
            .completed,
            "Closing Guru must finish dismissing its sheet before switching tabs."
        )
        XCTAssertFalse(guruCloseButton.exists, "The Guru sheet must be gone before Activity navigation.")

        let activityTab = tabButton(app, label: "Activity")
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()
        XCTAssertTrue(activityTab.isSelected, "Selecting Activity must change the active tab.")
        let activityScreen = app.scrollViews["gativx-activity-screen"]
        XCTAssertTrue(activityScreen.waitForExistence(timeout: 10),
                      "Selecting Activity must render its own screen rather than leave the Home dashboard visible.")
        XCTAssertTrue(app.staticTexts["ACTIVITY TRACKER"].waitForExistence(timeout: 5),
                      "The Activity screen must show the Activity Tracker controls.")

        // Verify the direct Guru action dismisses its sheet before opening Activity.
        homeTab.tap()
        for _ in 0..<20 where !guruEntry.isHittable {
            scrollTowardBottom(scrollView)
        }
        XCTAssertTrue(guruEntry.isHittable, "Guru must remain reachable after returning Home.")
        guruEntry.tap()
        let guruStartWalk = app.buttons["gativx-guru-start-walk"]
        let guruActionScrollView = app.scrollViews.element(boundBy: app.scrollViews.count - 1)
        XCTAssertTrue(guruActionScrollView.waitForExistence(timeout: 5))
        for _ in 0..<20 where !guruStartWalk.isHittable {
            scrollTowardBottom(guruActionScrollView)
        }
        XCTAssertTrue(guruStartWalk.isHittable, "Guru must expose its direct Start a walk action.")
        guruStartWalk.tap()
        let guruStartWalkDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: guruStartWalk
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [guruStartWalkDismissed], timeout: 10),
            .completed,
            "Guru's Start a walk action must dismiss the sheet before Activity is presented."
        )
        XCTAssertTrue(activityTab.isSelected, "Guru's Start a walk action must select Activity.")
        XCTAssertTrue(activityScreen.waitForExistence(timeout: 10),
                      "Guru's Start a walk action must open the Activity screen.")

        let missionsTab = tabButton(app, label: "Missions")
        XCTAssertTrue(missionsTab.waitForExistence(timeout: 5))
        missionsTab.tap()
        XCTAssertTrue(missionsTab.isSelected, "Selecting Missions must change the active tab.")
        let missionsScreen = app.scrollViews["gativx-missions-screen"]
        XCTAssertTrue(missionsScreen.waitForExistence(timeout: 10),
                      "Selecting Missions must render its own screen.")
        XCTAssertTrue(app.staticTexts["TODAY · CONSISTENCY"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Begin walking mission"].exists)

        let communityTab = tabButton(app, label: "Community")
        XCTAssertTrue(communityTab.waitForExistence(timeout: 5))
        communityTab.tap()
        XCTAssertTrue(communityTab.isSelected, "Selecting Community must change the active tab.")
        XCTAssertTrue(
            app.descendants(matching: .any)["gativx-community-screen"].firstMatch.waitForExistence(timeout: 10),
            "The gated Community tab must render without blocking the app after Activity navigation."
        )
        XCTAssertTrue(app.descendants(matching: .any)["gativx-community-gated"].waitForExistence(timeout: 5))

        let profileTab = tabButton(app, label: "Profile")
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected, "Selecting Profile should switch the active tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-profile-screen"].waitForExistence(timeout: 5), "The Profile form should be visible after selecting its tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-member-login-id"].exists,
                      "Profile must show the current member identity or explicit local-only status.")
    }

    func testHomeStartWalkNavigatesWithoutStartingSession() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["gativx-home-dashboard"].waitForExistence(timeout: 10),
            "Explicit guest entry must display the Home dashboard before its actions are queried."
        )
        let homeStart = app.buttons["gativx-start-walk"]
        XCTAssertTrue(homeStart.waitForExistence(timeout: 5))
        homeStart.tap()

        let activityTab = tabButton(app, label: "Activity")
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        XCTAssertTrue(activityTab.isSelected,
                      "Home START WALK must navigate to Activity.")
        XCTAssertTrue(app.scrollViews["gativx-activity-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start Walk"].waitForExistence(timeout: 5),
                      "The Activity screen must present the explicit start action.")
        XCTAssertFalse(app.buttons["Finish & save activity"].exists,
                       "Navigating from Home must not silently start GPS or pedometer recording.")
    }

}
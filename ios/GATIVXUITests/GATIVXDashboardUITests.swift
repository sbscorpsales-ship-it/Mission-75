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

    private func launchFreshGuestApp(_ app: XCUIApplication, additionalArguments: [String] = []) {
        // UserDefaults persist between XCTest methods on the same simulator.
        // Force the local-only entry flag off so every test starts at Welcome,
        // independent of a guest choice made by an earlier test run.
        app.launchArguments += ["-gativx-ui-test-reset-local-mode"] + additionalArguments
        app.launch()
    }

    private func tabButton(_ app: XCUIApplication, label: String) -> XCUIElement {
        app.buttons["gativx-tab-\(label.lowercased())"]
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

        // XCTest reports the ScrollView's backing accessibility frame, not its
        // clipped viewport, so comparing that frame directly with the dock is invalid.
        // Prove both an early dashboard card and the final Home card can be scrolled
        // fully above the dock. This verifies content reachability, not clip geometry.
        let scrollView = app.scrollViews["gativx-home-dashboard"]
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5),
                      "Home must expose its scrollable dashboard viewport.")
        let missionCard = app.descendants(matching: .any)["gativx-todays-mission"].firstMatch
        XCTAssertTrue(missionCard.waitForExistence(timeout: 5), "Today's mission must render as a real dashboard card.")
        XCTAssertGreaterThan(missionCard.frame.width, appWindow.frame.width * 0.82,
                             "Today's mission card must use the available dashboard width.")
        XCTAssertGreaterThan(missionCard.frame.height, 90,
                             "Today's mission card must retain enough height for readable content.")
        let bottomNavigation = app.descendants(matching: .any)["gativx-bottom-navigation"].firstMatch
        XCTAssertTrue(bottomNavigation.waitForExistence(timeout: 10))
        XCTAssertTrue(bottomNavigation.isHittable, "The fixed dock must remain reachable while Home is selected.")
        // XCTest exposes a SwiftUI ScrollView's backing accessibility frame, which
        // can include the safe-area region occupied by safeAreaInset. Validate the
        // actual visible content against the dock after scrolling instead of
        // treating that backing frame as the clipped viewport.
        XCTAssertTrue(scrollView.isHittable, "The Home dashboard scroll viewport must remain interactive.")
        XCTAssertTrue(missionCard.isHittable, "Today's mission card must remain reachable from the dashboard.")
        for _ in 0..<12 where missionCard.frame.maxY > bottomNavigation.frame.minY + 1 {
            scrollTowardBottom(scrollView)
        }
        XCTAssertTrue(missionCard.isHittable, "The mission card must remain reachable after scrolling.")
        XCTAssertLessThanOrEqual(missionCard.frame.maxY, bottomNavigation.frame.minY + 1,
                                 "The mission card must be fully scrollable above the persistent dock.")

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

        // The dashboard scroll view was validated above before scrolling to lower sections.

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

        // The final Home card must also be reachable above the fixed dock. This
        // catches bottom-content clipping that a middle-card assertion can miss.
        let communityCard = app.buttons["gativx-community-gati-card"]
        for _ in 0..<24 where !communityCard.isHittable {
            scrollTowardBottom(scrollView)
        }
        XCTAssertTrue(communityCard.waitForExistence(timeout: 5),
                      "The final Community Gati card must remain part of the Home dashboard.")
        XCTAssertTrue(communityCard.isHittable,
                      "The final Home card must be reachable without interacting through the dock.")
        for _ in 0..<12 where communityCard.frame.maxY > bottomNavigation.frame.minY + 1 {
            scrollTowardBottom(scrollView)
        }
        XCTAssertLessThanOrEqual(communityCard.frame.maxY, bottomNavigation.frame.minY + 1,
                                 "The final Home card must be fully scrollable above the persistent dock.")

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
        XCTAssertTrue(app.staticTexts["GATIVX GURU"].exists)
        XCTAssertTrue(app.staticTexts["NURUN · YOUR PERSONAL GUIDE"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gativx-guru-today-signals"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gativx-guru-walking"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gativx-guru-nutrition"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gativx-guru-recovery"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gativx-guru-learning"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["gativx-journey-duration"].exists)

        let guruScrollView = app.scrollViews["gativx-guru-fullscreen"]
        XCTAssertTrue(guruScrollView.waitForExistence(timeout: 5),
                      "Guru must open as a full-screen scrollable coaching experience.")
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(guruScrollView.frame.width, window.frame.width * 0.95,
                             "Guru must use the full iPhone width.")
        XCTAssertGreaterThan(guruScrollView.frame.height, window.frame.height * 0.80,
                             "Guru must occupy the full usable iPhone viewport, not a half-height sheet.")
        XCTAssertLessThanOrEqual(guruScrollView.frame.minY, window.frame.minY + 75,
                                 "Guru must start at the top safe area, without a large blank band.")
        XCTAssertGreaterThanOrEqual(guruScrollView.frame.maxY, window.frame.maxY - 100,
                                     "Guru must extend to the bottom safe area.")

        let walkingCheckIn = app.buttons["gativx-guru-walking-checkin"]
        for _ in 0..<20 where !walkingCheckIn.isHittable { scrollTowardBottom(guruScrollView) }
        XCTAssertTrue(walkingCheckIn.isHittable)
        if !walkingCheckIn.label.localizedCaseInsensitiveContains("checked") {
            walkingCheckIn.tap()
        }
        XCTAssertTrue(walkingCheckIn.label.localizedCaseInsensitiveContains("checked"),
                      "The walking habit check-in must visibly save today's completion.")

        let nutritionCheckIn = app.buttons["gativx-guru-nutrition-checkin"]
        for _ in 0..<20 where !nutritionCheckIn.isHittable { scrollTowardBottom(guruScrollView) }
        XCTAssertTrue(nutritionCheckIn.isHittable)
        if !nutritionCheckIn.label.localizedCaseInsensitiveContains("checked") {
            nutritionCheckIn.tap()
        }
        XCTAssertTrue(nutritionCheckIn.label.localizedCaseInsensitiveContains("checked"),
                      "The nutrition habit check-in must visibly save today's completion.")

        let recoveryPicker = app.segmentedControls["gativx-guru-recovery-feeling"]
        for _ in 0..<20 where !recoveryPicker.isHittable { scrollTowardBottom(guruScrollView) }
        XCTAssertTrue(recoveryPicker.isHittable)
        recoveryPicker.buttons["Tired"].tap()
        let recoverySave = app.buttons["gativx-guru-recovery-save"]
        for _ in 0..<10 where !recoverySave.isHittable { scrollTowardBottom(guruScrollView) }
        XCTAssertTrue(recoverySave.isHittable)
        if !recoverySave.label.localizedCaseInsensitiveContains("saved") {
            recoverySave.tap()
        }
        XCTAssertTrue(recoverySave.label.localizedCaseInsensitiveContains("saved"),
                      "The recovery check-in must visibly save today's selection.")

        let goalField = app.textFields["gativx-guru-goal"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 5))
        let guruCloseButton = app.buttons["gativx-guru-close"]
        XCTAssertTrue(guruCloseButton.waitForExistence(timeout: 5),
                      "Guru's navigation control must be present before checking goal-field hit testing.")
        // Goal setup appears above the walking, nutrition and recovery cards. Scroll back
        // until it is both hittable and below the fixed Guru navigation control; hittability
        // alone can be true while a scrolled field is partly covered by the navigation bar.
        for _ in 0..<12 where !goalField.isHittable || goalField.frame.minY < guruCloseButton.frame.maxY + 8 {
            scrollTowardTop(guruScrollView)
        }
        XCTAssertTrue(goalField.isHittable, "The Guru goal field must be scrolled into view before editing.")
        XCTAssertGreaterThanOrEqual(goalField.frame.minY, guruCloseButton.frame.maxY + 8,
                                    "The Guru goal field must be clear of the fixed navigation control before tapping.")
        let goalFieldScreenshot = XCTAttachment(screenshot: app.screenshot())
        goalFieldScreenshot.name = "GATIVX-Guru-Goal-Field-Before-Tap"
        goalFieldScreenshot.lifetime = .keepAlways
        add(goalFieldScreenshot)
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
        let guruSheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: guruCloseButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [guruSheetDismissed], timeout: 10),
            .completed,
            "Closing Guru must finish dismissing its full-screen experience before switching tabs."
        )
        XCTAssertFalse(guruCloseButton.exists, "The Guru full-screen experience must be gone before Activity navigation.")

        let activityTab = app.descendants(matching: .any)["gativx-tab-activity"].firstMatch
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

        let communityTab = app.descendants(matching: .any)["gativx-tab-community"].firstMatch
        XCTAssertTrue(communityTab.waitForExistence(timeout: 5))
        communityTab.tap()
        XCTAssertTrue(communityTab.isSelected, "Selecting Community must change the active tab.")
        XCTAssertTrue(
            app.descendants(matching: .any)["gativx-community-screen"].firstMatch.waitForExistence(timeout: 10),
            "The gated Community tab must render without blocking the app after Activity navigation."
        )
        XCTAssertTrue(app.descendants(matching: .any)["gativx-community-gated"].waitForExistence(timeout: 5))

        let profileTab = app.descendants(matching: .any)["gativx-tab-profile"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected, "Selecting Profile should switch the active tab.")
        let profileScreen = app.descendants(matching: .any)["gativx-profile-screen"].firstMatch
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 5), "The Profile form should be visible after selecting its tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-member-login-id"].exists,
                      "Profile must show the current member identity or explicit local-only status.")

        // PhotosUI is intentionally created only after the member asks to change
        // their photo; simply opening Profile must not initialize the picker.
        let openPhotoPicker = app.buttons["gativx-profile-photo-picker-open"]
        XCTAssertTrue(openPhotoPicker.waitForExistence(timeout: 5))
        openPhotoPicker.tap()
        XCTAssertTrue(app.staticTexts["gativx-profile-photo-picker-sheet"].waitForExistence(timeout: 5),
                      "The on-demand member-photo sheet should appear.")
        let cancelPhotoPicker = app.buttons["gativx-profile-photo-picker-cancel"]
        XCTAssertTrue(cancelPhotoPicker.waitForExistence(timeout: 5))
        cancelPhotoPicker.tap()
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 5),
                      "Cancelling the member-photo sheet should return to Profile.")
    }

    func testCommunityTabAfterMissionsFromFreshDashboard() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let homeDashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(homeDashboard.waitForExistence(timeout: 10),
                      "Choosing local-only access must transition from Welcome to the member dashboard.")

        let bottomNavigation = app.descendants(matching: .any)["gativx-bottom-navigation"].firstMatch
        XCTAssertTrue(bottomNavigation.waitForExistence(timeout: 5))

        let missionsTab = tabButton(app, label: "Missions")
        XCTAssertTrue(missionsTab.waitForExistence(timeout: 5))
        missionsTab.tap()
        XCTAssertTrue(missionsTab.isSelected, "Missions must become the selected tab.")
        XCTAssertTrue(app.scrollViews["gativx-missions-screen"].waitForExistence(timeout: 10))

        let communityTab = tabButton(app, label: "Community")
        XCTAssertTrue(communityTab.waitForExistence(timeout: 5))
        communityTab.tap()
        XCTAssertTrue(communityTab.isSelected, "Community must become the selected tab after Missions.")
        let communityScreen = app.descendants(matching: .any)["gativx-community-screen"].firstMatch
        XCTAssertTrue(communityScreen.waitForExistence(timeout: 10),
                      "Community must render after leaving the Missions tab.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-community-gated"].waitForExistence(timeout: 5))
    }

    func testLocalOnlyEntryPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10),
                      "Local-only entry must open the member dashboard.")
        XCTAssertTrue(app.buttons["gativx-tab-home"].waitForExistence(timeout: 5))

        app.terminate()
        // Remove the one-shot UI-test reset argument so the persisted guest choice
        // is evaluated exactly as it would be on a normal subsequent app launch.
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["gativx-home-dashboard"].waitForExistence(timeout: 10),
                      "The explicit local-only choice must survive an app relaunch.")
        XCTAssertTrue(app.buttons["gativx-tab-home"].waitForExistence(timeout: 5))
        app.buttons["gativx-tab-profile"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["gativx-member-login-id"].waitForExistence(timeout: 5),
                      "Profile must identify the member as local-only after relaunch.")
    }

    func testFinishSavePersistsAndRecoversActivityHistory() {
        let app = XCUIApplication()
        launchFreshGuestApp(app, additionalArguments: ["-gativx-ui-test-simulated-walk"])

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let activityTab = tabButton(app, label: "Activity")
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()
        XCTAssertTrue(app.scrollViews["gativx-activity-screen"].waitForExistence(timeout: 10))

        let startWalk = app.buttons["Start Walk"]
        XCTAssertTrue(startWalk.waitForExistence(timeout: 5))
        startWalk.tap()

        let finishSave = app.buttons["Finish & save activity"]
        XCTAssertTrue(finishSave.waitForExistence(timeout: 5),
                      "Starting a walk must expose the explicit Finish & save action.")
        finishSave.tap()

        let savedRowID = "gativx-saved-activity-00000000-0000-4000-8000-000000000123"
        let savedRow = app.descendants(matching: .any)[savedRowID].firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 15),
                      "Finish & Save must write a local history row before reporting success.")
        XCTAssertTrue(savedRow.label.contains("Walking"),
                      "The saved history row must retain the selected activity type.")
        XCTAssertTrue(savedRow.label.contains("123"),
                      "The saved history row must retain the deterministic DEBUG test step reading.")

        // Relaunch the app to prove the row is read back from durable local history,
        // not merely retained in ContentView state.
        app.terminate()
        app.launch()

        let relaunchedGuestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(relaunchedGuestEntry.waitForExistence(timeout: 10))
        relaunchedGuestEntry.tap()
        let relaunchedActivityTab = tabButton(app, label: "Activity")
        XCTAssertTrue(relaunchedActivityTab.waitForExistence(timeout: 5))
        relaunchedActivityTab.tap()

        let recoveredRow = app.descendants(matching: .any)[savedRowID].firstMatch
        XCTAssertTrue(recoveredRow.waitForExistence(timeout: 15),
                      "A saved activity must remain visible after terminating and relaunching GATIVX.")
        XCTAssertTrue(recoveredRow.label.contains("Walking"))
        XCTAssertTrue(recoveredRow.label.contains("123"))
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

        let activityTab = app.descendants(matching: .any)["gativx-tab-activity"].firstMatch
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        XCTAssertTrue(activityTab.isSelected,
                      "Home START WALK must navigate to Activity.")
        XCTAssertTrue(app.scrollViews["gativx-activity-screen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Start Walk"].waitForExistence(timeout: 5),
                      "The Activity screen must present the explicit start action.")
        XCTAssertFalse(app.buttons["Finish & save activity"].exists,
                       "Navigating from Home must not silently start GPS or pedometer recording.")
    }

    func testProfileTabRendersFromFreshDashboard() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10),
                      "The Home dashboard must render before testing direct Profile navigation.")

        let profileTab = app.descendants(matching: .any)["gativx-tab-profile"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5),
                      "The Profile tab must expose its stable accessibility identifier.")
        XCTAssertFalse(profileTab.isSelected, "Home must remain selected before Profile is tapped.")
        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected, "A direct Profile tap must select the Profile tab.")

        let profileScreen = app.descendants(matching: .any)["gativx-profile-screen"].firstMatch
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 10),
                      "Profile must render when opened directly from a fresh dashboard.")
        XCTAssertTrue(app.descendants(matching: .any)["gativx-member-login-id"].waitForExistence(timeout: 5),
                      "Profile must identify the local-only member.")

        // The photo picker sheet belongs to the root member shell, not the Profile
        // navigation subtree. Verify it opens and dismisses from the Profile screen.
        let photoPickerOpen = app.buttons["gativx-profile-photo-picker-open"]
        XCTAssertTrue(photoPickerOpen.waitForExistence(timeout: 5))
        photoPickerOpen.tap()
        let photoPickerSheet = app.staticTexts["gativx-profile-photo-picker-sheet"]
        XCTAssertTrue(photoPickerSheet.waitForExistence(timeout: 5),
                      "The root-hosted member photo sheet must open from Profile.")
        XCTAssertTrue(app.buttons["gativx-profile-photo-picker"].waitForExistence(timeout: 5),
                      "The photo library entry point must be present in the sheet.")
        app.buttons["gativx-profile-photo-picker-cancel"].tap()
        let photoSheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: photoPickerSheet
        )
        XCTAssertEqual(XCTWaiter.wait(for: [photoSheetDismissed], timeout: 5), .completed,
                       "Cancelling the root-hosted photo sheet must return to Profile.")
        XCTAssertTrue(profileScreen.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GATIVX-Profile-Direct-From-Home"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }


    func testProfileAboutSectionRemainsReachableAboveFixedBottomNavigation() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let profileTab = tabButton(app, label: "Profile")
        XCTAssertTrue(profileTab.waitForExistence(timeout: 5))
        profileTab.tap()
        XCTAssertTrue(profileTab.isSelected)

        let profileScreen = app.descendants(matching: .any)["gativx-profile-screen"].firstMatch
        XCTAssertTrue(profileScreen.waitForExistence(timeout: 10),
                      "Profile must render before checking its final section.")

        let bottomNavigation = app.descendants(matching: .any)["gativx-bottom-navigation"].firstMatch
        XCTAssertTrue(bottomNavigation.waitForExistence(timeout: 5))

        let aboutText = app.staticTexts["From Goals to Xcellence"]
        // SwiftUI Form rows are lazy: the final About section may not enter the
        // accessibility tree until the Profile form is scrolled down to it.
        for _ in 0..<20 where !aboutText.exists {
            profileScreen.swipeUp()
        }
        XCTAssertTrue(aboutText.waitForExistence(timeout: 5),
                      "The final About GATIVX content must exist after scrolling to the end of Profile.")
        XCTAssertTrue(aboutText.isHittable,
                      "The final Profile content must be scroll-reachable above the fixed dock.")
        XCTAssertLessThanOrEqual(aboutText.frame.maxY, bottomNavigation.frame.minY + 1,
                                 "The final Profile content must not sit underneath the fixed navigation dock.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GATIVX-Profile-Final-Section-Above-Dock"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAllFiveTabsSwitchScreensFromOneNavigationDock() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let destinations: [(String, String)] = [
            ("Home", "gativx-home-dashboard"),
            ("Activity", "gativx-activity-screen"),
            ("Missions", "gativx-missions-screen"),
            ("Community", "gativx-community-screen"),
            ("Profile", "gativx-profile-screen")
        ]

        for (label, screenIdentifier) in destinations {
            let tab = tabButton(app, label: label)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "The \(label) destination must be present.")
            tab.tap()
            XCTAssertTrue(tab.isSelected, "The \(label) destination must become selected.")
            XCTAssertTrue(
                app.descendants(matching: .any)[screenIdentifier].firstMatch.waitForExistence(timeout: 8),
                "Selecting \(label) must render its own screen."
            )
        }
    }

    func testNotificationsSheetDismissesFromFreshHome() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        let notifications = app.buttons["gativx-header-notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()

        let message = app.staticTexts["Notifications aren't active yet"]
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["gativx-notifications-gated"].exists)
        app.buttons["Done"].tap()

        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: message
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: 10),
            .completed,
            "The Notifications sheet must fully dismiss before the Home dashboard is reused."
        )
        XCTAssertTrue(dashboard.exists, "Dismissing Notifications must return to the same Home dashboard.")
    }

    func testGuruKeyboardAndDismissalFromFreshHome() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        let homeScroll = app.scrollViews["gativx-home-dashboard"]
        XCTAssertTrue(homeScroll.waitForExistence(timeout: 5))

        let guruEntry = app.buttons["gativx-guru-entry"]
        XCTAssertTrue(guruEntry.waitForExistence(timeout: 5))
        for _ in 0..<20 where !guruEntry.isHittable {
            scrollTowardBottom(homeScroll)
        }
        XCTAssertTrue(guruEntry.isHittable, "Guru must be reachable from a fresh Home dashboard.")
        guruEntry.tap()

        let guruScrollViews = app.scrollViews
        XCTAssertGreaterThan(guruScrollViews.count, 0)
        let guruScroll = guruScrollViews.element(boundBy: guruScrollViews.count - 1)
        let goalField = app.textFields["gativx-guru-goal"]
        XCTAssertTrue(goalField.waitForExistence(timeout: 10))
        for _ in 0..<12 where !goalField.isHittable {
            scrollTowardBottom(guruScroll)
        }
        XCTAssertTrue(goalField.isHittable, "The Guru goal field must be visible before keyboard interaction.")
        goalField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10),
                      "Tapping the Guru goal field must present the keyboard.")
        goalField.typeText("Walk consistently")

        let keyboardDone = app.buttons["gativx-guru-keyboard-done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 10))
        keyboardDone.tap()
        let keyboardDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: keyboard
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [keyboardDismissed], timeout: 10),
            .completed,
            "Guru's keyboard toolbar action must dismiss the keyboard."
        )

        let close = app.buttons["gativx-guru-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let sheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: close
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [sheetDismissed], timeout: 10),
            .completed,
            "Closing Guru must remove the sheet before returning to Home."
        )
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))

        // The same focus state used to dismiss the Guru keyboard must leave
        // the dashboard responsive when the member switches tabs afterwards.
        let activityTab = app.descendants(matching: .any)["gativx-tab-activity"].firstMatch
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()
        XCTAssertTrue(activityTab.isSelected, "Activity must remain selectable after dismissing the Guru keyboard and sheet.")
        XCTAssertTrue(
            app.scrollViews["gativx-activity-screen"].waitForExistence(timeout: 10),
            "Activity must render after Guru has relinquished text-field focus."
        )
    }



    func testActivityScreenFillsViewportAboveFixedBottomNavigation() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10))
        guestEntry.tap()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let homeDashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(
            homeDashboard.waitForExistence(timeout: 10),
            "Guest entry must finish presenting the member dashboard before dock geometry is inspected."
        )
        let homeTab = tabButton(app, label: "Home")
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        XCTAssertTrue(homeTab.isSelected, "Home must be selected before switching to Activity.")
        let bottomNavigation = app.descendants(matching: .any)["gativx-bottom-navigation"].firstMatch
        XCTAssertTrue(bottomNavigation.waitForExistence(timeout: 10))
        XCTAssertTrue(bottomNavigation.isHittable, "The persistent dock must be reachable after guest entry.")

        let activityTab = tabButton(app, label: "Activity")
        XCTAssertTrue(activityTab.waitForExistence(timeout: 5))
        activityTab.tap()
        XCTAssertTrue(activityTab.isSelected)

        let activityScreen = app.scrollViews["gativx-activity-screen"]
        XCTAssertTrue(activityScreen.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(activityScreen.frame.width, window.frame.width * 0.95,
                             "Activity must use the full device width.")
        XCTAssertGreaterThan(activityScreen.frame.height, window.frame.height * 0.70,
                             "Activity must fill the usable viewport instead of appearing as a middle strip.")
        XCTAssertLessThanOrEqual(activityScreen.frame.minY, window.frame.minY + 70,
                                 "Activity must begin near the top safe area.")
        XCTAssertGreaterThanOrEqual(activityScreen.frame.maxY, bottomNavigation.frame.minY - 1,
                                     "Activity content must extend to the fixed bottom dock.")
        XCTAssertTrue(bottomNavigation.isHittable,
                      "The fixed bottom navigation must remain available over the full Activity screen.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GATIVX-Activity-Full-Viewport-Fixed-Navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDashboardFillsDeviceViewportAndExposesAllFiveTabs() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10),
                      "The explicit local-only entry must be available before testing the member shell.")
        guestEntry.tap()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5),
                      "The iPhone app window must be measurable for viewport acceptance.")

        // Capture the physical simulator display, not only the app's accessibility window.
        // This catches a reduced/letterboxed app window that could otherwise pass viewport
        // assertions measured only against app.windows.firstMatch.
        let deviceScreenScreenshot = XCUIScreen.main.screenshot()
        let deviceScreenSize = deviceScreenScreenshot.image.size
        let deviceScreenAttachment = XCTAttachment(screenshot: deviceScreenScreenshot)
        deviceScreenAttachment.name = "GATIVX-Full-Device-Screen"
        deviceScreenAttachment.lifetime = .keepAlways
        add(deviceScreenAttachment)
        XCTAssertGreaterThan(deviceScreenSize.height, deviceScreenSize.width * 1.8,
                             "The device capture must be portrait and represent the full iPhone display.")
        XCTAssertGreaterThanOrEqual(window.frame.width, deviceScreenSize.width * 0.98,
                                     "The app window must span the physical device width.")
        XCTAssertGreaterThanOrEqual(window.frame.height, deviceScreenSize.height * 0.95,
                                     "The app window must fill the physical device height, not a reduced window.")
        XCTAssertLessThanOrEqual(window.frame.minY, 8,
                                  "The app window must begin at the top of the physical device display.")
        let dashboard = app.descendants(matching: .any)["gativx-home-dashboard"].firstMatch
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10),
                      "Member entry must render the full Home dashboard.")

        let bottomNavigation = app.descendants(matching: .any)["gativx-bottom-navigation"].firstMatch
        XCTAssertTrue(bottomNavigation.waitForExistence(timeout: 5),
                      "The fixed full-width five-tab navigation must be visible after member entry.")

        XCTAssertGreaterThan(dashboard.frame.width, window.frame.width * 0.95,
                             "Home must occupy nearly the full available iPhone width.")
        XCTAssertGreaterThan(dashboard.frame.height, window.frame.height * 0.74,
                             "Home must fill the usable viewport; a narrow middle strip is not acceptable.")
        XCTAssertLessThanOrEqual(dashboard.frame.minY, window.frame.minY + 70,
                                 "Home content must begin near the top safe area, not below a large blank band.")
        XCTAssertGreaterThanOrEqual(dashboard.frame.minX, window.frame.minX - 1)
        XCTAssertLessThanOrEqual(dashboard.frame.maxX, window.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(dashboard.frame.maxY, bottomNavigation.frame.minY - 1,
                                     "Home content must extend to the fixed bottom navigation.")
        XCTAssertGreaterThan(bottomNavigation.frame.width, window.frame.width * 0.98,
                             "Bottom navigation must span the full device width.")
        XCTAssertGreaterThanOrEqual(bottomNavigation.frame.maxY, window.frame.maxY - 90,
                                     "Bottom navigation must be attached to the device bottom safe area.")
        XCTAssertLessThanOrEqual(bottomNavigation.frame.height, 76,
                                 "Bottom navigation must use a compact fixed-height dock.")
        let allTabButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "gativx-tab-"))
        XCTAssertEqual(allTabButtons.count, 5,
                       "Home, Activity, Missions, Community and Profile must all be present together.")

        for label in ["Home", "Activity", "Missions", "Community", "Profile"] {
            let tab = tabButton(app, label: label)
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing bottom navigation tab: \\(label)")
            XCTAssertTrue(tab.isHittable, "The \\(label) tab must be visible and tappable.")
            XCTAssertGreaterThanOrEqual(tab.frame.minX, window.frame.minX - 1)
            XCTAssertLessThanOrEqual(tab.frame.maxX, window.frame.maxX + 1)
        }

        // The dashboard is a vertical surface with fixed bottom tabs, not a horizontally
        // paging carousel. A left/right swipe must not switch the selected destination.
        let homeTab = tabButton(app, label: "Home")
        dashboard.swipeLeft()
        XCTAssertTrue(homeTab.isSelected, "A left swipe must not move the dashboard sideways to another tab.")
        dashboard.swipeRight()
        XCTAssertTrue(homeTab.isSelected, "A right swipe must not move the dashboard sideways to another tab.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "GATIVX-Full-Viewport-Five-Tabs"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testWelcomeScreenFillsDeviceViewportBeforeGuestEntry() {
        let app = XCUIApplication()
        launchFreshGuestApp(app)

        let guestEntry = app.buttons["gativx-continue-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 10),
                      "The first-run Welcome screen must render before measuring the device viewport.")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5),
                      "The Welcome screen must be hosted in a measurable iPhone window.")
        let deviceScreenScreenshot = XCUIScreen.main.screenshot()
        let deviceScreenSize = deviceScreenScreenshot.image.size
        let attachment = XCTAttachment(screenshot: deviceScreenScreenshot)
        attachment.name = "GATIVX-Welcome-Full-Device-Screen"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThanOrEqual(window.frame.width, deviceScreenSize.width * 0.98,
                                    "The first-run Welcome screen must span the physical iPhone width.")
        XCTAssertGreaterThanOrEqual(window.frame.height, deviceScreenSize.height * 0.95,
                                    "The first-run Welcome screen must fill the physical iPhone height.")
        XCTAssertLessThanOrEqual(window.frame.minY, 8,
                                 "The first-run Welcome screen must begin at the top of the device display.")
    }

}

import XCTest
@testable import GATIVX

final class GATIVXGoalJourneyTests: XCTestCase {
    func testJourneyCalculatesElapsedDaysRemainingAndProgress() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let now = calendar.date(byAdding: .day, value: 7, to: start)!
        let journey = GATIVXGoalJourney(durationDays: 30, startedAt: start, now: now)

        XCTAssertEqual(journey.elapsedDays, 7)
        XCTAssertEqual(journey.daysRemaining, 23)
        XCTAssertEqual(journey.progress, 7.0 / 30.0, accuracy: 0.0001)
        XCTAssertFalse(journey.isComplete)
        XCTAssertTrue(journey.checkpointMessage.contains("Weekly checkpoint"))
    }

    func testJourneyCompletionNeverExceedsOneHundredPercent() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let now = calendar.date(byAdding: .day, value: 40, to: start)!
        let journey = GATIVXGoalJourney(durationDays: 30, startedAt: start, now: now)

        XCTAssertEqual(journey.daysRemaining, 0)
        XCTAssertEqual(journey.progress, 1)
        XCTAssertTrue(journey.isComplete)
        XCTAssertTrue(journey.checkpointMessage.contains("Journey complete"))
    }

    func testGuruGuidesMemberThroughGoalPurposeAndEmotionInOrder() {
        XCTAssertEqual(
            GATIVXGuruCoach.suggestedNextAction(
                goal: "", purpose: "", emotion: "", dailySteps: nil, dailyStepGoal: 10_000
            ),
            "Write one clear outcome you want to achieve."
        )
        XCTAssertEqual(
            GATIVXGuruCoach.suggestedNextAction(
                goal: "Walk daily", purpose: "", emotion: "", dailySteps: nil, dailyStepGoal: 10_000
            ),
            "Write one personal reason this goal matters to you."
        )
        XCTAssertEqual(
            GATIVXGuruCoach.suggestedNextAction(
                goal: "Walk daily", purpose: "Be active with family", emotion: "", dailySteps: nil, dailyStepGoal: 10_000
            ),
            "Name how you want to feel when you reach your goal."
        )
    }

    func testGuruSuggestsSmallActionWhenStepReadingIsUnavailable() {
        let action = GATIVXGuruCoach.suggestedNextAction(
            goal: "Walk daily",
            purpose: "Have energy for my family",
            emotion: "Confident",
            dailySteps: nil,
            dailyStepGoal: 10_000
        )

        XCTAssertTrue(action.contains("5-minute walk"))
        XCTAssertTrue(action.contains("measured step reading"))
    }

    func testGuruAdaptsNextActionToRemainingDailySteps() {
        let common = ["goal": "Walk daily", "purpose": "Be active", "emotion": "Confident"]
        let almostThere = GATIVXGuruCoach.suggestedNextAction(
            goal: common["goal"]!, purpose: common["purpose"]!, emotion: common["emotion"]!,
            dailySteps: 9_700, dailyStepGoal: 10_000
        )
        let halfway = GATIVXGuruCoach.suggestedNextAction(
            goal: common["goal"]!, purpose: common["purpose"]!, emotion: common["emotion"]!,
            dailySteps: 8_500, dailyStepGoal: 10_000
        )
        let reached = GATIVXGuruCoach.suggestedNextAction(
            goal: common["goal"]!, purpose: common["purpose"]!, emotion: common["emotion"]!,
            dailySteps: 10_500, dailyStepGoal: 10_000
        )

        XCTAssertTrue(almostThere.contains("remaining 300 steps"))
        XCTAssertTrue(halfway.contains("10-minute walk"))
        XCTAssertTrue(reached.contains("reached today's step target"))
    }

    func testPurposeAnchorUsesOnlyMemberProvidedContext() {
        let anchor = GATIVXGuruCoach.purposeAnchor(
            goal: "Walk every day",
            purpose: "Keep up with my family",
            emotion: "Energetic"
        )

        XCTAssertTrue(anchor.contains("Walk every day"))
        XCTAssertTrue(anchor.contains("Keep up with my family"))
        XCTAssertTrue(anchor.contains("Energetic"))
    }
}

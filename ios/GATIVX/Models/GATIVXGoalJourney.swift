import Foundation

/// A locally persisted, calendar-day goal journey used by GATIVX Guru.
struct GATIVXGoalJourney {
    let durationDays: Int
    let startedAt: Date
    let now: Date

    var elapsedDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startedAt)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    var daysRemaining: Int {
        max(0, max(1, durationDays) - elapsedDays)
    }

    var progress: Double {
        min(Double(elapsedDays) / Double(max(1, durationDays)), 1)
    }

    var isComplete: Bool {
        elapsedDays >= max(1, durationDays)
    }

    var checkpointMessage: String {
        if isComplete {
            return "Journey complete. Reflect on what changed, celebrate consistency, and choose your next cycle."
        }
        if elapsedDays == 0 {
            return "Day 1 starts with one small action. Make it easy enough to repeat tomorrow."
        }
        if elapsedDays.isMultiple(of: 7) {
            return "Weekly checkpoint: notice what is working, remove one obstacle, and keep the next action realistic."
        }
        return "Keep showing up. A small repeatable action is more valuable than an occasional perfect day."
    }
}

/// Deterministic coaching prompts. These guide behavior without pretending to
/// diagnose health or infer emotions the member has not supplied.
enum GATIVXGuruCoach {
    static func suggestedNextAction(
        goal: String,
        purpose: String,
        emotion: String,
        dailySteps: Int?,
        dailyStepGoal: Int
    ) -> String {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmotion = emotion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanGoal.isEmpty else {
            return "Write one clear outcome you want to achieve."
        }
        guard !cleanPurpose.isEmpty else {
            return "Write one personal reason this goal matters to you."
        }
        guard !cleanEmotion.isEmpty else {
            return "Name how you want to feel when you reach your goal."
        }
        guard let dailySteps else {
            return "Take a comfortable 5-minute walk, then check your measured step reading."
        }

        let remaining = max(0, max(1, dailyStepGoal) - max(0, dailySteps))
        if remaining == 0 {
            return "You have reached today's step target. Take 2 minutes to notice how you feel and choose tomorrow's first 5-minute action."
        }
        if remaining <= 500 {
            return "Take a relaxed 3–5-minute walk to close the remaining \(remaining) steps. Keep a comfortable pace."
        }
        if remaining <= 2_000 {
            return "Take one comfortable 10-minute walk, then check your measured step total again."
        }
        return "Begin with 10 comfortable minutes. If that feels manageable, add a second short walk later. Consistency matters more than rushing."
    }

    static func purposeAnchor(goal: String, purpose: String, emotion: String) -> String {
        let cleanGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmotion = emotion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanGoal.isEmpty, !cleanPurpose.isEmpty, !cleanEmotion.isEmpty else {
            return "Complete your goal, purpose and emotion reflections. Guru will use your own words to reconnect you with your reason."
        }
        return "You are working toward \(cleanGoal) because \(cleanPurpose). Keep \(cleanEmotion) in view; today's small action is one vote for that future."
    }
}

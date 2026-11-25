import Foundation

enum ActivitySessionFinishPolicy {
    static func effectiveFinishDate(
        now: Date,
        startedAt: Date,
        lastRoutePointAt: Date?,
        recoveredWithoutResume: Bool
    ) -> Date {
        guard recoveredWithoutResume, let lastRoutePointAt else { return now }
        return min(now, max(lastRoutePointAt, startedAt))
    }
}

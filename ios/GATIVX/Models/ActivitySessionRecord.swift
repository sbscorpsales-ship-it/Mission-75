import Foundation
import CoreLocation

struct ActivitySessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    /// Authenticated Supabase user who owned this activity when it was recorded.
    /// Nil means the legacy or local-only record has no verified account owner.
    let ownerID: String?
    let activity: String
    let startedAt: Date
    let finishedAt: Date
    let steps: Int?
    let routePoints: [GATIVXRoutePoint]?
    let motionDistanceMeters: Double?

    init(
        id: UUID,
        activity: String,
        startedAt: Date,
        finishedAt: Date,
        steps: Int?,
        routePoints: [GATIVXRoutePoint]?,
        motionDistanceMeters: Double?,
        ownerID: String? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.activity = activity
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.routePoints = routePoints
        self.motionDistanceMeters = motionDistanceMeters
    }

    var gpsDistanceMeters: Double {
        guard let routePoints, routePoints.count > 1 else { return 0 }

        return zip(routePoints, routePoints.dropFirst()).reduce(0.0) { total, pair in
            guard !pair.1.breakBefore else { return total }

            let previous = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let current = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + current.distance(from: previous)
        }
    }

    /// A session can be uploaded to the activity cloud only when it contains
    /// a measured step count or a GPS route. Metadata-only legacy imports stay local.
    var hasCloudSyncPayload: Bool {
        steps != nil || !(routePoints?.isEmpty ?? true)
    }

    /// Merge a recovered copy of the same session without losing better local data.
    /// The existing record remains authoritative for identity, original start and owner.
    func mergingRecovery(_ incoming: ActivitySessionRecord) -> ActivitySessionRecord {
        let existingPoints = routePoints ?? []
        let incomingPoints = incoming.routePoints ?? []
        let useIncomingRoute = incoming.gpsDistanceMeters > gpsDistanceMeters ||
            (incoming.gpsDistanceMeters == gpsDistanceMeters && incomingPoints.count > existingPoints.count)
        let mergedSteps = [steps, incoming.steps].compactMap { $0 }.max()
        let mergedMotionDistance = [motionDistanceMeters, incoming.motionDistanceMeters].compactMap { $0 }.max()

        return ActivitySessionRecord(
            id: id,
            activity: activity,
            startedAt: startedAt,
            finishedAt: max(finishedAt, incoming.finishedAt),
            steps: mergedSteps,
            routePoints: useIncomingRoute ? incoming.routePoints : routePoints,
            motionDistanceMeters: mergedMotionDistance,
            ownerID: ownerID
        )
    }

    var durationText: String {
        let seconds = max(0, Int(finishedAt.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

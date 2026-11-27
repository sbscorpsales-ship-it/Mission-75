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

    /// Distance from accepted GPS fixes. Segment breaks and invalid GPS gaps are
    /// excluded so the app never draws or counts a straight line across a dropout.
    var gpsDistanceMeters: Double {
        guard let routePoints, routePoints.count > 1 else { return 0 }
        return zip(routePoints, routePoints.dropFirst()).reduce(0.0) { total, pair in
            guard !pair.1.breakBefore else { return total }
            let previous = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let current = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return total + current.distance(from: previous)
        }
    }

    enum DistanceSource: String, Codable {
        case gps
        case pedometer
        case strideEstimate
        case unavailable
    }

    struct DistanceResult: Equatable {
        let meters: Double?
        let source: DistanceSource
        var isEstimate: Bool { source == .strideEstimate }
    }

    /// GPS is authoritative when it has a usable route; Core Motion distance is
    /// the next choice. Step/stride distance is an explicitly estimated fallback.
    func distance(heightCm: Double?) -> DistanceResult {
        if gpsDistanceMeters > 0 {
            return DistanceResult(meters: gpsDistanceMeters, source: .gps)
        }
        if let motionDistanceMeters, motionDistanceMeters.isFinite, motionDistanceMeters > 0 {
            return DistanceResult(meters: motionDistanceMeters, source: .pedometer)
        }
        if let steps, steps > 0, let heightCm, heightCm.isFinite, heightCm > 0 {
            return DistanceResult(meters: Double(steps) * (heightCm / 100.0) * 0.415,
                                  source: .strideEstimate)
        }
        return DistanceResult(meters: nil, source: .unavailable)
    }

    /// Active time is calculated only from GPS intervals that indicate movement.
    /// Pauses, long GPS gaps, segment breaks and stationary intervals are excluded.
    /// Without adequate GPS evidence it returns nil rather than labelling elapsed
    /// wall-clock time as active exercise time.
    var activeDurationSeconds: Int? {
        guard let routePoints, routePoints.count > 1 else { return nil }
        let movingSeconds = zip(routePoints, routePoints.dropFirst()).reduce(0.0) { total, pair in
            let (previous, current) = pair
            guard !current.breakBefore,
                  current.horizontalAccuracy >= 0, current.horizontalAccuracy <= 50,
                  previous.horizontalAccuracy >= 0, previous.horizontalAccuracy <= 50 else { return total }
            let interval = current.timestamp.timeIntervalSince(previous.timestamp)
            guard interval > 0, interval <= 30 else { return total }
            let a = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let b = CLLocation(latitude: current.latitude, longitude: current.longitude)
            let speed = b.distance(from: a) / interval
            guard speed >= 0.5, speed <= 8 else { return total }
            return total + interval
        }
        return Int(movingSeconds.rounded())
    }

    var activeDurationText: String {
        guard let seconds = activeDurationSeconds else { return "—" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// GATIVX estimate: 0.5 kcal × body mass (kg) × distance (km).
    /// This is deliberately separate from measured HealthKit active energy.
    func estimatedCaloriesKcal(weightKg: Double, heightCm: Double?) -> Double? {
        guard weightKg.isFinite, weightKg > 0,
              let meters = distance(heightCm: heightCm).meters,
              meters > 0 else { return nil }
        return weightKg * (meters / 1000.0) * 0.5
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

    /// Elapsed session time retained for backward compatibility with existing history.
    var durationText: String {
        let seconds = max(0, Int(finishedAt.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

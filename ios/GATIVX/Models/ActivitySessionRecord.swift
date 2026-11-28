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
    /// Local-only values captured when this session was saved. This is never sent
    /// as a whole record to Supabase; cloud payloads use explicit field allowlists.
    let metricSnapshot: HistoricalMetricSnapshot?

    init(
        id: UUID,
        activity: String,
        startedAt: Date,
        finishedAt: Date,
        steps: Int?,
        routePoints: [GATIVXRoutePoint]?,
        motionDistanceMeters: Double?,
        ownerID: String? = nil,
        metricSnapshot: HistoricalMetricSnapshot? = nil
    ) {
        self.id = id
        self.ownerID = ownerID
        self.activity = activity
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.routePoints = routePoints
        self.motionDistanceMeters = motionDistanceMeters
        self.metricSnapshot = metricSnapshot
    }

    /// Local historical estimate inputs and results captured at Finish & Save.
    /// Only the inputs actually used are retained: weight for a calorie estimate,
    /// height for a stride-distance estimate. Missing values remain unavailable.
    struct HistoricalMetricSnapshot: Codable, Equatable {
        let capturedAt: Date
        let distanceMeters: Double?
        let distanceSource: DistanceSource
        let movingTimeSeconds: Int?
        let estimatedActiveCaloriesKcal: Double?
        let weightKgUsedForEstimate: Double?
        let heightCmUsedForStrideEstimate: Double?
        let calculationEngineVersion: String?
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
        // No qualifying movement is not a measured zero-minute workout.
        guard movingSeconds > 0 else { return nil }
        return Int(movingSeconds.rounded())
    }

    var activeDurationText: String {
        guard let seconds = activeDurationSeconds else { return "—" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Canonical MET-based estimate from the shared GATIVX activity engine.
    /// Requires measured moving time and a usable distance; never substitutes
    /// elapsed wall-clock time or emits a zero when the inputs are unavailable.
    func activityCalculation(
        weightKg: Double,
        heightCm: Double?,
        ageYears: Double? = nil,
        heartRateBpm: Double? = nil
    ) -> GATIVXActivityCalculationResult {
        guard activity.caseInsensitiveCompare("Walking") == .orderedSame,
              let movingSeconds = activeDurationSeconds,
              movingSeconds > 0,
              let meters = distance(heightCm: heightCm).meters,
              meters.isFinite, meters > 0 else {
            return GATIVXActivityCalculationEngine.estimate(
                weightKg: weightKg,
                movingMinutes: 0,
                speedKmh: nil,
                activityType: activity
            )
        }

        let movingMinutes = Double(movingSeconds) / 60.0
        let speedKmh = (meters / 1_000.0) / (movingMinutes / 60.0)
        return GATIVXActivityCalculationEngine.estimate(
            weightKg: weightKg,
            movingMinutes: movingMinutes,
            speedKmh: speedKmh,
            grade: 0,
            heartRateBpm: heartRateBpm,
            ageYears: ageYears,
            activityType: activity
        )
    }

    /// Estimated active calories only. Measured HealthKit energy must remain a
    /// separate authoritative value and must never be added to this estimate.
    func estimatedCaloriesKcal(weightKg: Double, heightCm: Double?) -> Double? {
        activityCalculation(weightKg: weightKg, heightCm: heightCm).activeCaloriesKcal
    }

    func estimatedActivityPoints(
        weightKg: Double,
        heightCm: Double?,
        ageYears: Double? = nil,
        heartRateBpm: Double? = nil
    ) -> Int? {
        let result = activityCalculation(
            weightKg: weightKg,
            heightCm: heightCm,
            ageYears: ageYears,
            heartRateBpm: heartRateBpm
        )
        return result.status == .estimated ? result.activityPoints : nil
    }

    /// Capture a stable, local-only history snapshot at Finish & Save. Later edits
    /// to the member's Profile must not recalculate an older session with new inputs.
    func withHistoricalMetricSnapshot(
        weightKg: Double?,
        heightCm: Double?,
        capturedAt: Date = Date()
    ) -> ActivitySessionRecord {
        let validWeightKg = weightKg.flatMap {
            $0.isFinite && (25...300).contains($0) ? $0 : nil
        }
        let validHeightCm = heightCm.flatMap {
            $0.isFinite && (100...250).contains($0) ? $0 : nil
        }
        let distanceResult = distance(heightCm: validHeightCm)
        let storedDistanceMeters = distanceResult.meters.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        let movingSeconds = activeDurationSeconds

        let calculation: GATIVXActivityCalculationResult?
        if activity.caseInsensitiveCompare("Walking") == .orderedSame,
           let weight = validWeightKg,
           let movingSeconds, movingSeconds > 0,
           storedDistanceMeters != nil {
            let candidate = activityCalculation(weightKg: weight, heightCm: validHeightCm)
            calculation = candidate.status == .estimated ? candidate : nil
        } else {
            calculation = nil
        }

        let calories = calculation?.activeCaloriesKcal
        let snapshot = HistoricalMetricSnapshot(
            capturedAt: capturedAt,
            distanceMeters: storedDistanceMeters,
            distanceSource: storedDistanceMeters == nil ? .unavailable : distanceResult.source,
            movingTimeSeconds: movingSeconds,
            estimatedActiveCaloriesKcal: calories,
            weightKgUsedForEstimate: calories == nil ? nil : validWeightKg,
            heightCmUsedForStrideEstimate: distanceResult.source == .strideEstimate
                && storedDistanceMeters != nil ? validHeightCm : nil,
            calculationEngineVersion: calories == nil ? nil : calculation?.engineVersion
        )

        return ActivitySessionRecord(
            id: id,
            activity: activity,
            startedAt: startedAt,
            finishedAt: finishedAt,
            steps: steps,
            routePoints: routePoints,
            motionDistanceMeters: motionDistanceMeters,
            ownerID: ownerID,
            metricSnapshot: snapshot
        )
    }

    /// History uses the saved snapshot when present. Legacy records can still
    /// show GPS/pedometer measurements, but never derive a stride estimate from
    /// today's Profile height or calories from today's Profile weight.
    var historicalDistanceResult: DistanceResult {
        if let metricSnapshot {
            return DistanceResult(
                meters: metricSnapshot.distanceMeters,
                source: metricSnapshot.distanceSource
            )
        }
        return distance(heightCm: nil)
    }

    var historicalActiveDurationSeconds: Int? {
        if let metricSnapshot {
            return metricSnapshot.movingTimeSeconds
        }
        return activeDurationSeconds
    }

    var historicalActiveDurationText: String {
        guard let seconds = historicalActiveDurationSeconds else { return "—" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var historicalActiveCaloriesKcal: Double? {
        metricSnapshot?.estimatedActiveCaloriesKcal
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
        let metricsChanged = useIncomingRoute ||
            mergedSteps != steps ||
            mergedMotionDistance != motionDistanceMeters
        let mergedMetricSnapshot = metricsChanged
            ? incoming.metricSnapshot
            : (metricSnapshot ?? incoming.metricSnapshot)

        return ActivitySessionRecord(
            id: id,
            activity: activity,
            startedAt: startedAt,
            finishedAt: max(finishedAt, incoming.finishedAt),
            steps: mergedSteps,
            routePoints: useIncomingRoute ? incoming.routePoints : routePoints,
            motionDistanceMeters: mergedMotionDistance,
            ownerID: ownerID,
            metricSnapshot: mergedMetricSnapshot
        )
    }

    /// Elapsed session time retained for backward compatibility with existing history.
    var durationText: String {
        let seconds = max(0, Int(finishedAt.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

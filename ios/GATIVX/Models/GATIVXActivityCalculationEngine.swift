import Foundation

/// Swift port of shared/gativx-activity-engine.js (v1.1.2).
/// Estimates are explicitly labelled; they are not HealthKit measurements.
struct GATIVXActivityCalculationResult: Equatable {
    enum Status: String {
        case estimated
        case insufficientData = "insufficient_data"
    }

    enum CalculationMethod: String {
        case speedGradeMET = "speed_grade_met"
        case cadenceMET = "cadence_met"
        case none
    }

    enum IntensitySource: String {
        case heartRate = "heart_rate"
        case metEstimate = "met_estimate"
        case cadenceThreshold = "cadence_threshold"
        case none
    }

    let engineVersion: String
    let status: Status
    let activeCaloriesKcal: Double?
    let grossCaloriesKcal: Double?
    let met: Double?
    let movingMinutes: Double
    let activityPoints: Int
    let moderateMinutes: Int
    let vigorousMinutes: Int
    let calculationMethod: CalculationMethod
    let intensitySource: IntensitySource
}

/// Canonical GATIVX walking estimate. Keep constants and golden values aligned
/// with docs/GATIVX_ACTIVITY_ENGINE_SPEC.md and the shared JavaScript engine.
enum GATIVXActivityCalculationEngine {
    static let version = "1.1.2"

    private static let walkingAnchors: [(speedKmh: Double, met: Double)] = [
        (1, 1.8), (2, 2), (2.5, 2.3), (3, 2.5), (3.5, 2.8),
        (4, 3), (4.5, 3.5), (5, 3.8), (5.5, 4.3), (6, 13.5 / 3.5),
        (6.5, 5.5), (7, 6), (7.5, 6.5), (8, 7), (9, 8.3),
        (10, 9.8), (11, 11), (12, 12.5)
    ]

    static func estimate(
        weightKg: Double,
        movingMinutes: Double,
        speedKmh: Double?,
        grade: Double = 0,
        cadenceSpm: Double? = nil,
        heartRateBpm: Double? = nil,
        ageYears: Double? = nil,
        activityType: String = "walking"
    ) -> GATIVXActivityCalculationResult {
        guard weightKg.isFinite, (25...300).contains(weightKg),
              movingMinutes.isFinite, movingMinutes > 0, movingMinutes <= 1_440,
              activityType.lowercased() == "walking" else {
            return unavailable(movingMinutes: movingMinutes)
        }

        let hasSpeed = speedKmh.map { $0.isFinite && $0 > 0 } ?? false
        let walkingMET: Double?
        let method: GATIVXActivityCalculationResult.CalculationMethod

        if hasSpeed, let speedKmh {
            walkingMET = estimateMET(speedKmh: speedKmh, grade: grade)
            method = .speedGradeMET
        } else if let cadenceSpm, let cadenceMET = estimateMETFromCadence(cadenceSpm) {
            walkingMET = cadenceMET
            method = .cadenceMET
        } else {
            walkingMET = nil
            method = .none
        }

        guard let met = walkingMET else {
            return unavailable(movingMinutes: movingMinutes)
        }

        let gross = met * 3.5 * weightKg * movingMinutes / 200
        let resting = 3.5 * weightKg * movingMinutes / 200
        let active = max(0, gross - resting)
        let intensity = classifyIntensity(
            movingMinutes: movingMinutes,
            met: met,
            cadenceSpm: cadenceSpm,
            heartRateBpm: heartRateBpm,
            ageYears: ageYears
        )

        return GATIVXActivityCalculationResult(
            engineVersion: version,
            status: .estimated,
            activeCaloriesKcal: active,
            grossCaloriesKcal: gross,
            met: met,
            movingMinutes: movingMinutes,
            activityPoints: intensity.points,
            moderateMinutes: intensity.moderateMinutes,
            vigorousMinutes: intensity.vigorousMinutes,
            calculationMethod: method,
            intensitySource: intensity.source
        )
    }

    static func estimateMETFromCadence(_ cadenceSpm: Double) -> Double? {
        guard cadenceSpm.isFinite, (40...140).contains(cadenceSpm) else { return nil }
        let vo2 = 1.811 + 0.02014 * cadenceSpm + 0.0007427 * cadenceSpm * cadenceSpm
        return clamp(vo2 / 3.5, lower: 1, upper: 16)
    }

    static func estimateMET(speedKmh: Double, grade: Double = 0) -> Double? {
        guard speedKmh.isFinite, speedKmh > 0 else { return nil }
        let boundedGrade = clamp(grade.isFinite ? grade : 0, lower: -0.10, upper: 0.15)
        let metersPerMinute = speedKmh * 1_000 / 60
        let met: Double

        if (3...6).contains(speedKmh) {
            let vo2 = 0.1 * metersPerMinute
                + 1.8 * metersPerMinute * boundedGrade
                + 3.5
            met = vo2 / 3.5
        } else {
            met = interpolateWalkingMET(speedKmh)
                + (1.8 * metersPerMinute * boundedGrade / 3.5)
        }

        return clamp(met, lower: 1, upper: 16)
    }

    private static func interpolateWalkingMET(_ speedKmh: Double) -> Double {
        if speedKmh <= walkingAnchors[0].speedKmh {
            return walkingAnchors[0].met
        }

        for index in 1..<walkingAnchors.count {
            let right = walkingAnchors[index]
            let left = walkingAnchors[index - 1]
            if speedKmh <= right.speedKmh {
                let fraction = (speedKmh - left.speedKmh)
                    / (right.speedKmh - left.speedKmh)
                return left.met + (right.met - left.met) * fraction
            }
        }

        return walkingAnchors[walkingAnchors.count - 1].met
    }

    private static func classifyIntensity(
        movingMinutes: Double,
        met: Double,
        cadenceSpm: Double?,
        heartRateBpm: Double?,
        ageYears: Double?
    ) -> (points: Int, moderateMinutes: Int, vigorousMinutes: Int,
          source: GATIVXActivityCalculationResult.IntensitySource) {
        let wholeMinutes = max(0, Int(movingMinutes))

        if let heartRateBpm, let ageYears,
           heartRateBpm.isFinite, heartRateBpm > 0,
           ageYears.isFinite, (18...100).contains(ageYears) {
            let estimatedMaxHeartRate = 205.8 - 0.685 * ageYears
            let ratio = heartRateBpm / estimatedMaxHeartRate
            if ratio >= 0.70 {
                return (2 * wholeMinutes, 0, wholeMinutes, .heartRate)
            }
            if ratio >= 0.50 {
                return (wholeMinutes, wholeMinutes, 0, .heartRate)
            }
            return (0, 0, 0, .heartRate)
        }

        if met >= 6 {
            return (2 * wholeMinutes, 0, wholeMinutes, .metEstimate)
        }
        if met >= 3 {
            return (wholeMinutes, wholeMinutes, 0, .metEstimate)
        }

        if let cadenceSpm, cadenceSpm.isFinite {
            if cadenceSpm >= 130 {
                return (2 * wholeMinutes, 0, wholeMinutes, .cadenceThreshold)
            }
            if cadenceSpm >= 100 {
                return (wholeMinutes, wholeMinutes, 0, .cadenceThreshold)
            }
            return (0, 0, 0, .cadenceThreshold)
        }

        return (0, 0, 0, .none)
    }

    private static func unavailable(
        movingMinutes: Double
    ) -> GATIVXActivityCalculationResult {
        GATIVXActivityCalculationResult(
            engineVersion: version,
            status: .insufficientData,
            activeCaloriesKcal: nil,
            grossCaloriesKcal: nil,
            met: nil,
            movingMinutes: movingMinutes,
            activityPoints: 0,
            moderateMinutes: 0,
            vigorousMinutes: 0,
            calculationMethod: .none,
            intensitySource: .none
        )
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

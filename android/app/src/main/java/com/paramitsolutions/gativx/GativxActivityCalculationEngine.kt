package com.paramitsolutions.gativx

import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt

internal data class GativxActivityCalculationResult(
    val engineVersion: String,
    val status: Status,
    val activeCaloriesKcal: Double?,
    val grossCaloriesKcal: Double?,
    val met: Double?,
    val movingMinutes: Double,
    val activityPoints: Int,
    val moderateMinutes: Int,
    val vigorousMinutes: Int,
    val calculationMethod: CalculationMethod,
    val intensitySource: IntensitySource
) {
    enum class Status { ESTIMATED, INSUFFICIENT_DATA }
    enum class CalculationMethod { SPEED_GRADE_MET, CADENCE_MET, NONE }
    enum class IntensitySource { HEART_RATE, MET_ESTIMATE, CADENCE_THRESHOLD, NONE }
}

/** Kotlin port of shared/gativx-activity-engine.js v1.1.2. */
internal object GativxActivityCalculationEngine {
    const val VERSION = "1.1.2"
    private const val EARTH_RADIUS_METERS = 6_371_000.0

    private val walkingAnchors = listOf(
        1.0 to 1.8, 2.0 to 2.0, 2.5 to 2.3, 3.0 to 2.5,
        3.5 to 2.8, 4.0 to 3.0, 4.5 to 3.5, 5.0 to 3.8,
        5.5 to 4.3, 6.0 to (13.5 / 3.5), 6.5 to 5.5, 7.0 to 6.0,
        7.5 to 6.5, 8.0 to 7.0, 9.0 to 8.3, 10.0 to 9.8,
        11.0 to 11.0, 12.0 to 12.5
    )

    fun movingDurationSeconds(points: List<WalkOnPoint>): Long? {
        if (points.size < 2) return null
        var movingSeconds = 0.0
        for (index in 1 until points.size) {
            val previous = points[index - 1]
            val current = points[index]
            if (current.breakBefore) continue
            if (!previous.accuracyMeters.isFinite() || previous.accuracyMeters !in 0.0..50.0) continue
            if (!current.accuracyMeters.isFinite() || current.accuracyMeters !in 0.0..50.0) continue

            val intervalSeconds = (current.timestampMillis - previous.timestampMillis) / 1_000.0
            if (!intervalSeconds.isFinite() || intervalSeconds <= 0.0 || intervalSeconds > 30.0) continue

            val distance = distanceMeters(previous.latitude, previous.longitude, current.latitude, current.longitude)
            val speed = distance / intervalSeconds
            if (speed in 0.5..8.0) movingSeconds += intervalSeconds
        }
        if (movingSeconds <= 0.0) return null
        return movingSeconds.roundToLong().coerceIn(1L, 86_400L)
    }

    fun estimate(
        weightKg: Double?,
        movingMinutes: Double?,
        speedKmh: Double?,
        grade: Double = 0.0,
        cadenceSpm: Double? = null,
        heartRateBpm: Double? = null,
        ageYears: Double? = null,
        activityType: String = "walking"
    ): GativxActivityCalculationResult {
        val minutes = movingMinutes ?: 0.0
        if (weightKg == null || !weightKg.isFinite() || weightKg !in 25.0..300.0 ||
            movingMinutes == null || !movingMinutes.isFinite() || movingMinutes <= 0.0 || movingMinutes > 1_440.0 ||
            !activityType.equals("walking", ignoreCase = true)) {
            return unavailable(minutes)
        }

        val hasSpeed = speedKmh != null && speedKmh.isFinite() && speedKmh > 0.0
        val met: Double
        val method: GativxActivityCalculationResult.CalculationMethod
        if (hasSpeed) {
            met = estimateMET(speedKmh!!, grade) ?: return unavailable(minutes)
            method = GativxActivityCalculationResult.CalculationMethod.SPEED_GRADE_MET
        } else {
            met = cadenceSpm?.let(::estimateMETFromCadence) ?: return unavailable(minutes)
            method = GativxActivityCalculationResult.CalculationMethod.CADENCE_MET
        }

        val gross = met * 3.5 * weightKg * movingMinutes / 200.0
        val resting = 3.5 * weightKg * movingMinutes / 200.0
        val active = max(0.0, gross - resting)
        val intensity = classifyIntensity(movingMinutes, met, cadenceSpm, heartRateBpm, ageYears)
        return GativxActivityCalculationResult(
            engineVersion = VERSION,
            status = GativxActivityCalculationResult.Status.ESTIMATED,
            activeCaloriesKcal = active,
            grossCaloriesKcal = gross,
            met = met,
            movingMinutes = movingMinutes,
            activityPoints = intensity.points,
            moderateMinutes = intensity.moderateMinutes,
            vigorousMinutes = intensity.vigorousMinutes,
            calculationMethod = method,
            intensitySource = intensity.source
        )
    }

    fun estimateMETFromCadence(cadenceSpm: Double): Double? {
        if (!cadenceSpm.isFinite() || cadenceSpm !in 40.0..140.0) return null
        val vo2 = 1.811 + 0.02014 * cadenceSpm + 0.0007427 * cadenceSpm * cadenceSpm
        return clamp(vo2 / 3.5, 1.0, 16.0)
    }

    fun estimateMET(speedKmh: Double, grade: Double = 0.0): Double? {
        if (!speedKmh.isFinite() || speedKmh <= 0.0) return null
        val boundedGrade = clamp(if (grade.isFinite()) grade else 0.0, -0.10, 0.15)
        val metersPerMinute = speedKmh * 1_000.0 / 60.0
        val met = if (speedKmh in 3.0..6.0) {
            val vo2 = 0.1 * metersPerMinute + 1.8 * metersPerMinute * boundedGrade + 3.5
            vo2 / 3.5
        } else {
            interpolateWalkingMET(speedKmh) + 1.8 * metersPerMinute * boundedGrade / 3.5
        }
        return clamp(met, 1.0, 16.0)
    }

    private fun interpolateWalkingMET(speedKmh: Double): Double {
        if (speedKmh <= walkingAnchors.first().first) return walkingAnchors.first().second
        for (index in 1 until walkingAnchors.size) {
            val left = walkingAnchors[index - 1]
            val right = walkingAnchors[index]
            if (speedKmh <= right.first) {
                val fraction = (speedKmh - left.first) / (right.first - left.first)
                return left.second + (right.second - left.second) * fraction
            }
        }
        return walkingAnchors.last().second
    }

    private data class Intensity(
        val points: Int,
        val moderateMinutes: Int,
        val vigorousMinutes: Int,
        val source: GativxActivityCalculationResult.IntensitySource
    )

    private fun classifyIntensity(
        movingMinutes: Double,
        met: Double,
        cadenceSpm: Double?,
        heartRateBpm: Double?,
        ageYears: Double?
    ): Intensity {
        val wholeMinutes = floor(movingMinutes).toInt().coerceAtLeast(0)
        if (heartRateBpm != null && ageYears != null &&
            heartRateBpm.isFinite() && heartRateBpm > 0.0 &&
            ageYears.isFinite() && ageYears in 18.0..100.0) {
            val maximum = 205.8 - 0.685 * ageYears
            val ratio = heartRateBpm / maximum
            return when {
                ratio >= 0.70 -> Intensity(2 * wholeMinutes, 0, wholeMinutes, GativxActivityCalculationResult.IntensitySource.HEART_RATE)
                ratio >= 0.50 -> Intensity(wholeMinutes, wholeMinutes, 0, GativxActivityCalculationResult.IntensitySource.HEART_RATE)
                else -> Intensity(0, 0, 0, GativxActivityCalculationResult.IntensitySource.HEART_RATE)
            }
        }
        return when {
            met >= 6.0 -> Intensity(2 * wholeMinutes, 0, wholeMinutes, GativxActivityCalculationResult.IntensitySource.MET_ESTIMATE)
            met >= 3.0 -> Intensity(wholeMinutes, wholeMinutes, 0, GativxActivityCalculationResult.IntensitySource.MET_ESTIMATE)
            cadenceSpm != null && cadenceSpm >= 130.0 -> Intensity(2 * wholeMinutes, 0, wholeMinutes, GativxActivityCalculationResult.IntensitySource.CADENCE_THRESHOLD)
            cadenceSpm != null && cadenceSpm >= 100.0 -> Intensity(wholeMinutes, wholeMinutes, 0, GativxActivityCalculationResult.IntensitySource.CADENCE_THRESHOLD)
            else -> Intensity(0, 0, 0, GativxActivityCalculationResult.IntensitySource.NONE)
        }
    }

    private fun unavailable(movingMinutes: Double) = GativxActivityCalculationResult(
        engineVersion = VERSION,
        status = GativxActivityCalculationResult.Status.INSUFFICIENT_DATA,
        activeCaloriesKcal = null,
        grossCaloriesKcal = null,
        met = null,
        movingMinutes = movingMinutes,
        activityPoints = 0,
        moderateMinutes = 0,
        vigorousMinutes = 0,
        calculationMethod = GativxActivityCalculationResult.CalculationMethod.NONE,
        intensitySource = GativxActivityCalculationResult.IntensitySource.NONE
    )

    private fun distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        if (!lat1.isFinite() || !lon1.isFinite() || !lat2.isFinite() || !lon2.isFinite()) return 0.0
        if (lat1 !in -90.0..90.0 || lat2 !in -90.0..90.0 || lon1 !in -180.0..180.0 || lon2 !in -180.0..180.0) return 0.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2)
        val bounded = clamp(a, 0.0, 1.0)
        return 2.0 * EARTH_RADIUS_METERS * asin(sqrt(bounded))
    }

    private fun clamp(value: Double, lower: Double, upper: Double): Double =
        min(upper, max(lower, value))
}

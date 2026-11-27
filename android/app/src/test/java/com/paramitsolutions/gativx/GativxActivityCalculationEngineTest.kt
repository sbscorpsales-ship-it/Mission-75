package com.paramitsolutions.gativx

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GativxActivityCalculationEngineTest {
    @Test
    fun briskWalkingMatchesSharedGoldenValues() {
        val result = GativxActivityCalculationEngine.estimate(
            weightKg = 70.0,
            movingMinutes = 30.0,
            speedKmh = 5.0,
            grade = 0.0,
            cadenceSpm = 112.0
        )

        assertEquals(GativxActivityCalculationResult.Status.ESTIMATED, result.status)
        assertEquals("1.1.2", result.engineVersion)
        assertEquals(3.38, result.met!!, 0.02)
        assertEquals(88.0, result.activeCaloriesKcal!!, 1.0)
        assertEquals(30, result.activityPoints)
        assertEquals(GativxActivityCalculationResult.CalculationMethod.SPEED_GRADE_MET, result.calculationMethod)
        assertEquals(GativxActivityCalculationResult.IntensitySource.MET_ESTIMATE, result.intensitySource)
    }

    @Test
    fun cadenceFallbackMatchesSharedGoldenValues() {
        val result = GativxActivityCalculationEngine.estimate(
            weightKg = 70.0,
            movingMinutes = 30.0,
            speedKmh = null,
            cadenceSpm = 100.0
        )

        assertEquals(GativxActivityCalculationResult.Status.ESTIMATED, result.status)
        assertEquals(3.21, result.met!!, 0.02)
        assertEquals(81.4, result.activeCaloriesKcal!!, 1.0)
        assertEquals(GativxActivityCalculationResult.CalculationMethod.CADENCE_MET, result.calculationMethod)
    }

    @Test
    fun heartRateOverridesMETIntensityClassification() {
        val result = GativxActivityCalculationEngine.estimate(
            weightKg = 70.0,
            movingMinutes = 12.0,
            speedKmh = 5.0,
            heartRateBpm = 120.0,
            ageYears = 40.0
        )

        assertEquals(12, result.activityPoints)
        assertEquals(GativxActivityCalculationResult.IntensitySource.HEART_RATE, result.intensitySource)
    }

    @Test
    fun unsupportedActivitiesAndMissingInputsRemainUnavailable() {
        val unsupported = GativxActivityCalculationEngine.estimate(
            weightKg = 70.0,
            movingMinutes = 30.0,
            speedKmh = 5.0,
            activityType = "running"
        )
        val missingWeight = GativxActivityCalculationEngine.estimate(
            weightKg = null,
            movingMinutes = 30.0,
            speedKmh = 5.0
        )
        val missingMovement = GativxActivityCalculationEngine.estimate(
            weightKg = 70.0,
            movingMinutes = null,
            speedKmh = 5.0
        )

        assertEquals(GativxActivityCalculationResult.Status.INSUFFICIENT_DATA, unsupported.status)
        assertEquals(GativxActivityCalculationResult.Status.INSUFFICIENT_DATA, missingWeight.status)
        assertEquals(GativxActivityCalculationResult.Status.INSUFFICIENT_DATA, missingMovement.status)
        assertNull(unsupported.activeCaloriesKcal)
        assertNull(missingWeight.activeCaloriesKcal)
        assertNull(missingMovement.activeCaloriesKcal)
    }

    @Test
    fun sixKmhMETBoundaryRemainsContinuous() {
        val at = GativxActivityCalculationEngine.estimateMET(6.0)!!
        val below = GativxActivityCalculationEngine.estimateMET(5.9999)!!
        val above = GativxActivityCalculationEngine.estimateMET(6.0001)!!

        assertEquals(13.5 / 3.5, at, 0.001)
        assertEquals(at, below, 0.001)
        assertEquals(at, above, 0.002)
    }

    @Test
    fun movingTimeExcludesStationaryGapsBreaksAndInaccurateFixes() {
        val latitudeStep = 25.0 / 111_195.0
        val origin = 15.8500
        val points = listOf(
            point(origin, 0, breakBefore = true),
            point(origin + latitudeStep, 30_000),
            point(origin + latitudeStep * 2, 60_000),
            point(origin + latitudeStep * 2, 90_000), // stationary
            point(origin + latitudeStep * 3, 120_000),
            point(origin + latitudeStep * 4, 200_000), // long gap
            point(origin + latitudeStep * 5, 230_000, breakBefore = true),
            point(origin + latitudeStep * 6, 260_000),
            point(origin + latitudeStep * 7, 290_000, accuracy = 60.0),
            point(origin + latitudeStep * 8, 320_000)
        )

        assertEquals(120L, GativxActivityCalculationEngine.movingDurationSeconds(points))
    }

    @Test
    fun noValidMovingIntervalsAreUnavailableRatherThanZero() {
        val points = listOf(
            point(15.8500, 0, breakBefore = true),
            point(15.8500, 30_000),
            point(15.8500, 60_000)
        )

        assertNull(GativxActivityCalculationEngine.movingDurationSeconds(points))
    }

    @Test
    fun movingDurationSurvivesSessionEncodingAndLegacyDecode() {
        val legacy = JSONObject()
            .put("id", "walk-legacy")
            .put("activity", "Walking")
            .put("startedAt", "2026-11-28T00:00:00Z")
            .put("finishedAt", JSONObject.NULL)
            .put("durationSeconds", 1_200)
            .put("distanceMeters", 1_000.0)
            .put("points", JSONArray())
            .put("sessionSteps", 1_000)
            .put("stepCounterLastValue", JSONObject.NULL)
            .put("synced", false)
            .put("ownerUserId", JSONObject.NULL)

        assertNull(WalkOnStore.decodeSession(legacy).movingDurationSeconds)
        legacy.put("movingDurationSeconds", 720)
        assertEquals(720L, WalkOnStore.decodeSession(legacy).movingDurationSeconds)
        assertNotNull(GativxActivityCalculationEngine.movingDurationSeconds(listOf(
            point(15.85, 0, breakBefore = true),
            point(15.85 + 25.0 / 111_195.0, 30_000)
        )))
    }

    private fun point(
        latitude: Double,
        timestampMillis: Long,
        breakBefore: Boolean = false,
        accuracy: Double = 4.0
    ) = WalkOnPoint(
        latitude = latitude,
        longitude = 74.5000,
        timestampMillis = timestampMillis,
        accuracyMeters = accuracy,
        breakBefore = breakBefore
    )
}

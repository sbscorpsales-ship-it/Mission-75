package com.paramitsolutions.gativx

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WalkOnStartPolicyTest {
    @Test
    fun allowsStartWhenNoActiveDraftExists() {
        assertFalse(WalkOnStartPolicy.shouldBlockNewSession(ActiveWalkDraftState.ABSENT))
    }

    @Test
    fun resumesReadableActiveDraftInsteadOfBlocking() {
        assertFalse(WalkOnStartPolicy.shouldBlockNewSession(ActiveWalkDraftState.READABLE))
    }

    @Test
    fun blocksNewStartWhenExistingDraftIsUnreadable() {
        assertTrue(WalkOnStartPolicy.shouldBlockNewSession(ActiveWalkDraftState.UNREADABLE))
    }

    @Test
    fun unreadableCompletedHistoryNeverLooksFullyBackedUp() {
        assertTrue(WalkOnStartPolicy.shouldBlockSyncSuccess(completedHistoryUnreadable = true))
        assertFalse(WalkOnStartPolicy.shouldBlockSyncSuccess(completedHistoryUnreadable = false))
    }

    @Test
    fun legacyWalkHistoryWithoutMetricSnapshotRemainsUnavailable() {
        val legacy = JSONObject()
            .put("id", "walk-legacy-metrics")
            .put("activity", "Walking")
            .put("startedAt", "2026-11-28T00:00:00Z")
            .put("finishedAt", "2026-11-28T00:12:00Z")
            .put("durationSeconds", 720)
            .put("distanceMeters", 1_000.0)
            .put("points", JSONArray())
            .put("sessionSteps", 1_000)
            .put("stepCounterLastValue", JSONObject.NULL)
            .put("synced", false)
            .put("ownerUserId", JSONObject.NULL)

        val decoded = WalkOnStore.decodeSession(legacy)
        assertNull(decoded.estimatedActiveCaloriesKcal)
        assertNull(decoded.weightKgUsedForEstimate)
        assertNull(decoded.calculationEngineVersion)
    }

    @Test
    fun localWalkMetricSnapshotRoundTripsButCloudPayloadUsesAllowlist() {
        val points = listOf(
            WalkOnPoint(15.8500, 74.5000, 1_800_000_000_000L, 4.0, true),
            WalkOnPoint(15.8502, 74.5000, 1_800_000_018_000L, 4.0, false)
        )
        val saved = WalkOnSession(
            id = "walk-metrics",
            activity = "Walking",
            startedAt = "2026-11-28T00:00:00Z",
            finishedAt = "2026-11-28T00:12:00Z",
            durationSeconds = 720,
            distanceMeters = 1_000.0,
            points = points,
            sessionSteps = 1_000,
            movingDurationSeconds = 720,
            estimatedActiveCaloriesKcal = 40.0,
            weightKgUsedForEstimate = 80.0,
            calculationEngineVersion = "1.1.2"
        )
        val restored = WalkOnStore.decodeSession(JSONObject(WalkOnStore.encodeSession(saved)))
        assertEquals(40.0, restored.estimatedActiveCaloriesKcal!!, 0.5)
        assertEquals(80.0, restored.weightKgUsedForEstimate!!, 0.001)
        assertEquals("1.1.2", restored.calculationEngineVersion)

        val incompleteSnapshot = JSONObject(WalkOnStore.encodeSession(saved))
            .put("calculationEngineVersion", JSONObject.NULL)
        val incomplete = WalkOnStore.decodeSession(incompleteSnapshot)
        assertNull(incomplete.estimatedActiveCaloriesKcal)
        assertNull(incomplete.weightKgUsedForEstimate)
        assertNull(incomplete.calculationEngineVersion)

        val payload = WalkOnCloudPayload.route(restored)
        val keys = mutableSetOf<String>()
        val iterator = payload.keys()
        while (iterator.hasNext()) keys.add(iterator.next())
        assertEquals(
            setOf("p_session_id", "p_started_at", "p_finished_at", "p_duration_seconds",
                "p_distance_m", "p_steps", "p_route_points"),
            keys
        )
        assertFalse(payload.has("estimatedActiveCaloriesKcal"))
        assertFalse(payload.has("weightKgUsedForEstimate"))
        assertFalse(payload.has("calculationEngineVersion"))

        val unknownStepsPayload = WalkOnCloudPayload.route(restored.copy(sessionSteps = 0L))
        assertTrue(unknownStepsPayload.has("p_steps"))
        assertTrue(unknownStepsPayload.isNull("p_steps"),
            "Unknown step count must remain JSON null, never be converted to zero.")
    }

    @Test
    fun localProfileWeightStorageKeyIsScopedAndDoesNotExposeAccountId() {
        val first = WalkOnStore.profileWeightStorageKey("member-one")
        val second = WalkOnStore.profileWeightStorageKey("member-two")
        val guest = WalkOnStore.profileWeightStorageKey(null)

        assertFalse(first == second)
        assertFalse(first == guest)
        assertFalse(first.contains("member-one"))
        assertEquals(first, WalkOnStore.profileWeightStorageKey("member-one"))
    }

    @Test
    fun strictPointDecoderRetainsEveryValidPoint() {
        val point = JSONObject()
            .put("latitude", 12.9716)
            .put("longitude", 77.5946)
            .put("timestampMillis", 1_800_000_000_000L)
            .put("accuracyMeters", 5.0)
            .put("breakBefore", false)

        assertEquals(1, WalkOnStore.decodePointsStrict(JSONArray().put(point)).size)
    }

    @Test
    fun strictPointDecoderRejectsMalformedPointInsteadOfDroppingIt() {
        val malformed = JSONObject()
            .put("latitude", "not-a-number")
            .put("longitude", 77.5946)
            .put("timestampMillis", 1_800_000_000_000L)
            .put("accuracyMeters", 5.0)
            .put("breakBefore", false)

        assertThrows(Exception::class.java) {
            WalkOnStore.decodePointsStrict(JSONArray().put(malformed))
        }
    }
}

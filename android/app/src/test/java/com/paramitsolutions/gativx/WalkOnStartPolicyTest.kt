package com.paramitsolutions.gativx

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

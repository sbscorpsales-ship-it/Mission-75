package com.paramitsolutions.gativx

import org.junit.Assert.assertFalse
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
}

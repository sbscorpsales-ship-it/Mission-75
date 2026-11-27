package com.paramitsolutions.gativx

/**
 * Distinguishes an absent active route from a route that exists but cannot be
 * decrypted or decoded. Treating both as null could overwrite a recoverable draft.
 */
internal enum class ActiveWalkDraftState {
    ABSENT,
    READABLE,
    UNREADABLE
}

internal object WalkOnStartPolicy {
    fun shouldBlockNewSession(state: ActiveWalkDraftState): Boolean =
        state == ActiveWalkDraftState.UNREADABLE

    fun shouldBlockSyncSuccess(completedHistoryUnreadable: Boolean): Boolean =
        completedHistoryUnreadable
}

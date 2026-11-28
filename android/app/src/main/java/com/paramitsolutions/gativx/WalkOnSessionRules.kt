package com.paramitsolutions.gativx

/** Pure activity-save rules shared by the Android persistence layer and JVM tests. */
internal object WalkOnSessionRules {
    fun hasPersistableActivity(gpsPointCount: Int, measuredSteps: Long): Boolean =
        gpsPointCount > 0 || measuredSteps > 0L
}

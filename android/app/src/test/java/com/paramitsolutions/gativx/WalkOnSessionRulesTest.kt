package com.paramitsolutions.gativx

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WalkOnSessionRulesTest {
    @Test
    fun measuredStepsRemainSavableWhenGpsRouteHasNoPoints() {
        assertTrue(WalkOnSessionRules.hasPersistableActivity(gpsPointCount = 0, measuredSteps = 27L))
    }

    @Test
    fun gpsRouteRemainsSavableWhenStepCounterIsUnavailable() {
        assertTrue(WalkOnSessionRules.hasPersistableActivity(gpsPointCount = 2, measuredSteps = 0L))
    }

    @Test
    fun emptySensorResultIsNotReportedAsACompletedActivity() {
        assertFalse(WalkOnSessionRules.hasPersistableActivity(gpsPointCount = 0, measuredSteps = 0L))
    }
}

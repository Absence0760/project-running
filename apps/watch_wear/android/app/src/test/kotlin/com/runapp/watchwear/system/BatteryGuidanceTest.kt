package com.runapp.watchwear.system

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryGuidanceTest {

    @Test
    fun `samsung is detected case-insensitively and trimmed`() {
        assertTrue(isSamsungOneUiWatch("samsung"))
        assertTrue(isSamsungOneUiWatch("Samsung"))
        assertTrue(isSamsungOneUiWatch("SAMSUNG"))
        assertTrue(isSamsungOneUiWatch("  samsung  "))
    }

    @Test
    fun `non-samsung manufacturers are not flagged`() {
        assertFalse(isSamsungOneUiWatch("Google"))
        assertFalse(isSamsungOneUiWatch("Mobvoi"))
        assertFalse(isSamsungOneUiWatch("Fossil"))
        assertFalse(isSamsungOneUiWatch(""))
        assertFalse(isSamsungOneUiWatch(null))
    }

    @Test
    fun `samsung gets manual guidance, others get the system prompt`() {
        assertEquals(
            BatteryFixStrategy.SamsungManualGuidance,
            batteryFixStrategy("samsung"),
        )
        assertEquals(
            BatteryFixStrategy.SystemPrompt,
            batteryFixStrategy("Google"),
        )
        assertEquals(
            BatteryFixStrategy.SystemPrompt,
            batteryFixStrategy(null),
        )
    }
}

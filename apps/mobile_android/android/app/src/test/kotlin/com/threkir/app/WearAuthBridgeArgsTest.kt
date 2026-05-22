package com.threkir.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/// Pure-JVM unit tests for [parseWearAuthPushArgs] — the strict arg
/// parser for the `/supabase_session` push. Unlike the routes bridge
/// (which has tolerant fallbacks), every field here is load-bearing
/// for the watch to authenticate against Supabase. A missing field
/// is a bug on the Dart side; the parser throws so the bridge can
/// surface a `bad_args` error and the watch never sees a half-formed
/// session DataItem.
class WearAuthBridgeArgsTest {

    private fun validArgs(): Map<String, Any?> = mapOf(
        "access_token" to "eyJ.access.tok",
        "refresh_token" to "eyJ.refresh.tok",
        "user_id" to "user-A",
        "base_url" to "https://example.supabase.co",
        "anon_key" to "eyJ.anon.key",
        "expires_at_ms" to 1_700_000_000_000L,
    )

    @Test
    fun `null args throws WearAuthArgsException`() {
        val ex = assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(null)
        }
        assertTrue(ex.message!!.contains("Map"))
    }

    @Test
    fun `happy path with all six fields parses correctly`() {
        val parsed = parseWearAuthPushArgs(validArgs())
        assertEquals("eyJ.access.tok", parsed.accessToken)
        assertEquals("eyJ.refresh.tok", parsed.refreshToken)
        assertEquals("user-A", parsed.userId)
        assertEquals("https://example.supabase.co", parsed.baseUrl)
        assertEquals("eyJ.anon.key", parsed.anonKey)
        assertEquals(1_700_000_000_000L, parsed.expiresAtMs)
    }

    @Test
    fun `missing access_token throws`() {
        val args = validArgs().toMutableMap().apply { remove("access_token") }
        val ex = assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
        assertTrue(ex.message!!.contains("access_token"))
    }

    @Test
    fun `missing refresh_token throws`() {
        val args = validArgs().toMutableMap().apply { remove("refresh_token") }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `missing user_id throws`() {
        val args = validArgs().toMutableMap().apply { remove("user_id") }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `missing base_url throws`() {
        val args = validArgs().toMutableMap().apply { remove("base_url") }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `missing anon_key throws`() {
        val args = validArgs().toMutableMap().apply { remove("anon_key") }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `missing expires_at_ms throws`() {
        val args = validArgs().toMutableMap().apply { remove("expires_at_ms") }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `wrong-type access_token (int instead of String) throws`() {
        val args = validArgs().toMutableMap().apply { put("access_token", 42) }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `wrong-type expires_at_ms (String instead of Number) throws`() {
        val args = validArgs().toMutableMap()
            .apply { put("expires_at_ms", "not a number") }
        assertThrows(WearAuthArgsException::class.java) {
            parseWearAuthPushArgs(args)
        }
    }

    @Test
    fun `expires_at_ms accepts Int (coerces to Long via Number)`() {
        val args = validArgs().toMutableMap().apply { put("expires_at_ms", 42) }
        val parsed = parseWearAuthPushArgs(args)
        assertEquals(42L, parsed.expiresAtMs)
    }

    @Test
    fun `expires_at_ms accepts Double (coerces via Number)`() {
        // Dart's int can serialise as Double over MethodChannel
        // for very large values. Same defensive coercion the
        // routes bridge does.
        val args = validArgs().toMutableMap()
            .apply { put("expires_at_ms", 1_700_000_000_000.0) }
        val parsed = parseWearAuthPushArgs(args)
        assertEquals(1_700_000_000_000L, parsed.expiresAtMs)
    }

    @Test
    fun `empty-string fields are accepted as valid (Dart contract — '' is a real value for refresh_token)`() {
        // The Dart writer ships `session.refreshToken ?? ''` so an
        // empty string IS legitimately on the wire when the user's
        // refresh token isn't set yet (rare but possible). Don't
        // reject — the watch handles it.
        val args = validArgs().toMutableMap().apply { put("refresh_token", "") }
        val parsed = parseWearAuthPushArgs(args)
        assertEquals("", parsed.refreshToken)
    }

    @Test
    fun `WearAuthPushArgs data-class equality is by-value`() {
        val a = parseWearAuthPushArgs(validArgs())
        val b = parseWearAuthPushArgs(validArgs())
        assertEquals(a, b)
    }

    @Test
    fun `PATH constant matches the watch-side SessionBridge contract`() {
        assertEquals("/supabase_session", WearAuthBridge.PATH)
    }

    @Test
    fun `extra fields ignored — forward-compat with future Dart writer`() {
        val args = validArgs().toMutableMap().apply {
            put("future_field", "something")
            put("another", 42)
        }
        val parsed = parseWearAuthPushArgs(args)
        // Required fields still parse correctly.
        assertEquals("user-A", parsed.userId)
    }
}

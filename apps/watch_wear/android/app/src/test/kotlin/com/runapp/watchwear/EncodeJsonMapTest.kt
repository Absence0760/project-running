package com.runapp.watchwear

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Coverage of `encodeJsonMap` / `encodeJsonValue` — the hand-rolled
/// JSON encoder every Supabase POST flows through. A regression in
/// the encoder (missing string escape, wrong null serialisation,
/// numeric coercion) would break every save silently — PostgREST
/// would either 400 the request or, worse, accept a subtly-wrong
/// shape.
///
/// These tests use the encoder as a public seam — the function was a
/// private method of SupabaseClient until this round; lifted to
/// file-level `internal` for testability.
class EncodeJsonMapTest {

    // ─────────────────── basic shapes ───────────────────

    @Test fun `empty map encodes as empty object`() {
        assertEquals("{}", encodeJsonMap(emptyMap()))
    }

    @Test fun `single key-value encodes correctly`() {
        assertEquals("""{"id":"abc"}""", encodeJsonMap(mapOf("id" to "abc")))
    }

    @Test fun `multiple keys joined with comma in insertion order`() {
        // LinkedHashMap iteration is insertion-ordered, which the
        // builder uses. Pin the order so the wire shape is
        // predictable across runs (handy when grepping fixture
        // diffs).
        val out = encodeJsonMap(linkedMapOf(
            "id" to "abc",
            "duration_s" to 60,
            "distance_m" to 1000.0,
        ))
        assertEquals("""{"id":"abc","duration_s":60,"distance_m":1000.0}""", out)
    }

    // ─────────────────── value types ───────────────────

    @Test fun `null value encoded as literal null`() {
        assertEquals("""{"x":null}""", encodeJsonMap(mapOf("x" to null)))
        assertEquals("null", encodeJsonValue(null))
    }

    @Test fun `Int round-trip preserves type (no decimal)`() {
        assertEquals("60", encodeJsonValue(60))
        assertEquals("""{"n":60}""", encodeJsonMap(mapOf("n" to 60)))
    }

    @Test fun `Long round-trip preserves type (no decimal)`() {
        assertEquals("9999999999", encodeJsonValue(9_999_999_999L))
    }

    @Test fun `Double round-trip preserves decimal`() {
        // PostgREST distinguishes integer columns from float columns
        // by JSON shape. distance_m is double precision; sending
        // "1000" (no decimal) for a Double would be a no-op but is
        // ambiguous. Pin the .0 suffix.
        assertEquals("1000.0", encodeJsonValue(1000.0))
        assertEquals("0.5", encodeJsonValue(0.5))
    }

    @Test fun `Float round-trip preserves decimal`() {
        assertEquals("1.5", encodeJsonValue(1.5f))
    }

    @Test fun `Boolean true and false encoded as literals`() {
        assertEquals("true", encodeJsonValue(true))
        assertEquals("false", encodeJsonValue(false))
        assertEquals("""{"a":true,"b":false}""",
            encodeJsonMap(linkedMapOf("a" to true, "b" to false)))
    }

    // ─────────────────── string escaping ───────────────────

    @Test fun `String with no special chars encoded inside quotes`() {
        assertEquals(""""hello"""", encodeJsonValue("hello"))
    }

    @Test fun `String with embedded double quote is escaped`() {
        // The most common JSON-injection trap — a string containing
        // `"` that's pasted literally would close the JSON early and
        // corrupt the rest of the payload. Pin the escape.
        assertEquals(""""\"hello\""""", encodeJsonValue(""""hello""""))
    }

    @Test fun `String with backslash is escaped`() {
        assertEquals(""""a\\b"""", encodeJsonValue("""a\b"""))
    }

    @Test fun `String with newline is escaped`() {
        assertEquals(""""line1\nline2"""", encodeJsonValue("line1\nline2"))
    }

    @Test fun `String with tab is escaped`() {
        assertEquals(""""a\tb"""", encodeJsonValue("a\tb"))
    }

    @Test fun `Empty string encoded as two quotes`() {
        assertEquals("\"\"", encodeJsonValue(""))
    }

    @Test fun `Unicode chars pass through unescaped (JSON allows literal UTF-8)`() {
        // kotlinx.serialization.JsonPrimitive doesn't escape printable
        // Unicode by default — emoji, accented chars, etc. ride the
        // UTF-8 transport cleanly. Pin the behaviour so a future
        // refactor that flips to \\uXXXX escape doesn't bloat
        // payloads.
        val out = encodeJsonValue("café · 🏃")
        assertEquals(""""café · 🏃"""", out)
    }

    // ─────────────────── JsonElement passthrough ───────────────────

    @Test fun `JsonObject passes through verbatim (no double-encoding)`() {
        // run.metadata is a JsonObject built by buildRunMetadata.
        // It must NOT be wrapped in another set of quotes — that
        // would turn jsonb into a string column server-side.
        val metadata: JsonObject = buildJsonObject {
            put("activity_type", "run")
            put("avg_bpm", 142)
        }
        val encoded = encodeJsonValue(metadata)
        // Not "\"…\"" — bare object literal.
        assertTrue("JsonObject must NOT be quoted as a string. Got: $encoded",
            encoded.startsWith("{") && encoded.endsWith("}"))
        assertTrue(encoded.contains(""""activity_type":"run""""))
        assertTrue(encoded.contains(""""avg_bpm":142"""))
    }

    @Test fun `JsonArray passes through verbatim`() {
        val laps = buildJsonArray {
            add(JsonPrimitive(1))
            add(JsonPrimitive(2))
            add(JsonPrimitive(3))
        }
        val encoded = encodeJsonValue(laps)
        assertEquals("[1,2,3]", encoded)
    }

    @Test fun `JsonPrimitive passes through as its own toString`() {
        assertEquals("\"abc\"", encodeJsonValue(JsonPrimitive("abc")))
        assertEquals("42", encodeJsonValue(JsonPrimitive(42)))
    }

    // ─────────────────── realistic row shape ───────────────────

    @Test fun `realistic runs-row payload round-trips`() {
        // Pin the exact wire format of a typical watch-saved run.
        // If this string changes, every saveRun is suspect.
        val row = linkedMapOf<String, Any?>(
            "id" to "run-abc",
            "user_id" to "u-1",
            "started_at" to "2026-01-01T00:00:00Z",
            "duration_s" to 3600,
            "distance_m" to 10_000.0,
            "source" to "watch",
            "track_url" to "u-1/run-abc.json.gz",
            "metadata" to buildJsonObject { put("activity_type", "run") },
            "external_id" to "run-abc",
            "is_public" to false,
        )
        val out = encodeJsonMap(row)
        // Pin the exact byte sequence — a single character drift
        // here would silently fail every save on a real device.
        assertEquals(
            """{"id":"run-abc","user_id":"u-1","started_at":"2026-01-01T00:00:00Z","duration_s":3600,"distance_m":10000.0,"source":"watch","track_url":"u-1/run-abc.json.gz","metadata":{"activity_type":"run"},"external_id":"run-abc","is_public":false}""",
            out,
        )
    }

    @Test fun `mixed null and non-null values encode side-by-side correctly`() {
        // The `is_public` column is OMITTED when null; but if a caller
        // ever did pass `null` explicitly, the encoder must emit
        // `null` (not skip the key). Pin so the omit-vs-null
        // distinction stays at the row-builder layer, not the
        // encoder.
        val out = encodeJsonMap(linkedMapOf(
            "a" to "x",
            "b" to null,
            "c" to 1,
        ))
        assertEquals("""{"a":"x","b":null,"c":1}""", out)
    }
}

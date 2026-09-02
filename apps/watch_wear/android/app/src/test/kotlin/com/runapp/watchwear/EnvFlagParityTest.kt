package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// The Wear OS build script is a fourth rail of the repo's boolean-flag
/// parser, and nothing connected it to the other three.
///
/// `app/build.gradle.kts` reads `BYPASS_LOGIN`, `DISABLE_HR` and
/// `DISABLE_TTS` out of `.env.development` / `.env.local` at
/// Gradle-configure time and emits them as `BuildConfig` booleans. It used
/// to accept `== "true"` and nothing else, where the canonical parser
/// (`apps/web/src/lib/core/env_flag.ts`, twinned into
/// `apps/mobile_android/lib/env_flag.dart`) accepts `1` / `true` / `yes` /
/// `on`. That is the [decisions.md § 709] defect — one narrow copy among
/// several — and here it fails OPEN rather than closed, because two of the
/// three flags are NEGATIVE: `DISABLE_HR=1` parsed as false, so
/// `ENABLE_HR = !false` left the Wear OS emulator's synthetic heart-rate
/// samples flowing into the runs table, which is the single thing the flag
/// exists to prevent.
///
/// The accepted set is READ OFF the canonical rail rather than restated
/// here. A list written into this file would pin the tokens someone
/// remembered on the day, and web adding a fifth affirmative would leave
/// this rail behind silently — which is how the drift happened in the
/// first place. `build.gradle.kts` is already a declared input of the test
/// task (`guardedBuildScripts`), so an edit to it re-runs this guard
/// instead of leaving `testDebugUnitTest` UP-TO-DATE.
class EnvFlagParityTest {

    private val buildScript: String by lazy {
        val f = WearLocales.findUp("apps/watch_wear/android/app/build.gradle.kts")
            ?: File("app/build.gradle.kts")
        assertTrue("could not locate the Wear OS app build script", f.exists())
        f.readText()
    }

    private val canonical: String by lazy {
        val f = WearLocales.findUp("apps/web/src/lib/core/env_flag.ts")
        assertTrue(
            "could not locate apps/web/src/lib/core/env_flag.ts — the canonical " +
                "rail this guard reads its accepted set from",
            f != null && f.exists(),
        )
        f!!.readText()
    }

    /// The body of a function, from its opening brace to the matching close.
    /// Brace-counting rather than a regex: the bodies contain braces of their
    /// own and a lazy match would stop at the first `}`.
    private fun bodyOf(src: String, signatureStart: String): String {
        val at = src.indexOf(signatureStart)
        assertTrue("no `$signatureStart` in the source", at >= 0)
        val open = src.indexOf('{', at)
        assertTrue("no body for `$signatureStart`", open >= 0)
        var depth = 0
        for (i in open until src.length) {
            when (src[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return src.substring(open + 1, i)
                }
            }
        }
        error("unterminated body for `$signatureStart`")
    }

    private fun quotedTokens(body: String, quote: Char): Set<String> =
        Regex("$quote([^$quote]*)$quote").findAll(body).map { it.groupValues[1] }.toSet()

    @Test
    fun `the build script accepts exactly the canonical affirmative set`() {
        val expected = quotedTokens(bodyOf(canonical, "export function isTruthyFlagValue"), '\'')
        val actual = quotedTokens(bodyOf(buildScript, "fun envFlag("), '"')
        assertEquals(
            "the Wear build script's envFlag must accept exactly what " +
                "apps/web/src/lib/core/env_flag.ts accepts (canonical=$expected, " +
                "build.gradle.kts=$actual). A narrower set fails OPEN here — the " +
                "DISABLE_* flags are negative.",
            expected,
            actual,
        )
        assertTrue(
            "the canonical rail should still declare a non-empty set — an empty " +
                "one would make this comparison vacuous",
            expected.isNotEmpty(),
        )
    }

    @Test
    fun `the build script trims and lowercases before comparing`() {
        // ` yes ` and `On` are the operator-intuition cases the canonical
        // parser's doc comment names explicitly. Without both calls the set
        // above would be right and the behaviour still wrong.
        val body = bodyOf(buildScript, "fun envFlag(")
        assertTrue("envFlag must .trim() the raw value", body.contains(".trim()"))
        assertTrue("envFlag must .lowercase() the raw value", body.contains(".lowercase()"))
    }

    @Test
    fun `every flag the build script reads goes through envFlag`() {
        // A gate that spells the comparison out inline is exactly how § 709
        // happened. There must be no second parse in this file.
        val offenders = Regex("""getProperty\((\w+|"[^"]+")\)""")
            .findAll(buildScript)
            .map { it.value }
            .filter { !it.contains("(key)") }
            .toList()
        assertEquals(
            "every .env read must go through envFlag / envString, not an " +
                "inline getProperty: $offenders",
            emptyList<String>(),
            offenders,
        )
    }

    @Test
    fun `envString falls back when a key is present but empty`() {
        // `APP_RELEASE=` is a key an operator can legitimately leave blank.
        // Returning "" there is not the same as returning the declared
        // default: MainActivity tags any release name that is not "dev" as
        // the Sentry `production` environment.
        val body = bodyOf(buildScript, "fun envString(")
        assertTrue(
            "envString must treat an empty value as absent so `default` " +
                "still applies (got: ${body.trim()})",
            body.contains("isNotEmpty()") || body.contains("isNotBlank()"),
        )
    }
}

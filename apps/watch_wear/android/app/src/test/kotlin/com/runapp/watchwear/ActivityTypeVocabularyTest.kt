package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Guard-rail: the wrist's `activity_type` vocabulary covers every value the
/// `runs_activity_type_check` constraint admits, in every locale.
///
/// The watch is the THIRD platform to carry this vocabulary. Mobile and web
/// each carried partial copies that fell through to a hand-rolled title-caser,
/// which printed English on a localized screen; both were resolved to one
/// shared helper guarded by `activity_type_vocabulary_test.dart` and
/// `activity_type_vocabulary.test.ts`. The wrist kept a fourth copy covering
/// four of five values, and `stroller` reaches it without ever being cycled:
/// `default_activity_type` primes the pre-run chip straight off the phone's
/// settings bag with no allowlist.
///
/// The value set is read out of the migration rather than restated here, so a
/// migration that widens the CHECK fails this file until the wrist catches up.
class ActivityTypeVocabularyTest {

    /// The six locales the Wear OS resource set ships. Fewer than mobile's
    /// seven: the wrist has no plain `pt` catalogue, only `pt-BR`.
    private val localeDirs = listOf(
        "values",
        "values-de",
        "values-es",
        "values-fr",
        "values-ja",
        "values-b+pt+BR",
    )

    @Test
    fun `every activity_type CHECK value carries a non-empty label in every locale`() {
        val values = checkValues()
        assertTrue("parsed an EMPTY value set out of the CHECK constraint", values.isNotEmpty())

        val res = findUp("apps/watch_wear/android/app/src/main/res")
            ?: findUp("app/src/main/res")
        assertTrue("could not locate the Wear OS resource set", res != null)

        var checked = 0
        for (dir in localeDirs) {
            val xml = File(res!!, "$dir/strings.xml")
            assertTrue("missing locale catalogue $dir/strings.xml", xml.exists())
            val text = xml.readText()
            val seen = mutableMapOf<String, String>()
            for (value in values) {
                val label = stringValue(text, "activity_$value")
                assertTrue(
                    "$dir has no non-empty label for activity_type \"$value\" " +
                        "(activity_$value). A missing key is a runtime English leak.",
                    label != null && label.isNotBlank(),
                )
                val clash = seen[label]
                assertEquals(
                    "$dir labels both \"$clash\" and \"$value\" as \"$label\"",
                    null,
                    clash,
                )
                seen[label!!] = value
                checked++
            }
        }
        // Assert the population, not only the property — a value that reached
        // no catalogue at all would satisfy every assertion above.
        assertEquals(
            "checked $checked labels",
            localeDirs.size * values.size,
            checked,
        )
    }

    @Test
    fun `the label resolver maps every CHECK value and capitalizes nothing`() {
        val src = findUp("apps/watch_wear/android/app/src/main/kotlin")
            ?: findUp("app/src/main/kotlin")
        assertTrue("could not locate the Wear OS main source set", src != null)

        val renderers = src!!.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filter { it.readText().contains("R.string.activity_run") }
            .toList()
        assertEquals(
            "expected exactly one activity-label resolver, found " +
                renderers.map { it.name },
            1,
            renderers.size,
        )

        val text = renderers.single().readText()
        for (value in checkValues()) {
            assertTrue(
                "the activity-label resolver has no branch for \"$value\" — an " +
                    "unmapped value falls through to the raw database token.",
                text.contains("R.string.activity_$value"),
            )
        }

        // Capitalizing a database token produces a word indistinguishable from
        // a real translation, which is how the English leak went unnoticed on
        // three platforms. Matched by shape so a rename cannot dodge it.
        val capitalizeIdiom = Regex("""replaceFirstChar\s*\{[^}]*uppercase\(\)""")
        assertTrue(
            "a resolver capitalizes a raw activity token instead of resolving " +
                "a label. Add the string resource; do not title-case the value.",
            !capitalizeIdiom.containsMatchIn(text),
        )
    }

    /// The authoritative value set, parsed from the migration that declares
    /// `runs_activity_type_check`. Same source the Dart and TypeScript guards
    /// read, so the three cannot disagree about what the column admits.
    private fun checkValues(): List<String> {
        val dir = findUp("apps/backend/supabase/migrations")
        assertTrue("could not locate apps/backend/supabase/migrations", dir != null)
        val re = Regex(
            """constraint\s+runs_activity_type_check\s*\n?\s*check\s*\(\s*activity_type\s+in\s*\(([^)]*)\)""",
            RegexOption.IGNORE_CASE,
        )
        var found: List<String>? = null
        dir!!.listFiles { f: File -> f.extension == "sql" }
            ?.sortedBy { it.name }
            ?.forEach { f ->
                val m = re.find(f.readText()) ?: return@forEach
                // A later migration replacing the constraint wins.
                found = Regex("""'([^']+)'""").findAll(m.groupValues[1])
                    .map { it.groupValues[1] }
                    .toList()
            }
        assertTrue("no migration declares runs_activity_type_check", found != null)
        return found!!
    }

    /// The text of `<string name="...">...</string>`, or null when absent.
    private fun stringValue(xml: String, name: String): String? =
        Regex("""<string name="${Regex.escape(name)}">(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)
            .find(xml)
            ?.groupValues
            ?.get(1)

    private fun findUp(rel: String): File? {
        var dir: File? = File(".").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        return null
    }
}

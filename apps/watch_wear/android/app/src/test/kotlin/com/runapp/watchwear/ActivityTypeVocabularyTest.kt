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

    private data class Catalogues(val arb: String, val web: String)

    /// The six locales the Wear OS resource set ships, each paired with the
    /// phone and web catalogue it answers for. Fewer than mobile's seven: the
    /// wrist has no plain `pt` catalogue, only `pt-BR`.
    private val localeCatalogues = linkedMapOf(
        "values" to Catalogues("app_en.arb", "en.ts"),
        "values-de" to Catalogues("app_de.arb", "de.ts"),
        "values-es" to Catalogues("app_es.arb", "es.ts"),
        "values-fr" to Catalogues("app_fr.arb", "fr.ts"),
        "values-ja" to Catalogues("app_ja.arb", "ja.ts"),
        "values-b+pt+BR" to Catalogues("app_pt_BR.arb", "pt-BR.ts"),
    )

    private val localeDirs: List<String> get() = localeCatalogues.keys.toList()

    /// The phone catalogue the wrist deliberately does not mirror: European
    /// Portuguese. Web is short the same one, so a pt-PT reader falls back on
    /// both — recorded rather than silently absent.
    private val unmirroredPhoneCatalogues = setOf("app_pt.arb")

    /// `hike` reads "Trail run" on web and mobile since decisions § 547 and
    /// still "Hike" on the wrist. That is a product RENAME, not a translation
    /// fix, so it is exempt from the comparison below until the owner calls it
    /// rather than being steamrollered — see `docs/product/followups.md`.
    private val renameAwaitingOwner = setOf("hike")

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

    @Test
    fun `every activity word is the phone's word and the web's, locale for locale`() {
        val values = checkValues().filter { it !in renameAwaitingOwner }
        assertTrue("the exemption swallowed the whole vocabulary", values.isNotEmpty())

        val res = resourceSet()
        val l10n = findUp("apps/mobile_android/lib/l10n")
        assertTrue("could not locate apps/mobile_android/lib/l10n", l10n != null)
        val web = findUp("apps/web/src/lib/i18n/locales")
        assertTrue("could not locate apps/web/src/lib/i18n/locales", web != null)

        var compared = 0
        for ((dir, cat) in localeCatalogues) {
            val wristXml = File(res, "$dir/strings.xml").readText()
            val arb = File(l10n!!, cat.arb)
            val ts = File(web!!, cat.web)
            assertTrue("missing phone catalogue ${arb.path}", arb.exists())
            assertTrue("missing web catalogue ${ts.path}", ts.exists())
            val arbText = arb.readText()
            val tsText = ts.readText()
            for (value in values) {
                val wrist = wristLabel(wristXml, value)
                val phone = arbValue(arbText, arbKey(value))
                val site = webValue(tsText, "activityType.$value")
                assertTrue("${cat.arb} has no label for \"$value\"", phone != null)
                assertTrue("${cat.web} has no label for \"$value\"", site != null)
                assertEquals(
                    "${cat.arb} says \"$phone\" for \"$value\" where ${cat.web} says " +
                        "\"$site\". The phone and the web are one vocabulary; the wrist " +
                        "cannot follow both.",
                    phone,
                    site,
                )
                assertEquals(
                    "$dir/activity_$value is \"$wrist\" where the phone and the web say " +
                        "\"$phone\". One product, one word for one activity — the wrist " +
                        "takes theirs. Shortening for the 56 dp chip is not a reason: its " +
                        "32 dp label box ellipsises this vocabulary in every locale either " +
                        "way (decisions § 713).",
                    phone,
                    wrist,
                )
                compared++
            }
        }
        assertEquals(
            "compared $compared labels",
            localeCatalogues.size * values.size,
            compared,
        )
    }

    @Test
    fun `the hike rename is the only exemption, and it is still open`() {
        val values = checkValues().toSet()
        assertEquals(
            "an exemption names a value the CHECK constraint does not admit, which " +
                "silently drops nothing and hides a typo",
            emptySet<String>(),
            renameAwaitingOwner - values,
        )

        val res = resourceSet()
        val l10n = findUp("apps/mobile_android/lib/l10n")
        assertTrue("could not locate apps/mobile_android/lib/l10n", l10n != null)
        for (value in renameAwaitingOwner) {
            val diverges = localeCatalogues.any { (dir, cat) ->
                val wrist = wristLabel(File(res, "$dir/strings.xml").readText(), value)
                wrist != arbValue(File(l10n!!, cat.arb).readText(), arbKey(value))
            }
            assertTrue(
                "\"$value\" is exempt from the vocabulary comparison, but the wrist " +
                    "already says what the phone says in every locale. The rename " +
                    "landed — drop it from renameAwaitingOwner and close the box in " +
                    "docs/product/followups.md.",
                diverges,
            )
        }
    }

    @Test
    fun `the wrist covers every phone locale except the recorded gap`() {
        val l10n = findUp("apps/mobile_android/lib/l10n")
        assertTrue("could not locate apps/mobile_android/lib/l10n", l10n != null)
        val shipped = l10n!!.listFiles { f: File -> f.extension == "arb" }
            ?.map { it.name }
            ?.toSet()
            .orEmpty()
        assertTrue("found no ARB catalogues at all", shipped.isNotEmpty())

        val mirrored = localeCatalogues.values.map { it.arb }.toSet()
        assertEquals(
            "the wrist mirrors a phone catalogue that no longer exists",
            emptySet<String>(),
            mirrored - shipped,
        )
        assertEquals(
            "the phone ships a locale the wrist has no values-* directory for. Add " +
                "the Wear catalogue, or record the gap in unmirroredPhoneCatalogues " +
                "and in docs/product/parity.md.",
            unmirroredPhoneCatalogues,
            shipped - mirrored,
        )
    }

    private fun resourceSet(): File {
        val res = findUp("apps/watch_wear/android/app/src/main/res")
            ?: findUp("app/src/main/res")
        assertTrue("could not locate the Wear OS resource set", res != null)
        return res!!
    }

    private fun arbKey(value: String): String =
        "activityType" + value.replaceFirstChar { it.uppercase() }

    /// A Wear label with aapt's backslash escapes undone, so a French `L\'`
    /// compares against the phone's plain apostrophe rather than against the
    /// escape aapt needs.
    private fun wristLabel(xml: String, value: String): String? =
        stringValue(xml, "activity_$value")?.replace("\\", "")

    private fun arbValue(json: String, key: String): String? =
        Regex("\"" + Regex.escape(key) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
            .find(json)?.groupValues?.get(1)?.replace("\\", "")

    private fun webValue(ts: String, key: String): String? =
        Regex("'" + Regex.escape(key) + "'\\s*:\\s*'((?:[^'\\\\]|\\\\.)*)'")
            .find(ts)?.groupValues?.get(1)?.replace("\\", "")

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

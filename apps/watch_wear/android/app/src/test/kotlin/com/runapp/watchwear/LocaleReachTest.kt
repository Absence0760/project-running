package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Every site that declares which locales the wrist ships, held to the
/// `values-*` directories that actually carry a `strings.xml`.
///
/// The wrist had the seam the phone closed in decisions § 740: the resource
/// set, `locales_config.xml`, and two test-side locale lists each enumerated
/// the same six by hand, with nothing connecting any of them to disk. A
/// seventh string set therefore shipped in the APK unlisted in the OS
/// language picker and unchecked for missing keys, and nothing failed.
class LocaleReachTest {

    private val androidRoot: File by lazy {
        WearLocales.findUp("apps/watch_wear/android")
            ?: WearLocales.findUp("app/build.gradle.kts")?.parentFile?.parentFile
            ?: error("could not locate the Wear OS Android project root")
    }

    @Test
    fun `the resource set ships translated locales at all`() {
        // Assert the population, not only the property: every comparison
        // below is vacuously true against an empty derived set.
        assertTrue(
            "found no values-*/strings.xml at all — did the resource set move?",
            WearLocales.translatedDirs().size >= 5,
        )
    }

    @Test
    fun `every values directory carrying strings is a locale this guard reads`() {
        assertEquals(
            "a values-* directory ships a strings.xml under a qualifier this " +
                "guard does not recognise as a locale, so every check below " +
                "skips it. If it is a locale, teach WearLocales the qualifier " +
                "form; if it is not (a Wear screen-shape or UI-mode directory " +
                "holding a shorter string), record why it is exempt here.",
            emptyList<String>(),
            WearLocales.qualifiedStringsDirs().second,
        )
    }

    @Test
    fun `the default resource language is not also a translated directory`() {
        assertTrue(
            "values-${WearLocales.DEFAULT_TAG}/ exists, so ${WearLocales.DEFAULT_TAG} " +
                "is a translated set rather than the language values/ is written " +
                "in — DEFAULT_TAG is now wrong.",
            WearLocales.DEFAULT_TAG !in WearLocales.translatedDirs().map { WearLocales.tagOf(it) },
        )
    }

    @Test
    fun `locales_config advertises exactly the locales on disk`() {
        val config = File(WearLocales.resDir(), "xml/locales_config.xml").readText()
        val declared = Regex("""android:name="([\w+-]+)"""")
            .findAll(config)
            .map { it.groupValues[1] }
            .toSet()
        assertEquals(
            "locales_config.xml and the values-* directories disagree about " +
                "which locales ship. Android 13+ reads this file to populate " +
                "Settings -> Apps -> Threkir -> Language, so a string set missing " +
                "from it is one no reader can ask for; an entry with no string " +
                "set offers a language that resolves to English.",
            WearLocales.tags(),
            declared,
        )
    }

    @Test
    fun `the manifest references the locale config`() {
        val manifest = File(androidRoot, "app/src/main/AndroidManifest.xml").readText()
        assertTrue(
            "<application> must set android:localeConfig=\"@xml/locales_config\". " +
                "Without the reference the file is inert and the per-app language " +
                "picker never lists this app, however complete the string sets.",
            manifest.contains("""android:localeConfig="@xml/locales_config""""),
        )
    }

    @Test
    fun `no build script filters the shipped locales`() {
        val offenders = androidRoot.walkTopDown()
            .filter { it.isFile && (it.name.endsWith(".gradle.kts") || it.name.endsWith(".gradle")) }
            .filter { !it.path.contains("${File.separator}build${File.separator}") }
            .filter { Regex("""resConfig|localeFilter""").containsMatchIn(it.readText()) }
            .map { it.relativeTo(androidRoot).path }
            .toList()
        assertEquals(
            "a build script declares a locale filter, which strips string sets " +
                "out of the APK after every check in this file has passed them. " +
                "Hold it to WearLocales.tags() here before shipping it.",
            emptyList<String>(),
            offenders,
        )
    }

    @Test
    fun `a test that names a shipped locale directory is anchored to the derivation`() {
        val dirs = WearLocales.translatedDirs()
        val offenders = File(androidRoot, "app/src/test/kotlin").walkTopDown()
            .filter { it.isFile && it.extension == "kt" && it.name != "WearLocales.kt" }
            .filter { f ->
                val text = f.readText()
                dirs.any { text.contains(it) } && !text.contains("WearLocales")
            }
            .map { it.name }
            .toList()
        assertEquals(
            "this file spells a values-* locale directory out and reads nothing " +
                "off disk, so it agrees with the resource set only until someone " +
                "adds a locale. Derive the set from WearLocales, or hold the " +
                "hand-written table's keys to it.",
            emptyList<String>(),
            offenders,
        )
    }
}

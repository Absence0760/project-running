package com.runapp.watchwear

import java.io.File
import java.util.Locale

/// The locales the Wear OS app actually ships, read off the resource
/// directory instead of listed.
///
/// A `values-xx/strings.xml` that no declaration site names still ships in
/// the APK: it costs bytes in every build, `locales_config.xml` never offers
/// it in Settings, and no parity test checks its keys. Nothing in this module
/// connected "the string set exists on disk" to "every site that declares the
/// locale set knows about it" — the same seam decisions § 740 closed on the
/// phone, where a catalogue shipped dark twice.
object WearLocales {

    /// The language `res/values/strings.xml` is written in. This is the one
    /// fact no file on disk states, so it is declared here rather than
    /// derived; `LocaleReachTest` asserts it is not also a translated
    /// directory.
    const val DEFAULT_TAG = "en"

    private val ISO_LANGUAGES = Locale.getISOLanguages().toSet()

    /// `b+pt+BR` — the BCP-47 qualifier form. Region may also be a UN M.49
    /// numeric code, and a script subtag may sit between the two.
    private val BCP47 = Regex("""^b\+([a-z]{2,3})(?:\+([A-Z][a-z]{3}))?(?:\+([A-Z]{2}|\d{3}))?$""")

    /// `pt-rBR` — the legacy qualifier form. Restricted to ISO 639-1 so a
    /// non-locale qualifier of the same shape (`values-car`, a UI-mode
    /// directory) is reported rather than read as a language.
    private val LEGACY = Regex("""^([a-z]{2})(?:-r([A-Z]{2}|\d{3}))?$""")

    fun resDir(): File = findUp("apps/watch_wear/android/app/src/main/res")
        ?: findUp("app/src/main/res")
        ?: error("could not locate the Wear OS resource set")

    /// Every `values-*` directory carrying a `strings.xml`, split into the
    /// ones whose qualifier is a locale and the ones it is not. An
    /// unrecognised directory is returned rather than dropped — silently
    /// skipping one would reintroduce exactly the gap this object exists to
    /// close.
    fun qualifiedStringsDirs(): Pair<List<String>, List<String>> {
        val dirs = resDir().listFiles { f: File -> f.isDirectory }
            .orEmpty()
            .map { it.name }
            .filter { it.startsWith("values-") }
            .filter { File(resDir(), "$it/strings.xml").exists() }
            .sorted()
        return dirs.partition { tagOrNull(it) != null }
    }

    /// The translated directories, default set excluded.
    fun translatedDirs(): List<String> = qualifiedStringsDirs().first

    /// The default set first, then every translated directory.
    fun allDirs(): List<String> = listOf("values") + translatedDirs()

    /// Every locale the resource set ships, as the BCP-47 tags
    /// `locales_config.xml` spells them.
    fun tags(): Set<String> =
        (listOf(DEFAULT_TAG) + translatedDirs().map { tagOf(it) }).toSet()

    fun tagOf(dir: String): String =
        tagOrNull(dir) ?: error("$dir is not a locale-qualified directory")

    fun tagOrNull(dir: String): String? {
        val qualifier = dir.removePrefix("values-")
        BCP47.matchEntire(qualifier)?.let { m ->
            val (language, script, region) = m.destructured
            if (language.length == 2 && language !in ISO_LANGUAGES) return null
            return listOf(language, script, region).filter { it.isNotEmpty() }.joinToString("-")
        }
        LEGACY.matchEntire(qualifier)?.let { m ->
            val (language, region) = m.destructured
            if (language !in ISO_LANGUAGES) return null
            return if (region.isEmpty()) language else "$language-$region"
        }
        return null
    }

    fun findUp(rel: String): File? {
        var dir: File? = File(".").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        return null
    }
}

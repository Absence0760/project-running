package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/// Guard-rail: every `runs.metadata` key referenced in the Wear OS sources
/// must be registered in `docs/backend/metadata.md`.
///
/// `runs.metadata` is a jsonb bag with no type-level protection. Cross-client
/// drift (this watch writes `activity_type`, web reads `activityType`) is the
/// exact failure mode the registry was created to prevent. The Dart twin of
/// this guard is `apps/mobile_android/test/metadata_registry_test.dart`; the
/// TypeScript and Swift twins live under `apps/web/` and `apps/watch_ios/`.
/// Each scans its own platform's sources against the one shared registry.
class MetadataRegistryTest {

    /// Keys the guard should ignore because the match is a real `metadata`
    /// identifier that is not `runs.metadata`. Keep empty until a genuine
    /// spurious match appears, and always record the reason beside the entry.
    private val exemptReferences = emptySet<String>()

    @Test
    fun `every runs metadata key in Kotlin source is registered in docs backend metadata md`() {
        val doc = findUp("docs/backend/metadata.md")
        assertTrue("could not locate docs/backend/metadata.md from ${File(".").absolutePath}", doc != null)
        val registry = parseRegistry(doc!!.readText())
        assertTrue("parsed an empty registry — the markdown table shape changed", registry.isNotEmpty())

        val root = listOf(
            "src/main/kotlin",
            "app/src/main/kotlin",
            "apps/watch_wear/android/app/src/main/kotlin",
        ).firstNotNullOfOrNull { findUp(it) }
        assertTrue("could not locate the Wear OS main source set", root != null)

        val referenced = mutableMapOf<String, MutableSet<String>>()
        root!!.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filterNot { it.path.contains("/generated/") }
            .forEach { file ->
                for (key in extractMetadataKeys(stripComments(file.readText()))) {
                    referenced.getOrPut(key) { mutableSetOf() }.add(file.path)
                }
            }

        // A scan that finds nothing is a broken scan, not a clean tree: the
        // watch's own run-metadata builder is always in range.
        assertTrue(
            "found no runs.metadata key references at all — the scan is not reaching the sources",
            referenced.isNotEmpty(),
        )

        val unknown = referenced.keys.filterNot { it in registry || it in exemptReferences }.sorted()
        assertEquals(
            buildString {
                append("Unregistered runs.metadata key(s) referenced in Kotlin source:\n")
                for (key in unknown) {
                    append("  $key\n")
                    referenced[key]!!.sorted().forEach { append("      at $it\n") }
                }
                append("\nEither:\n")
                append("  1) Register the key in docs/backend/metadata.md (preferred) — snake_case, ")
                append("shape, writers, readers, public_runs safety.\n")
                append("  2) If the match is spurious (a `metadata` identifier that is not ")
                append("runs.metadata), add the key to exemptReferences in this test with a reason.\n\n")
                append("Drift in runs.metadata is invisible to the DB type system — this registry ")
                append("IS the coordination point across web, mobile, watch_wear, and watch_ios.")
            },
            emptyList<String>(),
            unknown,
        )
    }

    /// Nearest ancestor of the working directory containing [rel].
    private fun findUp(rel: String): File? {
        var dir: File? = File(".").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        return null
    }

    /// Registered key names from the markdown registry: each table row opens
    /// `| \`key\` |`. Same parse as the Dart guard, so the two can't disagree
    /// about what "registered" means.
    private fun parseRegistry(doc: String): Set<String> =
        Regex("""^\|\s*`([a-z_][a-z0-9_]*)`\s*\|""", RegexOption.MULTILINE)
            .findAll(doc)
            .map { it.groupValues[1] }
            .toSet()

    /// Blank `//` and block comments, leaving offsets intact. String literals
    /// are walked over rather than blanked, so a `"//"` inside a string can't
    /// be mistaken for a comment and swallow the rest of the line.
    private fun stripComments(source: String): String {
        val out = source.toCharArray()
        var i = 0
        while (i < source.length) {
            when {
                source[i] == '"' -> {
                    i++
                    while (i < source.length) {
                        if (source[i] == '\\') i++ else if (source[i] == '"') break
                        i++
                    }
                    i++
                }
                source.startsWith("//", i) -> {
                    while (i < source.length && source[i] != '\n') out[i++] = ' '
                }
                source.startsWith("/*", i) -> {
                    val end = source.indexOf("*/", i + 2)
                    val stop = if (end == -1) source.length else end + 2
                    while (i < stop) {
                        if (out[i] != '\n') out[i] = ' '
                        i++
                    }
                }
                else -> i++
            }
        }
        return String(out)
    }

    /// Every `runs.metadata` key reference in one comment-stripped file:
    ///
    ///   * subscript reads: `metadata["x"]`, `metadata!!["x"]`, `metadata?.get("x")`
    ///   * builder bodies: an identifier ending in `metadata` (`buildRunMetadata`,
    ///     `val metadata`) followed by `buildJsonObject { … }`, whose DEPTH-1
    ///     `put("x", …)` calls are the keys. Depth matters: the nested
    ///     `buildJsonArray`/`addJsonObject` inside `put("laps", …)` carries the
    ///     per-lap field names, which belong to the `laps` shape and are not
    ///     metadata keys of their own.
    private fun extractMetadataKeys(source: String): Set<String> {
        val keys = mutableSetOf<String>()

        SUBSCRIPT.findAll(source).forEach { keys.add(it.groupValues[1]) }

        for (m in BUILD_JSON_OBJECT.findAll(source)) {
            // Walk back over the declaration that owns this builder. It is a
            // metadata builder when the nearest identifier behind it ends in
            // `metadata` with no brace in between (so `fun buildRunMetadata(
            // … ): JsonObject = buildJsonObject {`, spanning lines, matches,
            // while an unrelated builder further down the file does not).
            val from = maxOf(0, m.range.first - DECLARATION_WINDOW)
            val window = source.substring(from, m.range.first)
            val name = METADATA_IDENTIFIER.findAll(window).lastOrNull() ?: continue
            val between = window.substring(name.range.last + 1)
            if (between.contains('{') || between.contains('}')) continue
            keys.addAll(depthOnePutKeys(source, m.range.last))
        }
        return keys
    }

    /// Keys of the `put("x", …)` calls at depth 1 of the brace block opened at
    /// [open].
    private fun depthOnePutKeys(source: String, open: Int): Set<String> {
        val keys = mutableSetOf<String>()
        var depth = 1
        var i = open + 1
        while (i < source.length && depth > 0) {
            when (source[i]) {
                '{' -> depth++
                '}' -> depth--
                '"' -> {
                    i++
                    while (i < source.length) {
                        if (source[i] == '\\') i++ else if (source[i] == '"') break
                        i++
                    }
                }
            }
            if (depth == 1) {
                PUT_CALL.matchAt(source, i)?.let { keys.add(it.groupValues[1]) }
            }
            i++
        }
        return keys
    }

    private companion object {
        const val DECLARATION_WINDOW = 400

        val SUBSCRIPT = Regex(
            """(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Mm]etadata\s*(?:!!|\?)?\s*(?:\[|\.\s*get(?:Value)?\s*\()\s*"([a-z_][a-z0-9_]*)"""",
        )
        val BUILD_JSON_OBJECT = Regex("""buildJsonObject\s*\{""")
        val METADATA_IDENTIFIER = Regex("""[A-Za-z0-9_]*[Mm]etadata\b""")
        val PUT_CALL = Regex("""put\s*\(\s*"([a-z_][a-z0-9_]*)"""")
    }
}

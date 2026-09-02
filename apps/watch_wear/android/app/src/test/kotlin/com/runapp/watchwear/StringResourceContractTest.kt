package com.runapp.watchwear

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// Contracts over the string catalogue itself, one level below
/// `L10nResourceParityTest`. That one asks whether every locale agrees with
/// the default set; these two ask whether the default set is the right set.
///
/// **Unit pairing.** Every distance and pace read-out on the wrist is chosen
/// by `DistanceUnit`, so each unit-bearing string exists twice — a `km` key
/// and an `mi` key — and the composable dispatches between them. Except one
/// did not: `distance_km_recorded` had no mile sibling, so the crash-recovery
/// prompt (the screen where a runner decides whether a surviving checkpoint is
/// the run they care about) told a miles runner "6.44 km recorded". The
/// screen it sits on, `PreRunScreen`, was the only screen never handed
/// `preferredUnit`, so there was nothing to dispatch on and the km string was
/// the only one there was. Nothing could see it: the key was present in all
/// seven catalogues, so the parity guard was satisfied, and the value was in
/// the right language in each.
///
/// **Dead keys.** Three keys — `tile_stat_row`, `pace_placeholder`,
/// `pace_per_km_compact` — were declared in all seven catalogues and
/// referenced from nowhere; the tile had moved to building those strings in
/// Kotlin. Translators maintained 21 dead entries, and two of them hardcoded
/// `/km`, so a future call site wiring up `pace_placeholder` would have
/// inherited the same defect from a string that looked already-translated.
class StringResourceContractTest {

    private val resDir = WearLocales.resDir()

    private val defaultKeys: Set<String> by lazy {
        Regex("""<(?:string|plurals)\s+name="([^"]+)"""")
            .findAll(File(resDir, "values/strings.xml").readText())
            .map { it.groupValues[1] }
            .toSet()
    }

    /// Every place a resource can be named: Kotlin (`R.string.x`) and the
    /// XML/manifest surfaces (`@string/x`).
    private val referenceSites: String by lazy {
        val main = File(resDir.parentFile, "kotlin")
        val xml = listOf(
            File(resDir.parentFile, "AndroidManifest.xml"),
            File(resDir, "xml"),
            File(resDir, "drawable"),
        )
        buildString {
            main.walkTopDown().filter { it.isFile && it.extension == "kt" }
                .forEach { append(it.readText()) }
            xml.forEach { f ->
                if (f.isDirectory) {
                    f.walkTopDown().filter { it.isFile }.forEach { append(it.readText()) }
                } else if (f.isFile) {
                    append(f.readText())
                }
            }
        }
    }

    private fun isReferenced(key: String): Boolean =
        Regex("""R\.(?:string|plurals)\.$key\b""").containsMatchIn(referenceSites) ||
            Regex("""@(?:string|plurals)/$key\b""").containsMatchIn(referenceSites)

    /// `distance_km_to_go` → `distance_mi_to_go`. Segment-wise rather than a
    /// suffix swap, because the unit is not always the last word.
    private fun swapUnit(key: String): String? {
        val parts = key.split('_')
        val at = parts.indexOfFirst { it == "km" || it == "mi" }
        if (at < 0) return null
        return parts.toMutableList().also {
            it[at] = if (it[at] == "km") "mi" else "km"
        }.joinToString("_")
    }

    @Test
    fun `the guard can read the catalogue and the call sites`() {
        // Both halves below are "this set minus that set is empty", which an
        // empty read satisfies as happily as a correct one.
        assertTrue("no keys parsed out of values/strings.xml", defaultKeys.size >= 50)
        assertTrue(
            "no reference sites read — every usage check below would pass vacuously",
            referenceSites.length > 10_000,
        )
        assertTrue(
            "a key known to be referenced must read as referenced",
            isReferenced("distance_km"),
        )
        assertTrue(
            "a key that does not exist must NOT read as referenced",
            !isReferenced("a_key_no_call_site_names"),
        )
    }

    @Test
    fun `every unit-bearing string comes in a km and mi pair`() {
        val unpaired = defaultKeys.mapNotNull { key ->
            val sibling = swapUnit(key) ?: return@mapNotNull null
            if (sibling in defaultKeys) null else "$key (expected $sibling)"
        }.sorted()
        assertEquals(
            "a unit-bearing string with no sibling in the other unit: " +
                "$unpaired. The call site can only dispatch on DistanceUnit " +
                "if both halves exist; with one half it renders the wrong " +
                "unit to half the runners and every locale looks correct.",
            emptyList<String>(),
            unpaired,
        )
    }

    @Test
    fun `both halves of a unit pair are wired, not just the km one`() {
        // A pair can exist in the catalogue and still be half-wired — which
        // is indistinguishable, from the resource files, from the bug this
        // whole class is about.
        val halfWired = defaultKeys.mapNotNull { key ->
            val sibling = swapUnit(key) ?: return@mapNotNull null
            if (sibling !in defaultKeys) return@mapNotNull null
            if (isReferenced(key) == isReferenced(sibling)) null else "$key / $sibling"
        }.sorted()
        assertEquals(
            "one half of a unit pair is referenced and the other is not: " +
                "$halfWired. Dispatch on DistanceUnit names both.",
            emptyList<String>(),
            halfWired,
        )
    }

    @Test
    fun `no string is declared in seven catalogues and used in none`() {
        val orphans = defaultKeys.filterNot { isReferenced(it) }.sorted()
        assertEquals(
            "declared in values/strings.xml (and translated into every locale) " +
                "but named by no call site: $orphans. Delete it — a dead " +
                "string costs seven translations and, when it carries a unit " +
                "or a format, hands the next call site a defect that looks " +
                "already-reviewed.",
            emptyList<String>(),
            orphans,
        )
    }
}

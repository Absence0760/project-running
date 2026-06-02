package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

/// Wear-OS analogue of the mobile `l10n_parity_test`: every translated
/// `values-xx/strings.xml` must declare exactly the same set of `name=` keys
/// (across both `<string>` and `<plurals>`) as the default English set, with
/// no empty values. A missing key would crash at runtime with
/// `Resources.NotFoundException` only on a device set to that locale —
/// invisible to a developer running in English. This test fails the build
/// instead.
class L10nResourceParityTest {

    private val resDir = File("src/main/res")

    /// Default English set + the five translation dirs. pt-BR uses the
    /// BCP-47 `b+pt+BR` qualifier.
    private val localeDirs = listOf(
        "values-de",
        "values-fr",
        "values-es",
        "values-ja",
        "values-b+pt+BR",
    )

    private fun stringsFile(dir: String): File = File(resDir, "$dir/strings.xml")

    /// Map of name → list of non-empty text values declared under it. For a
    /// `<string>` that's a single value; for `<plurals>` it's one per
    /// `<item>`.
    private fun parse(file: File): Map<String, List<String>> {
        val doc = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = false
        }.newDocumentBuilder().parse(file)
        val out = linkedMapOf<String, List<String>>()

        val strings = doc.getElementsByTagName("string")
        for (i in 0 until strings.length) {
            val el = strings.item(i) as Element
            out[el.getAttribute("name")] = listOf(el.textContent)
        }
        val plurals = doc.getElementsByTagName("plurals")
        for (i in 0 until plurals.length) {
            val el = plurals.item(i) as Element
            val items = el.getElementsByTagName("item")
            val values = (0 until items.length).map { items.item(it).textContent }
            out[el.getAttribute("name")] = values
        }
        return out
    }

    @Test
    fun `default strings file exists and is non-empty`() {
        val def = stringsFile("values")
        assertTrue("Missing ${def.path}", def.exists())
        assertTrue("Default strings.xml declares no keys", parse(def).isNotEmpty())
    }

    @Test
    fun `every locale declares exactly the default key set`() {
        val defaultKeys = parse(stringsFile("values")).keys
        for (dir in localeDirs) {
            val file = stringsFile(dir)
            assertTrue("Missing translation file ${file.path}", file.exists())
            val keys = parse(file).keys

            val missing = defaultKeys - keys
            val extra = keys - defaultKeys
            assertEquals(
                "$dir is missing keys vs the default set: $missing",
                emptySet<String>(),
                missing,
            )
            assertEquals(
                "$dir has keys absent from the default set: $extra",
                emptySet<String>(),
                extra,
            )
        }
    }

    @Test
    fun `no locale has an empty translated value`() {
        for (dir in (listOf("values") + localeDirs)) {
            val parsed = parse(stringsFile(dir))
            for ((name, values) in parsed) {
                for (v in values) {
                    assertTrue(
                        "$dir/$name has an empty value",
                        v.isNotBlank(),
                    )
                }
            }
        }
    }

    @Test
    fun `placeholder arg positions match the default for every locale`() {
        // A translation that drops or renumbers a %1$s / %2$d arg would
        // throw IllegalFormatException at runtime on that locale. Pin that
        // each translated value uses the same set of positional args as the
        // English original (order may differ — e.g. Japanese run-complete
        // swaps distance and minutes — so we compare the *set*, not the
        // sequence).
        val argRegex = Regex("%\\d+\\$[sdf]")
        val default = parse(stringsFile("values"))
        for (dir in localeDirs) {
            val parsed = parse(stringsFile(dir))
            for ((name, defValues) in default) {
                val defArgs = defValues.flatMap { argRegex.findAll(it).map { m -> m.value } }.toSet()
                val locValues = parsed[name] ?: continue
                val locArgs = locValues.flatMap { argRegex.findAll(it).map { m -> m.value } }.toSet()
                assertEquals(
                    "$dir/$name uses different format args than the default " +
                        "(default=$defArgs, $dir=$locArgs)",
                    defArgs,
                    locArgs,
                )
            }
        }
    }
}

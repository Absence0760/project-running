package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/// The qualifier grammar `LocaleReachTest` classifies directories with. It
/// decides which `values-*` directories every locale check reaches, so a
/// qualifier it silently misreads as "not a locale" would drop a shipped
/// string set back out of the guard.
class WearLocalesTest {

    @Test
    fun `the qualifier forms Android accepts all resolve to their BCP-47 tag`() {
        assertEquals("de", WearLocales.tagOrNull("values-de"))
        assertEquals("pt-BR", WearLocales.tagOrNull("values-b+pt+BR"))
        assertEquals("pt-BR", WearLocales.tagOrNull("values-pt-rBR"))
        assertEquals("fil", WearLocales.tagOrNull("values-b+fil"))
        assertEquals("zh-Hant-TW", WearLocales.tagOrNull("values-b+zh+Hant+TW"))
        assertEquals("es-419", WearLocales.tagOrNull("values-b+es+419"))
    }

    @Test
    fun `a non-locale resource qualifier is not read as a language`() {
        // `round` / `notround` are the Wear OS screen-shape qualifiers and
        // `car` is a UI mode; each has the shape of a language subtag. A
        // directory under one of these is reported by LocaleReachTest rather
        // than dropped, so the disagreement reaches a human.
        for (dir in listOf(
            "values-round",
            "values-notround",
            "values-night",
            "values-car",
            "values-v31",
            "values-sw192dp",
            "values-ldrtl",
            "values-port",
        )) {
            assertNull("$dir was read as a locale", WearLocales.tagOrNull(dir))
        }
    }

    @Test
    fun `the directories that ship resolve through the same grammar`() {
        assertEquals(
            WearLocales.translatedDirs().map { WearLocales.tagOf(it) }.toSet() +
                WearLocales.DEFAULT_TAG,
            WearLocales.tags(),
        )
    }
}

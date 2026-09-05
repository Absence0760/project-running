package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/// The pairing a rotary list needs, read out of Kotlin source.
///
/// `Modifier.rotaryScrollable(behavior, focusRequester = x)` receives bezel and
/// crown events only while `x` holds focus, so the modifier and an
/// `x.requestFocus()` are one wiring in two places. The guards below used to
/// count `.rotaryScrollable(` call sites against matches of the literal
/// `rotaryFocus.requestFocus()` — a claim about a VARIABLE NAME, which failed a
/// correctly-wired list under any other name and, in the other direction,
/// passed two lists sharing one requester as 2 against 2 (decisions § 1205).
internal object RotaryWiring {

    private val CALL = Regex("""\.rotaryScrollable\(""")

    fun callSiteCount(text: String): Int = CALL.findAll(text).count()

    /// The `focusRequester = <name>` argument of every `.rotaryScrollable(` in
    /// `text`, in source order. Fails rather than skipping a call site that
    /// names none: a modifier with no requester argument is exactly the unwired
    /// list this reads for, and dropping it would make the pairing vacuous.
    fun requesters(text: String, where: String): List<String> =
        CALL.findAll(text).map { m ->
            val args = parenthesised(text, text.indexOf('(', m.range.last))
            val named = Regex("""focusRequester\s*=\s*(\w+)""").find(args)
            assertTrue(
                "a `.rotaryScrollable(` in $where names no focusRequester, so nothing " +
                    "focuses it and the bezel/crown reach it never: $args",
                named != null,
            )
            named!!.groupValues[1]
        }.toList()

    /// Assert every rotary list in `text` is wired: its own requester, declared
    /// here and focused here, and not shared with a second list.
    fun assertPaired(text: String, where: String) {
        val names = requesters(text, where)
        assertEquals(
            "two rotary lists in $where share one FocusRequester — one call to " +
                "requestFocus() cannot focus both, so the second receives nothing: $names",
            names.size,
            names.toSet().size,
        )
        for (name in names) {
            assertTrue(
                "`$name` is handed to a rotaryScrollable in $where but never focused " +
                    "there — an unfocused requester makes the bezel/crown silently dead",
                Regex("""\b${Regex.escape(name)}\.requestFocus\(\)""").containsMatchIn(text),
            )
            assertTrue(
                "`$name` is focused in $where but not created there — a FocusRequester " +
                    "reached from an outer scope focuses whichever node bound it last",
                Regex("""val\s+${Regex.escape(name)}\s*=\s*remember\s*\{\s*FocusRequester\(\)\s*\}""")
                    .containsMatchIn(text),
            )
        }
    }

    /// The parenthesised argument list starting at `open`, brace-matched.
    private fun parenthesised(text: String, open: Int): String {
        var depth = 0
        for (i in open until text.length) {
            when (text[i]) {
                '(' -> depth += 1
                ')' -> {
                    depth -= 1
                    if (depth == 0) return text.substring(open, i + 1)
                }
            }
        }
        return text.substring(open)
    }
}

package com.runapp.watchwear

import java.io.File

/// The module's own Kotlin source, read as text for the source-level
/// rules that have no compiler to ask.
///
/// Every such rule needs the same two things and neither is a regex: the
/// set of files the rule applies to, derived from the tree rather than
/// listed, and a view of a file in which a token that only LOOKS like code
/// is not read as code. `catch (e: X) {}` inside a KDoc paragraph warning
/// against it, or inside the failure message of the very test that forbids
/// it, is prose — a scan that cannot tell the difference fails correct
/// source, and the usual repair for that is to narrow the scan until it
/// reads almost nothing, which is how a rule about a module came to read
/// one file of 57.
///
/// So three views, each with one job, all the same length as the original
/// so an index means the same line in every one of them:
///
///  - [structureView] blanks comments AND strings. Brace counting and
///    construct-finding read this, so a `{` in a message cannot move the
///    depth and a `catch` in prose is not a site.
///  - [codeView] blanks comments only. "Does this body do anything" reads
///    this, because a body whose whole content is a string literal —
///    `humanErrorMessage`'s `"HTTP $code"` — is a value the caller uses,
///    not a silence.
///  - [commentView] blanks strings only. "Is there a stated reason" reads
///    this, so a `//` inside a URL is not mistaken for one.
object KotlinSources {

    fun mainRoot(): File =
        WearLocales.findUp("apps/watch_wear/android/app/src/main/kotlin")
            ?: WearLocales.findUp("app/src/main/kotlin")
            ?: WearLocales.findUp("src/main/kotlin")
            ?: error("could not locate the Wear OS main source set")

    /// Every `.kt` under the main source set, in path order. Derived, not
    /// listed: a file added tomorrow is in scope without anyone extending
    /// a table.
    fun mainSources(): List<File> =
        mainRoot().walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .sortedBy { it.invariantSeparatorsPath }
            .toList()

    fun structureView(text: String): String = blank(text, strings = true, comments = true)

    fun codeView(text: String): String = blank(text, strings = false, comments = true)

    fun commentView(text: String): String = blank(text, strings = true, comments = false)

    /// The index of the `}` closing the block whose `{` is at [open], or
    /// -1 if the source is unbalanced. Reads a [structureView], so a brace
    /// in a string or a comment does not move the count.
    fun blockEnd(structure: String, open: Int): Int {
        var depth = 0
        var i = open
        while (i < structure.length) {
            when (structure[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return i
                }
            }
            i++
        }
        return -1
    }

    /// A body says nothing when, comments aside, it holds no expression at
    /// all — or holds only Kotlin's no-op one. `catch (e: X) { Unit }` is a
    /// re-spelling of `catch (e: X) {}`, and a rule keyed on the empty
    /// braces would pass it.
    fun saysNothing(codeBody: String): Boolean {
        val stripped = codeBody.filterNot { it.isWhitespace() || it == ';' }
        return stripped.isEmpty() || stripped == "Unit"
    }

    fun statesAReason(commentBody: String): Boolean =
        commentBody.contains("//") || commentBody.contains("/*")

    private fun blank(text: String, strings: Boolean, comments: Boolean): String {
        val out = StringBuilder(text)
        fun wipe(from: Int, to: Int) {
            for (k in from until minOf(to, text.length)) {
                if (out[k] != '\n') out[k] = ' '
            }
        }
        // One pass, and the order of the branches is the rule: whichever
        // span opens first consumes the other's opener. `"https://x"` is a
        // string containing no comment; `// see "x"` is a comment
        // containing no string.
        var i = 0
        while (i < text.length) {
            val end: Int = when {
                text.startsWith("\"\"\"", i) ->
                    text.indexOf("\"\"\"", i + 3).let { if (it < 0) text.length else it + 3 }
                        .also { if (strings) wipe(i, it) }
                text[i] == '"' || text[i] == '\'' ->
                    closeOfLiteral(text, i).also { if (strings) wipe(i, it) }
                text.startsWith("//", i) ->
                    text.indexOf('\n', i).let { if (it < 0) text.length else it }
                        .also { if (comments) wipe(i, it) }
                text.startsWith("/*", i) ->
                    text.indexOf("*/", i + 2).let { if (it < 0) text.length else it + 2 }
                        .also { if (comments) wipe(i, it) }
                else -> i + 1
            }
            i = maxOf(end, i + 1)
        }
        return out.toString()
    }

    /// Index one past the closing quote of the single-quote or
    /// double-quote literal opening at [start]. A backslash consumes the
    /// character after it, so `'\''` and `"a\"b"` close where they should.
    private fun closeOfLiteral(text: String, start: Int): Int {
        val quote = text[start]
        var j = start + 1
        while (j < text.length && text[j] != quote && text[j] != '\n') {
            if (text[j] == '\\') j++
            j++
        }
        return minOf(j + 1, text.length)
    }
}

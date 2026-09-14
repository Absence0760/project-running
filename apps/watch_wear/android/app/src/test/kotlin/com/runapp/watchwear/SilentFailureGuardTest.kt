package com.runapp.watchwear

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/// No failure this module intercepts may vanish without trace, anywhere
/// under `src/main`.
///
/// The rule is older than this class; its READING was one file.
/// `ViewModelStreamResilienceTest` grepped `catch (…) {}` out of
/// `RunViewModel.kt` alone, because that is where sign-out's tile-cache
/// wipe swallowed and the cache it left behind is a map of where the
/// signed-out user runs. The sentence it states is about the module: at
/// the base commit the module holds 57 `.kt` files, 51 `catch` blocks
/// across 17 of them, and 21 of those 51 were in scope. The other 30 —
/// `SupabaseClient`, `SessionStore`, `LocalRouteStore`, `TileSource`, the
/// whole `recording/` package — could each have gone silent with nothing
/// to notice.
///
/// Widening the file set is half of it. The other half is that a rule
/// keyed on the SPELLING `catch (…) {}` is wrong in both directions. It
/// fails correct source: the empty braces appear inside this very file's
/// prose and inside the failure messages below, and a naive scan reads
/// them as sites. And it passes a silence written any other way — Kotlin
/// has three of those and this module uses all three:
///
///  1. `catch (…) { … }` with nothing in the body.
///  2. `Flow.catch { … }` with nothing in the lambda — the stream form,
///     which carries no parentheses and so was never even a candidate
///     for the old regex.
///  3. `runCatching { … }` whose `Result` is discarded — no `.getOrNull`,
///     no `.onFailure`, not assigned, not returned. Behaviourally
///     `try { … } catch (_: Throwable) {}` and textually nothing like it.
///     Five of those exist and the narrow rule saw none.
///
/// So the guard finds the CONSTRUCT and asks what it leaves behind, on a
/// [KotlinSources] view in which a brace inside a string cannot move the
/// depth and a `catch` inside a comment is not a site. What must be left
/// behind is one of: an expression (`humanErrorMessage`'s bare
/// `"HTTP $code"` is a value the caller uses), or a stated reason. The
/// reason is a comment in the body, which is the exemption shape the 13
/// deliberate swallows in this module already use — not a second
/// mechanism invented here. `Unit` is neither: it is the empty body
/// re-spelled.
class SilentFailureGuardTest {

    private data class Site(
        val file: String,
        val line: Int,
        val construct: String,
        val code: String,
        val comments: String,
    ) {
        override fun toString(): String = "$file:$line $construct"
    }

    private val scanned: List<Pair<String, Triple<String, String, String>>> by lazy {
        KotlinSources.mainSources().map { f ->
            val raw = f.readText()
            val rel = f.invariantSeparatorsPath.substringAfter("src/main/kotlin/")
            rel to Triple(
                KotlinSources.structureView(raw),
                KotlinSources.codeView(raw),
                KotlinSources.commentView(raw),
            )
        }
    }

    private fun sitesOf(pattern: Regex, construct: String): List<Site> =
        scanned.flatMap { (rel, views) ->
            val (structure, code, comments) = views
            pattern.findAll(structure).mapNotNull { m ->
                val open = m.range.last
                val close = KotlinSources.blockEnd(structure, open)
                if (close < 0) {
                    null
                } else {
                    Site(
                        file = rel,
                        line = structure.substring(0, m.range.first).count { it == '\n' } + 1,
                        construct = construct,
                        code = code.substring(open + 1, close),
                        comments = comments.substring(open + 1, close),
                    )
                }
            }
        }

    private fun catchSites(): List<Site> =
        sitesOf(Regex("""\bcatch\s*\([^)]*\)\s*\{"""), "catch")

    private fun flowCatchSites(): List<Site> =
        sitesOf(Regex("""\.catch\s*\{"""), "Flow.catch")

    /// A `runCatching` whose `Result` nothing reads. The two tests are
    /// what the language gives: nothing chains off the closing brace, and
    /// the construct is not itself an operand — so `= runCatching`,
    /// `return runCatching`, `|| runCatching` and `.getOrDefault(false)`
    /// are all consumers and only a bare statement is a discard.
    ///
    /// The reason for one of these cannot sit in the lambda, which is a
    /// one-liner doing the work; it sits on the comment lines above. Both
    /// are accepted.
    private fun discardedRunCatchingSites(): List<Site> =
        scanned.flatMap { (rel, views) ->
            val (structure, _, comments) = views
            Regex("""\brunCatching\s*\{""").findAll(structure).mapNotNull { m ->
                val open = m.range.last
                val close = KotlinSources.blockEnd(structure, open)
                if (close < 0) return@mapNotNull null
                val chained = structure.substring(close + 1).firstOrNull { !it.isWhitespace() } == '.'
                val precededBy = structure.substring(0, m.range.first).lastOrNull { !it.isWhitespace() }
                val statement = precededBy == null || precededBy in "{};"
                if (chained || !statement) return@mapNotNull null
                Site(
                    file = rel,
                    line = structure.substring(0, m.range.first).count { it == '\n' } + 1,
                    construct = "runCatching (Result discarded)",
                    // The lambda always holds the call being attempted, so
                    // "does it do anything" is not the question here — the
                    // question is whether the dropped failure is accounted
                    // for, and that is the comment alone.
                    code = "",
                    comments = commentLinesAbove(comments, m.range.first) +
                        comments.substring(open + 1, close),
                )
            }
        }

    /// The contiguous run of comment-only lines immediately above the line
    /// [at] falls on. Contiguity is the whole point: a comment three
    /// statements up explains something else.
    private fun commentLinesAbove(comments: String, at: Int): String {
        val lines = comments.substring(0, at).split("\n")
        val above = lines.dropLast(1).reversed()
            .takeWhile { it.trimStart().let { t -> t.startsWith("//") || t.startsWith("*") || t.startsWith("/*") } }
        return above.joinToString("\n")
    }

    @Test
    fun `the guard reads the whole module, not one file of it`() {
        val files = KotlinSources.mainSources()
        assertTrue(
            "fewer than 40 .kt files found under src/main — the source root has " +
                "moved and every rule below is passing on an empty read. Found " +
                "${files.size}: ${files.take(5).map { it.name }}",
            files.size >= 40,
        )
        assertTrue(
            "RunViewModel.kt is not in the scanned set, so the file the narrow " +
                "rule used to read is now unread — a strict regression",
            files.any { it.name == "RunViewModel.kt" },
        )
        assertTrue(
            "the scan reaches only ${catchSites().map { it.file }.distinct().size} " +
                "file(s) — it has narrowed back to something like the single-file " +
                "read this class replaced",
            catchSites().map { it.file }.distinct().size >= 8,
        )
    }

    @Test
    fun `the guard sees all three swallowing constructs`() {
        // Every rule below is vacuously true against a scan that parsed
        // nothing, and a stripper that over-blanks fails exactly that way.
        // The floors are under the base commit's measured 51 / 5 / 5.
        assertTrue(
            "fewer than 30 catch blocks parsed out of src/main (found " +
                "${catchSites().size}) — the structure view or the pattern has " +
                "gone blind",
            catchSites().size >= 30,
        )
        assertTrue(
            "no Flow .catch operators parsed (found ${flowCatchSites().size}) — " +
                "the stream form is how the Data Layer bridges and the sensor " +
                "streams are guarded, and it carries no parentheses to key on",
            flowCatchSites().size >= 3,
        )
        assertTrue(
            "no discarded runCatching parsed (found " +
                "${discardedRunCatchingSites().size}) — this is the silence with " +
                "no `catch` keyword in it at all, and a scan that cannot see it " +
                "is the gap this class was written for",
            discardedRunCatchingSites().size >= 3,
        )
    }

    @Test
    fun `no failure guard in the module is completely silent`() {
        val silent = (catchSites() + flowCatchSites())
            .filter { KotlinSources.saysNothing(it.code) && !KotlinSources.statesAReason(it.comments) }
            .plus(discardedRunCatchingSites().filterNot { KotlinSources.statesAReason(it.comments) })
            .map { it.toString() }
            .sorted()
        assertEquals(
            "a failure is intercepted here and nothing survives it — no log, no " +
                "state, no value, not even a stated reason. Sign-out's tile-cache " +
                "wipe was one of these and the cache it left is a map of where the " +
                "signed-out user runs. This is not a demand for a log on every " +
                "site: several swallows in this module are advisory polls whose " +
                "comment IS the rationale, and a one-line comment saying why is " +
                "the accepted answer. What may not stand is silence with nothing " +
                "written down: $silent",
            emptyList<String>(),
            silent,
        )
    }

    @Test
    fun `a catch in prose or in a message is not a site`() {
        // The direction that pushes a rule back towards reading one file.
        // The empty-braced form appears in this class's own KDoc and in the
        // failure text above; a scan that flagged those would be fixed by
        // narrowing it, which is how the rule got where it was found.
        val fixture = """
            /// Never write catch (e: Throwable) {} here.
            fun f() {
                val msg = "rejected: catch (e: Throwable) {}"
                try { g() } catch (e: Throwable) { Log.w(TAG, msg, e) }
            }
        """.trimIndent()
        val structure = KotlinSources.structureView(fixture)
        assertEquals(
            "the KDoc's and the string literal's `catch (…) {}` were read as " +
                "sites: $structure",
            1,
            Regex("""\bcatch\s*\([^)]*\)\s*\{""").findAll(structure).count(),
        )
    }

    @Test
    fun `the three views each answer only their own question`() {
        val fixture = """
            fun f() = try { g() } catch (_: Throwable) { "HTTP ${'$'}code // not a comment" }
        """.trimIndent()
        assertTrue(
            "a body whose whole content is a string literal is a value the caller " +
                "uses, and codeView must keep it",
            !KotlinSources.saysNothing(KotlinSources.codeView(fixture).substringAfterLast("{").substringBefore("}")),
        )
        assertTrue(
            "commentView must not read a `//` inside a string literal as a stated " +
                "reason",
            !KotlinSources.statesAReason(KotlinSources.commentView(fixture)),
        )
        assertTrue(
            "structureView must blank both, so neither can move a brace count",
            !KotlinSources.structureView(fixture).contains("HTTP"),
        )
    }

    @Test
    fun `the silence test recognises every shape it claims to`() {
        // The mutation cases, pinned rather than run by hand once: each of
        // these is a silence, and each is spelled differently.
        assertTrue("empty braces", KotlinSources.saysNothing(""))
        assertTrue("whitespace and newlines only", KotlinSources.saysNothing("\n    \n"))
        assertTrue("a stray semicolon", KotlinSources.saysNothing(" ; "))
        assertTrue("Kotlin's no-op expression re-spells the empty body", KotlinSources.saysNothing(" Unit "))
        assertTrue("a log is not silence", !KotlinSources.saysNothing(" Log.w(TAG, \"x\", e) "))
        assertTrue("a value is not silence", !KotlinSources.saysNothing(" \"HTTP 500\" "))
        assertTrue("a state write is not silence", !KotlinSources.saysNothing(" available = false "))
        assertTrue("a line comment is a stated reason", KotlinSources.statesAReason(" // best-effort "))
        assertTrue("a block comment is a stated reason", KotlinSources.statesAReason(" /* best-effort */ "))
        assertTrue("nothing written down is not one", !KotlinSources.statesAReason("   "))
    }

    @Test
    fun `a Result the code reads is not a discard`() {
        // The consumers, so the runCatching rule cannot drift into failing
        // every use of the construct — which would end with it exempted
        // wholesale.
        val consumers = listOf(
            "fun a() { val r = runCatching { g() } }",
            "fun b() = runCatching { g() }.getOrNull()",
            "fun c() { runCatching { g() }.onFailure { Log.w(TAG, \"x\", it) } }",
            "fun d(): Boolean = x() || runCatching { g() }.isSuccess",
            "fun e() { return runCatching { g() }.getOrDefault(false) }",
        )
        for (src in consumers) {
            val structure = KotlinSources.structureView(src)
            val m = Regex("""\brunCatching\s*\{""").find(structure)!!
            val close = KotlinSources.blockEnd(structure, m.range.last)
            val chained = structure.substring(close + 1).firstOrNull { !it.isWhitespace() } == '.'
            val precededBy = structure.substring(0, m.range.first).lastOrNull { !it.isWhitespace() }
            assertTrue(
                "read as a discarded Result, which it is not: $src",
                chained || !(precededBy == null || precededBy in "{};"),
            )
        }
    }
}

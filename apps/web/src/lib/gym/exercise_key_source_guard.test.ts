// Source-level guard: nothing in the web tree derives or compares an exercise
// identity off the display spelling.
//
// Two scans, because there are two ways to get it wrong and they are opposites.
// `foldHits` bans the WRONG fold (`trim().toLowerCase()` where
// `normaliseExerciseName` belongs). `rawNameComparisonHits` bans NO fold -- a
// raw `===` between two spellings, which is what four block-grouping surfaces
// and the routine promotion were doing (decisions 1322). The first scan is
// blind to the second shape by construction: there is no `.toLowerCase()` in
// `last.name === s.exercise_name` to see.
//
// The exercise grouping key has one derivation — `normaliseExerciseName`,
// which collapses the named whitespace class and lower-cases through the
// FROZEN Unicode table (decisions § 1175). `trim().toLowerCase()` is neither:
// it splits an internal whitespace run, and it answers a different letter from
// the table at 1 code point on Node and 465 on Dart. Six surfaces derived the
// key that way anyway; two of them were lookups WRITTEN with one spelling and
// READ with another, so a lift logged twice in one workout lost its PR chips
// on every block but the first, with no failure anywhere (decisions § 1248).
//
// Nothing stopped a seventh being written, which is why this scan exists: the
// defect is invisible at runtime, so source is the only place it can be seen.
// The Dart half is `apps/mobile_android/test/exercise_key_source_guard_test.dart`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';
import { stripComments } from '../core/strip_comments';

const SRC = resolve('src');

/// A file that names an exercise anywhere in its CODE is banned from the
/// runtime fold outright, rather than only where the receiver happens to name
/// the value it is folding.
///
/// This is the rule that gives the scan teeth, and it is anchored to what the
/// file DOES rather than to where it sits: the gym surfaces call their locals
/// `raw`, `q` and `s`, so a receiver test alone reads the picker's
/// `q.toLowerCase()` as unrelated to exercises and the fold walks straight
/// past. A hand-listed set of gym directories would have the same hole one
/// rename later. Prose does not count — `stripComments` runs first, so a doc
/// comment saying "exercise the enhance path" leaves the file unbanned.
const NAMES_AN_EXERCISE = /exercise/i;

/// Modules that serve every domain, so naming an exercise somewhere says
/// nothing about what any one fold in them is folding. The file-level ban is
/// waived here and each fold is judged on its own receiver instead — which is
/// what spares `slugify`'s `name.toLowerCase()` and the runner-handle
/// comparisons while still firing the moment one of them folds an
/// `exercise_name`.
///
/// A waiver of the FILE-level shapes only, in both scans that consult it. The
/// receiver rules — [NAMES_AN_EXERCISE] on a fold's own receiver,
/// [NAMES_A_SPELLING] on a comparison's operands — still run over every listed
/// module, so nothing here is un-scanned. `rawNameComparisonHits` used to skip
/// the whole file instead, which spared a scan that never had a file-level rule
/// to waive: a raw `patch.exercise_name !== other.exercise_name` inside
/// `data.ts` was judged by nothing at all (§ 1509).
const BROAD_MODULES = ['lib/core/data.ts'];

/// Files that still fold an exercise name, with why the fix is not in this
/// change. Each entry is a real instance of the same defect, in a tree the
/// change that added it does not own. The staleness test below fails when one
/// stops matching, so an exemption cannot outlive the site it excuses.
///
/// Empty since § 1274-1276 closed the last three (the share-workout meta
/// count, the coach prompt's per-workout tally and the catalogue picker's
/// search), which is the state the Dart half has been in since § 1250.
const PENDING: { path: string; why: string }[] = [];

/// A runtime case fold, however it is spelled. Only the LOWER half is
/// bannable file-wide: upper-casing is a presentation transform, never a key
/// derivation. An upper-case fold applied to something the code calls an
/// exercise is still reported, on the receiver rule below — a key derived that
/// way would be just as wrong. The Dart half draws the same line, where nine
/// section labels depend on it.
const RUNTIME_FOLD = /\.to(?:Locale)?(?<case>Lower|Upper)Case\s*\(/g;

interface Hit {
	path: string;
	line: number;
	text: string;
}

/// A declaration starting at column 0 — the top-level functions and consts a
/// `.ts` module is made of. Anchored there on purpose: the nearest PRECEDING
/// declaration at any depth would be a `const q = …` one line up, and naming
/// the enclosing scope after that is worse than not naming it. A `.svelte`
/// file's `<script>` body is indented, so this finds nothing there and the
/// file-level rule is what covers it.
const TOP_LEVEL_DECL =
	/^(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:function\s+|const\s+|let\s+|var\s+|class\s+)([A-Za-z_$][\w$]*)/gm;

/// Whether the top-level declaration enclosing [at] names an exercise.
///
/// The rule that reaches a broad module, where the file-level one is waived and
/// has to be: `data.ts` is 12,000 lines of club, checkpoint and meal-template
/// names beside its exercise ones, so "this file names an exercise" says
/// nothing about any one value in it — but "this value is inside
/// `fetchExerciseSetHistoryBatch`" says everything. Both of that module's
/// spelling-blankness defects were written under exactly such a name, on a
/// subject called `name` and `n`, where neither the receiver rule nor the file
/// rule could see them and a local line-regex in `data.test.ts` — the reason
/// the waiver was thought covered — missed them too (§ 1508).
///
/// Additive everywhere rather than a replacement for the file rule: it can only
/// widen what a scan sees, so no shape either scan caught before stops being
/// caught.
function scopeNamesAnExercise(code: string, at: number): boolean {
	let name = '';
	for (const m of code.matchAll(TOP_LEVEL_DECL)) {
		if ((m.index ?? 0) > at) break;
		name = m[1];
	}
	return NAMES_AN_EXERCISE.test(name);
}

/// The receiver expression a fold is applied to: the member chain immediately
/// left of the `.`, with balanced call and index groups walked over so
/// `(s.exercise_name ?? '').trim().toLowerCase()` reports the whole chain
/// rather than stopping at `.trim()`.
function receiverOf(code: string, at: number): string {
	let i = at - 1;
	while (i >= 0) {
		const c = code[i];
		if (/[\s]/.test(c) || /[A-Za-z0-9_$.?!]/.test(c)) {
			i--;
			continue;
		}
		if (c === ')' || c === ']') {
			const open = c === ')' ? '(' : '[';
			let depth = 0;
			while (i >= 0) {
				if (code[i] === c) depth++;
				else if (code[i] === open && --depth === 0) {
					i--;
					break;
				}
				i--;
			}
			continue;
		}
		break;
	}
	return code.slice(i + 1, at);
}

/// The statement a fold sits in — back to the nearest `;`, `,`, `{` or `}`. Catches
/// the shape the receiver alone cannot, where the value being folded was named
/// by the declaration rather than by the chain (`const exerciseKey = n.trim()
/// .toLowerCase()`). A value assigned to a neutral name in an EARLIER
/// statement and folded in this one is still out of reach; the blanket ban
/// inside the gym trees is what covers the surfaces where that matters.
function statementAt(code: string, at: number): string {
	let i = at - 1;
	while (i >= 0 && !';,{}'.includes(code[i])) i--;
	return code.slice(i + 1, at);
}

/// Every runtime case fold in [source] that this guard objects to, given where
/// the file lives. Takes the source rather than reading it so the mutation
/// test below can feed the same function a planted violation.
export function foldHits(path: string, source: string): Hit[] {
	// Matches are found in the string-blanked text so a documentation string
	// naming the banned shape is never read as an instance of it; the receiver
	// is read out of the comment-stripped text, where a quoted index like
	// `s['exercise_name']` still names what is being folded. Both transforms
	// preserve offsets.
	const code = stripComments(source);
	const scan = blankQuoted(code);
	const fileNamesAnExercise = NAMES_AN_EXERCISE.test(scan) && !BROAD_MODULES.includes(path);
	const out: Hit[] = [];
	for (const m of scan.matchAll(RUNTIME_FOLD)) {
		const at = m.index ?? 0;
		const named =
			NAMES_AN_EXERCISE.test(receiverOf(code, at)) || NAMES_AN_EXERCISE.test(statementAt(code, at));
		const lowering = m.groups?.case === 'Lower';
		const scoped = lowering && scopeNamesAnExercise(code, at);
		if (!(lowering && fileNamesAnExercise) && !named && !scoped) continue;
		const line = code.slice(0, at).split('\n').length;
		out.push({ path, line, text: source.split('\n')[line - 1]?.trim() ?? '' });
	}
	return out;
}

/// Bodies of single- and double-quoted strings blanked, offsets preserved.
/// `stripComments` emits string literals verbatim by design (a misread there
/// could delete code), so a documentation string naming the banned shape would
/// otherwise be reported as an instance of it. Template literals are left
/// alone: `${x.toLowerCase()}` inside one is a real fold.
function blankQuoted(code: string): string {
	let out = '';
	let i = 0;
	while (i < code.length) {
		const c = code[i];
		if (c !== "'" && c !== '"') {
			out += c;
			i++;
			continue;
		}
		out += c;
		i++;
		while (i < code.length && code[i] !== c && code[i] !== '\n') {
			const escaped = code[i] === '\\';
			out += escaped ? '  ' : ' ';
			i += escaped ? 2 : 1;
		}
		if (i < code.length && code[i] === c) {
			out += c;
			i++;
		}
	}
	return out;
}

/// An equality comparison, and only that: `>=` / `<=` / `=>` / assignment are
/// excluded by the surrounding character tests rather than by listing them.
const COMPARISON = /(?<![<>=!])(?:===|!==|==|!=)(?!=)/g;

/// The operand to the RIGHT of an operator at [at]: whitespace skipped, then a
/// primary expression -- identifier/member chain with balanced call and index
/// groups walked over, and a quoted literal read whole. The mirror of
/// [receiverOf], which reads the left.
function operandAfter(code: string, at: number): string {
	let i = at;
	while (i < code.length && /\s/.test(code[i])) i++;
	const start = i;
	if (code[i] === "'" || code[i] === '"' || code[i] === '`') {
		const q = code[i];
		i++;
		while (i < code.length && code[i] !== q) i += code[i] === '\\' ? 2 : 1;
		return code.slice(start, Math.min(i + 1, code.length));
	}
	while (i < code.length) {
		const c = code[i];
		if (/[A-Za-z0-9_$.?!]/.test(c)) {
			i++;
			continue;
		}
		if (c === '(' || c === '[') {
			const close = c === '(' ? ')' : ']';
			let depth = 0;
			while (i < code.length) {
				if (code[i] === c) depth++;
				else if (code[i] === close && --depth === 0) {
					i++;
					break;
				}
				i++;
			}
			continue;
		}
		break;
	}
	return code.slice(start, i);
}

/// An operand naming the free-text DISPLAY spelling of an exercise. Deliberately
/// narrower than [NAMES_AN_EXERCISE]: `exercise_id` and `exerciseCount` are
/// compared legitimately all over the tree, and only the NAME is the value with
/// two spellings.
const NAMES_A_SPELLING = /exercise[_]?name|exercise_?names/i;

/// A literal the other side of a comparison, which makes it a blankness or
/// sentinel test rather than an identity test between two spellings.
function isLiteral(operand: string): boolean {
	const t = operand.trim();
	if (t === '') return false;
	if (/^['"`]/.test(t)) return true;
	return /^(null|undefined|true|false|-?\d)/.test(t);
}

/// Every raw comparison of an exercise spelling in [source]. Exported so the
/// mutation test below can feed it planted violations, as `foldHits` is.
///
/// Each operand is judged on its DECLARATION as well as on itself. The scan
/// shipped without that and the Dart port found what it cost: the mobile
/// compose sheet grouped on `last.name.text == name` three lines under `final
/// name = (s['exercise_name'] as String?) ?? ''`, so neither operand said
/// "exercise" where the comparison was written and a tree the scan called clean
/// still rendered one lift as two blocks (decisions 1368).
export function rawNameComparisonHits(path: string, source: string): Hit[] {
	const code = stripComments(source);
	const scan = blankQuoted(code);
	const out: Hit[] = [];
	for (const m of scan.matchAll(COMPARISON)) {
		const at = m.index ?? 0;
		const left = originOf(code, receiverOf(code, at), at);
		const right = originOf(code, operandAfter(code, at + m[0].length), at);
		// A folded operand is the fix, not the defect. Either side carrying the
		// canonical derivation means the comparison is already on the key.
		if (/normaliseExerciseName\s*\(/.test(left) || /normaliseExerciseName\s*\(/.test(right)) continue;
		const namesSpelling = NAMES_A_SPELLING.test(left) || NAMES_A_SPELLING.test(right);
		if (!namesSpelling) continue;
		if (isLiteral(left) || isLiteral(right)) continue;
		const line = code.slice(0, at).split('\n').length;
		out.push({ path, line, text: source.split('\n')[line - 1]?.trim() ?? '' });
	}
	return out;
}

/// A field carrying the free-text DISPLAY spelling under a name that does not
/// say "exercise". Judged only inside a file that names one, the same
/// file-level rule that gives [foldHits] its teeth: the two editors call their
/// blocks `ex` and `e`, so `ex.name` says nothing to a receiver test on its own
/// while saying everything inside `GymEditor.svelte`.
const NAMES_A_DISPLAY_FIELD = /\.name\b/;

/// A value whose OWN identifier is the display spelling, judged under the same
/// file-level rule. The scan trusted a `.name` READ and not a value called
/// `name`, which is the difference between a spelling taken off a row and one
/// typed by the user — and the typed one is the whole reason the catalogue
/// picker's create path exists. There the value reaches the test through
/// `$derived(query.trim())`, whose text carries no `.name` and no "exercise",
/// so no amount of chasing the declaration can reach it: the evidence is the
/// subject, not the origin (decisions § 1483).
///
/// Anchored at the start so the trimming chain the defect is usually spelled
/// with (`name.trim() === ''`) is still the same subject, and so `named`,
/// whose `length === 0` is a count of blocks rather than a blank name, is not.
/// Unlike the `.name` read this sits beside, it is judged on the length shape
/// too: `named` is what that carve-out exists for and the word boundary
/// already excludes it.
///
/// The plural is here because [iteratedCollection] resolves an arrow parameter
/// to the collection, and a list of spellings is called `names` — the one
/// `fetchExerciseSetHistoryBatch` filters. `named` is excluded by the same word
/// boundary either way.
const IS_A_NAME_IDENTIFIER = /^names?\b/;

/// An empty-string literal, read out of the comment-stripped text where string
/// BODIES are still present. [blankQuoted] preserves offsets by replacing a
/// body with spaces, so `'x'` would read as an empty literal there.
function isEmptyLiteral(operand: string): boolean {
	return /^(?:''|""|``)$/.test(operand.trim());
}

const LENGTH_TAIL = /\.length\s*$/;

/// Every operator a blankness test is written with. Deliberately wider than
/// [COMPARISON], which the identity scan uses: `x === ''`, `x.length > 0` and
/// `x.length < 1` ask one question of one value, and the ordering spellings are
/// the ones the defect actually wore — two of the three writes § 1367 fixed
/// were `.trim().length > 0` and neither this scan nor anything else in the
/// tree could see them (§ 1508).
///
/// A generic parameter (`$state<Exercise[]>`) matches the `<` here and is
/// rejected by [emptinessSubject], which admits an ordering only against a
/// `.length` receiver and a 0-or-1 bound. Excluding it here instead would need
/// a parser.
const BLANKNESS_COMPARISON = /(?<![<>=!])(?:===|!==|==|!=|<=|>=|<|>)(?!=)/g;

/// The only bounds an ordering comparison can be asking about emptiness at.
/// `length > 2` is a minimum-length rule, which is a different claim and not
/// this scan's.
const EMPTY_BOUND = /^[01]$/;

/// The operand to the LEFT of an operator, a quoted literal included.
/// [receiverOf] walks a member chain and stops dead at a quote, so `'' === name`
/// reads as no left operand at all — and the emptiness scan has to see the
/// literal whichever side it is written on.
function leftOperand(code: string, at: number): string {
	const chain = receiverOf(code, at);
	if (chain.trim() !== '') return chain;
	let i = at - 1;
	while (i >= 0 && /\s/.test(code[i])) i--;
	const q = code[i];
	if (q !== "'" && q !== '"' && q !== '`') return chain;
	let j = i - 1;
	while (j >= 0 && code[j] !== q) j--;
	return code.slice(Math.max(j, 0), i + 1);
}

/// The value a comparison is testing for emptiness, or null if it is not an
/// emptiness test at all, paired with whether the subject may be judged on its
/// DECLARATION as well as on the operand itself.
///
/// `x === ''`, `x.length === 0` and `x.length > 0` are one question asked of a
/// string, but only the first says the subject is one. A list is emptied the
/// same way, and
/// `named.length === 0` two lines under `const named = exercises.filter((e) =>
/// e.name.trim() !== '')` is a count of blocks, not a blank name — so the
/// length shape does not get the `.name`-READ rule, whose whole content there
/// would be the filter's own body.
///
/// It still gets the declaration chase. Judging the length shape on the OPERAND
/// alone left `const trimmed = name.trim(); if (trimmed.length < 1)` invisible
/// on both rails, which is a create path with one line rewritten; the two cases
/// separate on the two stricter rules, since a chased `name.trim()` is a
/// spelling by its own identifier and a chased `exercises.filter(…)` is not.
function emptinessSubject(left: string, right: string): { subject: string; chase: boolean } | null {
	if (isEmptyLiteral(right)) return { subject: left, chase: true };
	if (isEmptyLiteral(left)) return { subject: right, chase: true };
	if (EMPTY_BOUND.test(right.trim()) && LENGTH_TAIL.test(left))
		return { subject: left.replace(LENGTH_TAIL, ''), chase: false };
	if (EMPTY_BOUND.test(left.trim()) && LENGTH_TAIL.test(right))
		return { subject: right.replace(LENGTH_TAIL, ''), chase: false };
	return null;
}

/// The collection an arrow parameter iterates, or `''` when [expr] is not one.
///
/// `names.filter((n) => …)` binds `n` to an element of `names`, and no
/// declaration chase can see that — there is no `const n =` anywhere to find.
/// `fetchExerciseSetHistoryBatch` decides blankness on exactly that subject, so
/// until this existed the one call site the module's own name says is about
/// exercises was reachable by no rule the scan has: not the receiver, not the
/// declaration chase, not the enclosing declaration (§ 1508 measured the limit
/// and left it open). Its cover was a positive assertion in `data.test.ts` that
/// the body CALLS `namesAnExercise`, which a body can do while deciding on the
/// spelling three lines away.
///
/// The nearest such binding before the subject wins, for [originOf]'s reason:
/// one module iterates many collections and the first is rarely the right one.
function iteratedCollection(code: string, expr: string, at: number): string {
	const bind = new RegExp(`\\.\\s*[A-Za-z_$][\\w$]*\\s*\\(\\s*\\(?\\s*${expr}\\s*\\)?\\s*=>`, 'g');
	let last = -1;
	for (const m of code.slice(0, at).matchAll(bind)) last = m.index ?? -1;
	return last < 0 ? '' : receiverOf(code, last);
}

/// The right-hand side of a bare identifier's NEAREST PRECEDING declaration,
/// chased up to a few hops so a value named by a `const` two lines up is still
/// judged on where it came from — falling back to the collection it iterates
/// when the identifier is an arrow parameter rather than a declaration.
///
/// [foldHits] reaches that shape with [statementAt], and a blankness test
/// cannot: `if (name === '')` names nothing in its own statement, and the whole
/// defect is that the declaration one line up read `ex.name.trim()`. The chase
/// stops at the first expression that is not a bare identifier, which is why
/// the catalogue picker's `query` prop is out of reach — noted where the scan
/// is asserted.
///
/// **Nearest, not first**, and [at] is what makes that possible. The chase took
/// the file's FIRST declaration of the identifier, which is the right answer
/// only in a module holding one — `data.ts` declares `name` dozens of times, so
/// it answered about a club, a meal template or a gear item whenever it was
/// asked about an exercise. It fails BOTH ways: a real defect reads as clean
/// when the first declaration is innocent, and clean code reads as a defect
/// when the first one is not. Both directions are pinned below.
function originOf(code: string, operand: string, at: number): string {
	let expr = operand.trim();
	const before = code.slice(0, at);
	const seen = new Set<string>();
	for (let hop = 0; hop < 4; hop++) {
		if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(expr) || seen.has(expr)) break;
		seen.add(expr);
		const re = new RegExp(`\\b(?:const|let|var)\\s+${expr}\\s*(?::[^=;\\n]*)?=([^;\\n]*)`, 'g');
		let last: RegExpMatchArray | null = null;
		for (const m of before.matchAll(re)) last = m;
		if (!last) {
			const collection = iteratedCollection(code, expr, at);
			if (collection.trim() === '') break;
			expr = collection.trim();
			continue;
		}
		expr = last[1].trim();
	}
	return expr;
}

/// A blankness test written with no comparison at all: `if (!name.trim())`.
/// Returns the offset of each such `.trim()` paired with the subject it is
/// applied to.
///
/// `!x` on its own is deliberately NOT bannable — it is how a nullable is
/// tested all over the tree — but `!x.trim()` can only be asking whether the
/// trimmed spelling is empty, which is the question JS `trim()` answers
/// differently from the fold at U+0085. A `.trim()` that continues into
/// `.length` or an `===` belongs to the comparison pass, so a chain is only
/// read here when the call ENDS the expression.
function negatedTrims(code: string, scan: string): { at: number; subject: string }[] {
	const out: { at: number; subject: string }[] = [];
	for (const m of scan.matchAll(/\.trim\(\s*\)/g)) {
		const at = m.index ?? 0;
		if (/^\s*[.[]/.test(code.slice(at + m[0].length, at + m[0].length + 8))) continue;
		// `receiverOf`'s character class carries `!` for the non-null assertion
		// (`x!.trim()`), so the negation arrives INSIDE the chain rather than
		// beside it. `x !== y.trim()` ends in `=`, not `!`, so the equality
		// operators exclude themselves.
		const chain = receiverOf(code, at).trim();
		if (!chain.startsWith('!')) continue;
		out.push({ at, subject: chain.replace(/^!+/, '') });
	}
	return out;
}

/// Every blankness test in [source] taken on an exercise SPELLING rather than
/// on its key. Exported so the mutation test below can feed it planted
/// violations, as the other two scans are.
///
/// The third shape, and the one the other two scans exclude by construction.
/// `rawNameComparisonHits` deliberately spares a comparison against a literal
/// — that is what separates an identity test from a sentinel test — and there
/// is no case fold in `name.trim() === ''` for `foldHits` to see. So the tree
/// could carry, and did carry, a drop guard that answered a different question
/// from every keyed surface downstream: JS `trim()` and the shared whitespace
/// class differ on U+0085, so a name made of one passed the guard and saved a
/// set whose server-stamped `exercise_key` is `''` (decisions 1367).
export function blankSpellingTestHits(path: string, source: string): Hit[] {
	const code = stripComments(source);
	const scan = blankQuoted(code);
	const fileNamesAnExercise = NAMES_AN_EXERCISE.test(scan) && !BROAD_MODULES.includes(path);
	const candidates: { at: number; subject: string; chase: boolean }[] = [];
	for (const m of scan.matchAll(BLANKNESS_COMPARISON)) {
		const at = m.index ?? 0;
		const found = emptinessSubject(leftOperand(code, at), operandAfter(code, at + m[0].length));
		if (found !== null) candidates.push({ at, ...found });
	}
	for (const n of negatedTrims(code, scan)) candidates.push({ ...n, chase: true });
	const out: Hit[] = [];
	for (const found of candidates) {
		const at = found.at;
		const origin = originOf(code, found.subject, at);
		// The fix itself, on either the operand or its declaration.
		if (/normaliseExerciseName\s*\(|namesAnExercise\s*\(/.test(origin)) continue;
		const scoped = fileNamesAnExercise || scopeNamesAnExercise(code, at);
		const spelling =
			NAMES_A_SPELLING.test(origin) ||
			(scoped &&
				(IS_A_NAME_IDENTIFIER.test(found.subject.trim()) ||
					IS_A_NAME_IDENTIFIER.test(origin))) ||
			(found.chase && scoped && NAMES_A_DISPLAY_FIELD.test(origin));
		if (!spelling) continue;
		const line = code.slice(0, at).split('\n').length;
		out.push({ path, line, text: source.split('\n')[line - 1]?.trim() ?? '' });
	}
	out.sort((a, b) => a.line - b.line);
	return out;
}

function scannableFiles(dir: string): string[] {
	const out: string[] = [];
	for (const e of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, e.name);
		if (e.isDirectory()) out.push(...scannableFiles(full));
		else if (/\.(ts|svelte)$/.test(e.name) && !e.name.endsWith('.test.ts')) out.push(full);
	}
	return out;
}

function scanTree(scan: (path: string, source: string) => Hit[]): Hit[] {
	const out: Hit[] = [];
	for (const full of scannableFiles(SRC)) {
		const rel = relative(SRC, full).split(sep).join('/');
		out.push(...scan(rel, readFileSync(full, 'utf-8')));
	}
	return out;
}

test('the guard scans a tree that is actually there', () => {
	// § 510: a guard whose root has moved reports nothing at all, which reads
	// as a clean sweep. Anchor on a file the scan must always find.
	const files = scannableFiles(SRC).map((f) => relative(SRC, f).split(sep).join('/'));
	assert.ok(files.length > 500, `only ${files.length} scannable files under src/ — has the tree moved?`);
	assert.ok(files.includes('lib/gym/gym_prs.ts'), 'lib/gym/gym_prs.ts is not in the scan');
	assert.ok(files.includes('routes/gym/[id]/+page.svelte'), 'the gym detail page is not in the scan');
});

test('no web surface folds an exercise name with the runtime case mapping', () => {
	const pending = new Set(PENDING.map((p) => p.path));
	const offenders = scanTree(foldHits).filter((h) => !pending.has(h.path));
	assert.deepEqual(
		offenders,
		[],
		'Fold an exercise name with normaliseExerciseName from $lib/gym/gym_prs, ' +
			'never the runtime case mapping — it splits an internal whitespace run ' +
			'and answers a different letter from the frozen table:\n' +
			offenders.map((h) => `  ${h.path}:${h.line}  ${h.text}`).join('\n'),
	);
});

test('every broad-module waiver is still load-bearing', () => {
	// A waiver that no longer waives anything is a line the next reader has to
	// re-derive. It stops being load-bearing the moment the module stops
	// naming an exercise at all, at which point the file-level ban was never
	// going to fire on it.
	for (const rel of BROAD_MODULES) {
		const scan = blankQuoted(stripComments(readFileSync(join(SRC, rel), 'utf-8')));
		assert.ok(
			NAMES_AN_EXERCISE.test(scan),
			`${rel} no longer names an exercise in code — delete its BROAD_MODULES entry.`,
		);
	}
});

test('every pending exemption still names a real fold', () => {
	for (const p of PENDING) {
		const hits = foldHits(p.path, readFileSync(join(SRC, p.path), 'utf-8'));
		assert.ok(
			hits.length > 0,
			`${p.path} no longer folds an exercise name — delete its PENDING entry ` +
				'so the next one cannot hide behind it.',
		);
	}
});

test('the scan sees the shapes it bans, and spares the ones it must not', () => {
	// Planted violations, each a shape the tree could plausibly grow. A scan is
	// the only instrument that can see this defect, so a shape it misses is a
	// shape that returns. The first two are the ones a directory-anchored or a
	// receiver-anchored rule alone would each walk past.
	const caught: [string, string, string][] = [
		[
			'the file names an exercise, the fold names a neutral local',
			'lib/components/Picker.svelte',
			'let entries = $state<Exercise[]>([]);\n\tconst q = query.trim().toLowerCase();',
		],
		[
			'the file names an exercise, the fold is a bare block name',
			'routes/anywhere/+page.svelte',
			'const names = exerciseNames;\n\tconst k = block.name.trim().toLowerCase();',
		],
		['the receiver names one, the file otherwise does not', 'lib/share/x.ts', 'const k = s.exercise_name.trim().toLowerCase();'],
		[
			'the receiver names one across a broken chain',
			'lib/social/y.ts',
			'const k = row.exercise_name\n\t\t.trim()\n\t\t.toLowerCase();',
		],
		['camelCase field', 'lib/social/z.ts', 'const k = set.exerciseName.toLowerCase();'],
		['locale variant', 'lib/social/w.ts', 'const k = s.exercise_name.toLocaleLowerCase();'],
		['upper-cased instead', 'lib/social/v.ts', 'const k = s.exercise_name.toUpperCase();'],
		[
			'nullish default in parens',
			'lib/social/u.ts',
			"const k = (s.exercise_name ?? '').trim().toLowerCase();",
		],
		['quoted index', 'lib/social/t.ts', "const k = s['exercise_name'].toLowerCase();"],
		[
			'named by the declaration rather than the chain',
			'lib/social/s.ts',
			'const exerciseKey = n.trim().toLowerCase();',
		],
	];
	for (const [label, path, source] of caught) {
		assert.equal(foldHits(path, source).length, 1, `missed: ${label}`);
	}

	const spared: [string, string, string][] = [
		['a comment describing the ban', 'lib/social/a.ts', '// never exercise_name.trim().toLowerCase()'],
		['a string mentioning it', 'lib/social/b.ts', "const doc = 'exercise_name.toLowerCase()';"],
		[
			'a file that only mentions an exercise in prose',
			'lib/routes/route_detail.ts',
			'/// a stub to exercise the enhance path\nconst q = query.trim().toLowerCase();',
		],
		['nothing names an exercise at all', 'lib/social/c.ts', 'const q = query.trim().toLowerCase();'],
		[
			'a section label upper-cased for presentation',
			'routes/gym/records/+page.svelte',
			'const names = exerciseNames;\n\tconst head = label.toUpperCase();',
		],
		[
			'a broad module folding something that is not an exercise',
			'lib/core/data.ts',
			'const cols = exercise_name;\n\tconst slug = name.toLowerCase();',
		],
	];
	for (const [label, path, source] of spared) {
		assert.deepEqual(foldHits(path, source), [], `false positive: ${label}`);
	}

	// The waiver is a waiver, not a blanket: a real fold inside a broad module
	// is still reported on its receiver.
	assert.equal(
		foldHits('lib/core/data.ts', 'const k = s.exercise_name.toLowerCase();').length,
		1,
		'a broad module must still be judged fold by fold',
	);
});

test('no web surface compares two exercise spellings raw', () => {
	const offenders = scanTree(rawNameComparisonHits);
	assert.deepEqual(
		offenders,
		[],
		'Compare exercise spellings through sameExerciseName / normaliseExerciseName ' +
			'from $lib/gym/gym_prs, never with ===. Adjacency measured on the display ' +
			'spelling renders one lift as two blocks beside a header stat that counts ' +
			'one, and in routineFromWorkout it PERSISTED two rows under one key ' +
			'(decisions 1322):\n' +
			offenders.map((h) => `  ${h.path}:${h.line}  ${h.text}`).join('\n'),
	);
});

test('the raw-comparison scan sees the shapes it bans, and spares the ones it must not', () => {
	const caught: [string, string, string][] = [
		[
			'the block-grouping shape all four surfaces had',
			'lib/components/GymEditor.svelte',
			'if (last && last.name === s.exercise_name) last.sets.push(row);',
		],
		[
			'the same shape reversed',
			'routes/gym/[id]/+page.svelte',
			'if (s.exercise_name === last.name) last.sets.push(s);',
		],
		['camelCase field', 'lib/social/z.ts', 'if (a.exerciseName !== b.exerciseName) skip();'],
		['loose equality', 'lib/social/y.ts', 'if (last.name == s.exercise_name) merge();'],
		['quoted index', 'lib/social/x.ts', "if (last.name === s['exercise_name']) merge();"],
		[
			'a nullish default around the spelling',
			'lib/social/w.ts',
			"if ((s.exercise_name ?? '') === last.name) merge();",
		],
		[
			'neither operand says exercise where the comparison is written',
			'lib/components/Composer.svelte',
			"const name = s.exercise_name ?? '';\n\t\tif (last.name === name) last.sets.push(row);",
		],
		[
			// This scan has no file-level rule, so a broad module has nothing to
			// waive: the operands say "exercise" or they do not, wherever the
			// file sits. It read as spared for the fold scan's reason and was
			// spared by neither (§ 1509).
			'a broad module, whose operands still name a spelling',
			'lib/core/data.ts',
			'if (patch.exercise_name !== other.exercise_name) fields.name = x;',
		],
	];
	for (const [label, path, source] of caught) {
		assert.equal(rawNameComparisonHits(path, source).length, 1, `missed: ${label}`);
	}

	const spared: [string, string, string][] = [
		[
			'the fix itself',
			'lib/gym/exercise_history.ts',
			"if (normaliseExerciseName(s.exercise_name ?? '') !== key) continue;",
		],
		[
			'the fix with the fold on the right',
			'lib/gym/x.ts',
			'if (key !== normaliseExerciseName(s.exercise_name)) continue;',
		],
		['a blankness test', 'lib/gym/y.ts', "if (s.exercise_name === '') continue;"],
		['a null test', 'lib/gym/z.ts', 'if (s.exercise_name == null) continue;'],
		['an id compared, not a spelling', 'lib/gym/w.ts', 'if (a.exercise_id === b.exercise_id) merge();'],
		['a count compared', 'lib/gym/v.ts', 'if (a.exerciseCount !== b.exerciseCount) redraw();'],
		[
			'a comment describing the ban',
			'lib/gym/u.ts',
			'// never last.name === s.exercise_name',
		],
		['a string mentioning it', 'lib/gym/t.ts', "const doc = 'last.name === s.exercise_name';"],
		[
			'a helper call, which is not a comparison at all',
			'lib/gym/s.ts',
			'if (sameExerciseName(last.name, s.exercise_name)) last.sets.push(row);',
		],
		['a greater-or-equal beside one', 'lib/gym/r.ts', 'if (s.exercise_name.length >= 1) keep();'],
		['an arrow function', 'lib/gym/q.ts', 'const f = (s) => s.exercise_name;'],
	];
	for (const [label, path, source] of spared) {
		assert.deepEqual(rawNameComparisonHits(path, source), [], `false positive: ${label}`);
	}
});

test('no web surface decides an exercise name is blank on the display spelling', () => {
	const offenders = scanTree(blankSpellingTestHits);
	assert.deepEqual(
		offenders,
		[],
		'Decide blankness with namesAnExercise from $lib/gym/gym_prs, never with ' +
			"`name.trim() === ''`. The two answers differ on U+0085 (in the shared " +
			'whitespace class, not in the set JS trim() strips), so a name made of ' +
			'one is saved as a set every keyed surface counts as nothing and both ' +
			'key columns with a length CHECK refuse outright (decisions 1367):\n' +
			offenders.map((h) => `  ${h.path}:${h.line}  ${h.text}`).join('\n'),
	);
});

test('the blankness scan sees the shapes it bans, and spares the ones it must not', () => {
	const caught: [string, string, string][] = [
		[
			'the editor drop guard, named by a declaration one line up',
			'lib/components/GymEditor.svelte',
			"let catalogue = $state<Exercise[]>([]);\n\t\t\tconst name = ex.name.trim();\n\t\t\tif (name === '') continue;",
		],
		[
			'the routine editor filter, named by the chain',
			'lib/components/RoutineEditor.svelte',
			"const named = exercises.filter((e) => e.name.trim() !== '');",
		],
		[
			'the receiver names one, the file otherwise does not',
			'lib/share/x.ts',
			"if (s.exercise_name === '') continue;",
		],
		['camelCase field', 'lib/social/z.ts', "if (set.exerciseName !== '') keep();"],
		['loose equality', 'lib/social/y.ts', "if (s.exercise_name == '') continue;"],
		['the literal on the left', 'lib/social/x.ts', "if ('' === s.exercise_name) continue;"],
		['a length test instead', 'lib/social/w.ts', 'if (s.exercise_name.length === 0) continue;'],
		[
			'a length test with the zero on the left',
			'lib/social/v.ts',
			'if (0 === s.exercise_name.length) continue;',
		],
		[
			'two declaration hops inside a file that names an exercise',
			'lib/components/Composer.svelte',
			"const exercises = [];\n\tconst raw = block.name;\n\tconst name = raw;\n\tif (name === '') continue;",
		],
		[
			"the picker's create path, whose value came from a search box through a rune",
			'lib/components/ExerciseCataloguePicker.svelte',
			"const catalogue = [];\n\tconst trimmed = $derived(query.trim());\n\tasync function create() {\n\t\tconst name = trimmed;\n\t\tif (name === '') return;\n\t\tawait createCustomExercise({ name });\n\t}",
		],
		[
			'the same call site written with the trimming chain the defect usually wears',
			'lib/components/ExerciseCataloguePicker.svelte',
			"const catalogue = [];\n\tconst trimmed = $derived(query.trim());\n\tasync function create() {\n\t\tconst name = trimmed;\n\t\tif (name.trim() === '') return;\n\t\tawait createCustomExercise({ name });\n\t}",
		],
		[
			'the same call site written as a length test',
			'lib/components/ExerciseCataloguePicker.svelte',
			"const catalogue = [];\n\tconst trimmed = $derived(query.trim());\n\tasync function create() {\n\t\tconst name = trimmed;\n\t\tif (name.length === 0) return;\n\t\tawait createCustomExercise({ name });\n\t}",
		],
		// The three shapes below are the ones the scan could not see until
		// § 1508, and two of them are how the defect was actually written.
		['blankness as an ordering test', 'lib/share/x.ts', 'const ok = s.exercise_name.trim().length > 0;'],
		['the same, below the boundary', 'lib/share/x.ts', 'if (s.exercise_name.trim().length < 1) continue;'],
		['the same, at the boundary', 'lib/share/x.ts', 'if (s.exercise_name.trim().length >= 1) keep();'],
		['blankness as a negation, with no comparison at all', 'lib/share/x.ts', 'if (!exerciseName.trim()) return null;'],
		[
			// The rule that reaches a broad module: the file is waived, the
			// subject is called `name`, and the enclosing declaration is what
			// says the value is an exercise.
			'a broad module, under a declaration that names an exercise',
			'lib/core/data.ts',
			'export async function fetchExerciseSetHistory(\n\tname: string\n) {\n\tif (!auth.user?.id || !name.trim()) return [];\n}',
		],
	];
	for (const [label, path, source] of caught) {
		assert.equal(blankSpellingTestHits(path, source).length, 1, `missed: ${label}`);
	}

	const spared: [string, string, string][] = [
		[
			'the fix itself',
			'lib/components/GymEditor.svelte',
			'let catalogue = $state<Exercise[]>([]);\n\t\t\tconst name = ex.name.trim();\n\t\t\tif (!namesAnExercise(name)) continue;',
		],
		[
			'the key tested directly, as every module that already holds one does',
			'lib/gym/gym_routine.ts',
			"const key = normaliseExerciseName(name);\n\tif (key === '') continue;",
		],
		[
			'a title trimmed in a file full of exercises',
			'lib/components/RoutineEditor.svelte',
			"const exercises = [];\n\tif (title.trim() === '') return;",
		],
		[
			'a numeric field in a file full of exercises',
			'lib/components/GymExecutionBand.svelte',
			"const step = exercise;\n\tconst reps = repsRaw.trim() === '' ? null : parseInt(repsRaw, 10);",
		],
		[
			'a .name blank test in a file that has nothing to do with exercises',
			'lib/social/club.ts',
			"if (club.name.trim() === '') return;",
		],
		['an identity test, which the raw-comparison scan owns', 'lib/gym/y.ts', 'if (last.name === s.exercise_name) merge();'],
		[
			'a count of blocks, whose declaration filtered on a name',
			'lib/components/RoutineEditor.svelte',
			"const named = exercises.filter((e) => namesAnExercise(e.name));\n\t\tif (named.length === 0) return null;",
		],
		['a null test', 'lib/gym/z.ts', 'if (s.exercise_name == null) continue;'],
		[
			'a comment describing the ban',
			'lib/gym/u.ts',
			"// never s.exercise_name.trim() === ''",
		],
		['a string mentioning it', 'lib/gym/t.ts', "const doc = \"s.exercise_name === ''\";"],
		[
			'the broad module, judged by the fold scan instead',
			'lib/core/data.ts',
			"const name = (row.movement_name ?? '').trim();\n\tif (name === '') continue;",
		],
		[
			// The ordering shapes admit a `.length` against 0 or 1 and nothing
			// else, so a list count in a file full of exercises is untouched —
			// `exerciseProgress` has two of these.
			'a list counted in a file that names an exercise',
			'lib/gym/exercise_history.ts',
			'const exercises = [];\n\tconst first = withE1rm.length > 0 ? withE1rm[0] : null;',
		],
		[
			'a minimum-length rule, which is a different claim',
			'lib/share/x.ts',
			'if (s.exercise_name.trim().length >= 3) keep();',
		],
		[
			// `receiverOf` carries `!` for the non-null assertion, so the
			// negation pass reads it out of the chain — and an inequality ends
			// in `=`, not `!`.
			'an inequality against a trimmed value, which is not a negation',
			'lib/share/x.ts',
			'if (key !== s.exercise_name.trim()) continue;',
		],
		[
			// A generic parameter matches the `<` the ordering shapes need and
			// is rejected on the operands rather than by excluding it up front.
			'a generic parameter in a file that names an exercise',
			'lib/components/GymEditor.svelte',
			'let catalogue = $state<Exercise[]>([]);',
		],
		[
			'a broad module, under a declaration that names nothing of the kind',
			'lib/core/data.ts',
			"const exercises = [];\nexport async function createClub(input) {\n\tif (!input.name.trim()) throw new Error('x');\n}",
		],
		[
			// The fold's own trim, and the display-spelling trim beside it, are
			// operations rather than blankness decisions — neither is a
			// comparison and neither is negated.
			'the display spelling trimmed before an insert decides on the key',
			'lib/core/data.ts',
			'export async function createCustomExercise(input) {\n\tconst name = input.name.trim();\n\tif (!namesAnExercise(name)) return null;\n}',
		],
	];
	for (const [label, path, source] of spared) {
		assert.deepEqual(blankSpellingTestHits(path, source), [], `false positive: ${label}`);
	}

	// The picker's own file, as it stands, plus the regression the three cases
	// above plant into it. Read from disk rather than restated, because what
	// makes the call site reachable is a property of the FILE — it names an
	// exercise, and the value under test is called `name` — and a restatement
	// would keep passing after the file stopped having it.
	const picker = 'lib/components/ExerciseCataloguePicker.svelte';
	const source = readFileSync(join(SRC, picker), 'utf-8');
	assert.deepEqual(blankSpellingTestHits(picker, source), [], 'the picker create path is fixed');
	assert.equal(
		blankSpellingTestHits(
			picker,
			source.replace(
				'if (!namesAnExercise(name) || creating) return;',
				"if (name === '' || creating) return;",
			),
		).length,
		1,
		'a regression at the picker create path must fail this scan',
	);
});

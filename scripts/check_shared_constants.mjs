#!/usr/bin/env node
// Guardrail: a constant with more than one home, where at least one home is
// not TypeScript, still says the same thing in every one of them.
//
// Why this exists: decisions.md § 787. Two registries already police
// duplication in this repo and neither covers this shape.
// `check_parity_pair_registry.mjs` covers TS<->Dart parity PAIRS — pure-logic
// modules, both in a language a `.test.ts`/`_test.dart` mirror pair can read.
// `apps/web/scripts/check_constraint_unions.mjs` covers a CHECK constraint's
// value set against the narrow TS union that mirrors it. Between them sits the
// class this file registers: a threshold, a bucket boundary, a vocabulary or an
// eligibility list copied into SQL, or copied from SQL into two clients, or
// copied from one SQL function into the next.
//
// § 641 is the standing lesson — `turn_cues` diverged in all THREE of its
// implementations at once, and nothing caught it because the pair was
// registered in no registry, "so its divergence was never detectable". The
// same thing had already happened to a value in this class and stayed
// undetected for over a year: `20260504_001` added `'watch'` to
// `personal_records()`'s eligible-source filter with a comment saying that
// without it "the migration that fixes the source value would silently drop
// all watch-recorded runs from PB calculations", and `20260710_001` — a
// search_path hardening pass that touched nothing else about the function —
// re-issued the ORIGINAL body and dropped `'watch'` back out. #378's later
// widening to `'parkrun'`/`'race'` reached the two sibling functions and never
// reached this one.
//
// The registry lives in this file rather than in markdown, deliberately. A
// registry written down twice is a registry that can disagree with itself,
// which is the defect § 604 records about the parity-pair list; and a markdown
// registry can only be checked for self-consistency, where this one reads the
// rails themselves and compares the values. That is `check_watch_ble_uuids.mjs`'s
// design (it "parses both sources rather than transcribing either") applied to
// a class rather than to one table.
//
// What is deliberately NOT registered here, because a guard already reads it:
//   - the watch<->phone GATT UUIDs        -> scripts/check_watch_ble_uuids.mjs
//   - a CHECK's value set vs its TS union -> apps/web/scripts/check_constraint_unions.mjs
//   - the AI-disclosure version ladder    -> both parity suites parse migration
//     20270511_001 (ai_disclosure.test.ts, ai_disclosure_test.dart)
//   - the `activity_type` label vocabulary and the text-length limits ->
//     activity_type_vocabulary.test.ts / text_limits.test.ts and their Dart
//     mirrors, each of which reads the migration
//   - the Strava lookback maximum -> a web guard in strava_sync_result.test.ts
//     reads the Edge Function's own bound
// And what is not registered because it is not extractable: `challenge_goal`'s
// streak ceiling is a FORMULA (`floor(window / one day) + 1`) written three
// times, not a literal. Comparing the `86400` out of it would certify nothing
// about the shape around it; that pair is pinned by its two mirror suites.
//
// Run: `node scripts/check_shared_constants.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list. That job is deliberately not
//      gated on a non-docs diff, which suits a registry whose entries name
//      source files: it runs on every PR.
// Unit tests: `node --test scripts/check_shared_constants.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { splitSqlStatements } from '../apps/backend/scripts/sql_lex.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const MIGRATIONS_DIR = join(REPO_ROOT, 'apps/backend/supabase/migrations');

/**
 * One place a value is written, and the value found there.
 * @typedef {{ key: string, where: string, values: string[] }} Site
 *
 * One rail of an entry: a language / file / generated surface holding the
 * value. `sites` may return more than one — the SQL rail of the run-source
 * entry returns one per live function that filters on it.
 * @typedef {{ label: string, sites: (ctx: Ctx) => Site[] }} Rail
 *
 * `match: 'all'`  every site on every rail carries the same values.
 * `match: 'key'`  sites are paired across rails by `key`; every rail must
 *                 carry the same key set, and paired sites must agree.
 * `compare: 'set'` order is not part of the value (a SQL `in` list, a bucket
 *                 vocabulary); `'ordered'` when it is (ascending bounds,
 *                 tier ladders).
 * @typedef {{
 *   name: string,
 *   why: string,
 *   match: 'all' | 'key',
 *   compare: 'set' | 'ordered',
 *   rails: Rail[],
 * }} Entry
 *
 * @typedef {{ read: (relPath: string) => string, sql: SqlIndex }} Ctx
 * @typedef {{ live: Map<string, { file: string, sql: string }>, statements: { file: string, sql: string }[] }} SqlIndex
 */

// ── SQL: what the migration set leaves behind ───────────────────────────────

// A migration set is a REPLAY, not a snapshot: the body a function has in
// production is the one the last `create or replace function` for that name
// wrote, which is routinely in a migration whose filename is about something
// else entirely (the run-source regression above arrived in a file named
// `_database_functions_search_path`). Reading any single migration therefore
// certifies nothing. Statements come from the Postgres lexer rather than a
// regex split so a `$$` body's own semicolons do not fragment it and a
// commented-out definition cannot register as live.
/**
 * @param {string} [dir]
 * @returns {SqlIndex}
 */
export function indexMigrations(dir = MIGRATIONS_DIR) {
	/** @type {Map<string, { file: string, sql: string }>} */
	const live = new Map();
	/** @type {{ file: string, sql: string }[]} */
	const statements = [];
	const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
	for (const file of files) {
		for (const sql of splitSqlStatements(readFileSync(join(dir, file), 'utf-8'))) {
			statements.push({ file, sql });
			const created = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/i.exec(sql);
			if (created) {
				live.set(created[1].toLowerCase(), { file, sql });
				continue;
			}
			const dropped = /^\s*drop\s+function\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/i.exec(sql);
			if (dropped) live.delete(dropped[1].toLowerCase());
		}
	}
	if (live.size === 0) {
		throw new Error(
			'check_shared_constants: parsed no function definitions out of the ' +
				'migrations. Every SQL rail below would report an empty set, which ' +
				'reads as agreement.',
		);
	}
	return { live, statements };
}

/** @param {string} list @returns {string[]} */
function sqlStringList(list) {
	return [...list.matchAll(/'([^']*)'/g)].map((m) => m[1]);
}

// ── Entry: the eligible-run source vocabulary ───────────────────────────────

const RUNS_SOURCE_IN = /\bsource\s+in\s*\(([^)]*)\)/gi;
/** A live function that reads the `runs` table itself, not a transition table. */
const READS_RUNS = /\b(?:from|join|update|into)\s+(?:public\.)?runs\b/i;

// A `source in (…)` filter on the `runs` table that is DELIBERATELY narrower
// than the column's own vocabulary belongs here with its reason, exactly as
// `check_watch_ble_uuids.mjs`'s UNCLAIMED holds a firmware row the phone
// deliberately does not consume. Empty today, and the rule stays: every live
// filter is the full eligible-run set, so the only thing a narrowing can mean
// right now is that a widening missed a copy.
/** @type {readonly string[]} */
export const NARROWED_RUN_SOURCE_FILTERS = [];

/** @param {Ctx} ctx @returns {Site[]} */
function runsSourceCheckSites(ctx) {
	/** @type {Site | null} */
	let last = null;
	for (const { file, sql } of ctx.sql.statements) {
		if (!/constraint\s+runs_source_check/i.test(sql)) continue;
		const clause = /check\s*\(\s*source\s+in\s*\(([^)]*)\)/i.exec(sql);
		if (!clause) continue;
		last = { key: 'runs.source', where: `${file} (runs_source_check)`, values: sqlStringList(clause[1]) };
	}
	return last === null ? [] : [last];
}

/** @param {Ctx} ctx @returns {Site[]} */
function runsSourceFilterSites(ctx) {
	/** @type {Site[]} */
	const out = [];
	for (const [name, { file, sql }] of ctx.sql.live) {
		if (!READS_RUNS.test(sql)) continue;
		if (NARROWED_RUN_SOURCE_FILTERS.includes(name)) continue;
		/** @type {Set<string>} */
		const seen = new Set();
		RUNS_SOURCE_IN.lastIndex = 0;
		/** @type {RegExpExecArray | null} */
		let m;
		while ((m = RUNS_SOURCE_IN.exec(sql)) !== null) {
			const values = sqlStringList(m[1]);
			const fingerprint = [...values].sort().join(',');
			if (seen.has(fingerprint)) continue;
			seen.add(fingerprint);
			out.push({ key: 'runs.source', where: `${name}() in ${file}`, values });
		}
	}
	return out;
}

// ── Entry: the runners-nearby distance buckets ──────────────────────────────

// Anchored on the declaration's own name rather than on "the first array in
// the file": both rails are ordinary source files that will grow other arrays,
// and a guard that silently starts reading a different one is a guard that
// certifies the wrong value. The optional `<T>` absorbs Dart's explicit list
// type argument (`= <String>[…]`), which TypeScript writes on the other side
// of the `=` and Dart writes on this one.
/** @param {string} src @param {string} declName @returns {string | null} */
function bracketList(src, declName) {
	const decl = new RegExp(`\\b${declName}\\b[^=\\n]*=\\s*(?:<[^>]*>\\s*)?\\[([^\\]]*)\\]`).exec(src);
	return decl ? decl[1] : null;
}

/** @param {string} src @param {string} declName @returns {string[]} */
export function parseNumberList(src, declName) {
	const inner = bracketList(src, declName);
	return inner === null ? [] : [...inner.matchAll(/-?\d+(?:\.\d+)?/g)].map((m) => m[0]);
}

/** @param {string} body @returns {string[]} */
export function parseNearbyCase(body) {
	return [...body.matchAll(/when\s+[^\n]*?<\s*(\d+)\s*then\s+\d+/gi)].map((m) => m[1]);
}

// ── Entry: the off-route hysteresis and the Minetti GAP coefficients ────────

// A constant whose value is DERIVED from another in the same file is still a
// value this registry can read: the divisor comes out of the source like every
// other digit. Three of the four off-route rails write the re-arm as
// `threshold / 2`; the Wear OS one writes both numbers by hand, so a threshold
// change on the other three would leave its band asymmetric with nothing
// reporting it. Resolving the derivation is what lets all four be compared as
// the same ordered pair.
/**
 * @param {string} src
 * @param {string} declName
 * @returns {number | null}
 */
export function resolveNumber(src, declName) {
	const decl = new RegExp(`\\b${declName}\\b[^=\\n]*=\\s*([^;\\n]+)`).exec(src);
	if (!decl) return null;
	const rhs = decl[1].trim();
	const literal = /^-?\d+(?:\.\d+)?/.exec(rhs);
	if (literal) return Number(literal[0]);
	const derived = /^([A-Za-z_][A-Za-z0-9_.]*)\s*\/\s*(\d+(?:\.\d+)?)/.exec(rhs);
	if (!derived) return null;
	const base = resolveNumber(src, derived[1].replace(/^.*\./, ''));
	return base === null ? null : base / Number(derived[2]);
}

/** @param {string} src @param {string} threshold @param {string} rearm @returns {string[]} */
function hysteresisPair(src, threshold, rearm) {
	const a = resolveNumber(src, threshold);
	const b = resolveNumber(src, rearm);
	return a === null || b === null ? [] : [String(a), String(b)];
}

// The Wear OS rail compares against bare literals inside the composable rather
// than naming them, so it is read where it is used. Both numbers come from the
// two comparisons that actually drive the banner, never from the comment above
// them — a comment agreeing with itself is the § 793 failure exactly.
/** @param {string} src @returns {string[]} */
export function parseWearOffRoute(src) {
	const over = /offRouteDistanceM\s*>\s*(\d+(?:\.\d+)?)/.exec(src);
	const under = /offRouteDistanceM\s*<\s*(\d+(?:\.\d+)?)/.exec(src);
	return over && under ? [String(Number(over[1])), String(Number(under[1]))] : [];
}

// Minetti et al. 2002's 5th-order energy-cost fit, written as one expression on
// every rail. Identifiers are blanked before the numbers are read, because
// `i5` / `i4` / `i3` / `i2` are variable names carrying digits and reading
// those as coefficients would compare ten numbers where there are six.
/** @param {string} src @returns {string[]} */
export function parseMinettiCoefficients(src) {
	const line = src
		.split('\n')
		.map((l) => l.replace(/\/\/.*$/, ''))
		.find((l) => /\bi5\b/.test(l) && /\bi2\b/.test(l) && l.includes('*'));
	if (!line) return [];
	const bare = line.replace(/[A-Za-z_][A-Za-z0-9_]*/g, ' ');
	return [...bare.matchAll(/([+-])?\s*(\d+(?:\.\d+)?)/g)].map(
		(m) => `${m[1] === '-' ? '-' : ''}${m[2]}`,
	);
}

// ── Entry: the achievement tier ladders ─────────────────────────────────────

// One extractor for both clients: the two catalogues are written in different
// languages but the same shape — `id: '<family>'` opening a block, then one
// `threshold: <n>` per tier inside it. Reading them with one function is what
// makes "web and mobile agree" a property of the parse rather than of two
// regexes that could drift the way their subjects can.
/** @param {string} src @returns {Site[]} */
export function parseBadgeCatalogue(src) {
	/** @type {Site[]} */
	const out = [];
	const blocks = [...src.matchAll(/\bid:\s*'([a-z_]+)'/g)];
	for (let i = 0; i < blocks.length; i++) {
		const start = blocks[i].index ?? 0;
		const end = i + 1 < blocks.length ? blocks[i + 1].index ?? src.length : src.length;
		const thresholds = [...src.slice(start, end).matchAll(/\bthreshold:\s*(\d+)/g)].map((m) => m[1]);
		if (thresholds.length > 0) out.push({ key: blocks[i][1], where: `${blocks[i][1]} catalogue entry`, values: thresholds });
	}
	return out;
}

// The awarder writes one UNION branch per family: a `select '<family>'` naming
// it, then the `(values ('bronze',<thr>,1), …)` ladder it is graded against.
/** @param {string} body @returns {Site[]} */
export function parseAwarderLadders(body) {
	/** @type {Site[]} */
	const out = [];
	const branches = [...body.matchAll(/select\s+'([a-z_]+)'(?:::text)?/gi)];
	for (let i = 0; i < branches.length; i++) {
		const start = branches[i].index ?? 0;
		const end = i + 1 < branches.length ? branches[i + 1].index ?? body.length : body.length;
		const values = /\bvalues\s*(\([^;]*?\))\s*\)?\s*as\s+t\s*\(/i.exec(body.slice(start, end));
		if (!values) continue;
		const thresholds = [...values[1].matchAll(/\(\s*'[a-z]+'\s*,\s*(\d+)\s*,\s*\d+\s*\)/g)].map((m) => m[1]);
		if (thresholds.length > 0) out.push({ key: branches[i][1], where: `${branches[i][1]} branch`, values: thresholds });
	}
	return out;
}

// ── Entry: the strippable-image MIME allowlist ─────────────────────────────

// The photo buckets whose accepted types must BE the set the clients can strip
// (decisions § 557). `runs` and `exports` hold non-image payloads and are not
// in this class.
/** @type {readonly string[]} */
export const PHOTO_BUCKETS = ['run-photos', 'route-photos', 'club-photos', 'avatars'];

// A bucket's allowlist is set by an `insert into storage.buckets … values (…)`
// on creation and narrowed by `update storage.buckets set allowed_mime_types`
// later, so the value is the LAST statement that names both the bucket and the
// column — the same replay the function index does, one table over.
/** @param {SqlIndex} sql @param {readonly string[]} [buckets] @returns {Site[]} */
export function bucketMimeSites(sql, buckets = PHOTO_BUCKETS) {
	/** @type {Site[]} */
	const out = [];
	for (const bucket of buckets) {
		/** @type {Site | null} */
		let last = null;
		for (const { file, sql: statement } of sql.statements) {
			if (!/storage\.buckets/i.test(statement)) continue;
			if (!statement.includes(`'${bucket}'`)) continue;
			const arr = /allowed_mime_types[\s\S]{0,80}?array\s*\[([^\]]*)\]/i.exec(statement);
			if (!arr) continue;
			last = { key: bucket, where: `${bucket} in ${file}`, values: sqlStringList(arr[1]) };
		}
		if (last !== null) out.push(last);
	}
	return out;
}

/** @param {string} src @param {string} declName @returns {string[]} */
export function parseStringList(src, declName) {
	const inner = bracketList(src, declName);
	return inner === null ? [] : [...inner.matchAll(/'([^']*)'/g)].map((m) => m[1]);
}

// ── Entry: the Wear OS route push/persist cap ──────────────────────────────

/** @param {string} src @param {string} declName @returns {string[]} */
export function parseNamedInt(src, declName) {
	const decl = new RegExp(`\\b${declName}\\b[^=\\n]*=\\s*(-?\\d+)`).exec(src);
	return decl ? [decl[1]] : [];
}

// ── Entry: the rate-limit bucket vocabulary ─────────────────────────────────

const RATE_LIMIT_CALL =
	/(?:enforce_create_rate_limit|check_rate_limit_tiered|check_rate_limit)\s*\(\s*(?:[^,()]+,\s*)?'([a-z_]+)'/gi;

/** @param {Ctx} ctx @returns {Site[]} */
function rateLimitSqlSites(ctx) {
	/** @type {Set<string>} */
	const buckets = new Set();
	for (const { sql } of ctx.sql.live.values()) {
		RATE_LIMIT_CALL.lastIndex = 0;
		/** @type {RegExpExecArray | null} */
		let m;
		while ((m = RATE_LIMIT_CALL.exec(sql)) !== null) buckets.add(m[1]);
	}
	return [{ key: 'buckets', where: 'live rate-limit call sites in the migrations', values: [...buckets] }];
}

// -- Entry: the exercise-name normalisation contract ------------------------

// The whitespace class and the case-fold table behind `exercise_key`, which is
// a STORED grouping key derived on three rails. A disagreement does not throw:
// it silently splits one lifter's history into two exercises, or merges two
// into one. decisions.md § 790.
//
// The extractors below yield CODE POINTS in hex, never the source text, so a
// rail is free to spell a member however its language spells one -- `\t` in a
// JS regex literal, `\\t` inside a Dart string, `chr(9)` in SQL -- and the
// guard still compares the same thing.

// SQL builds its class by concatenating `chr(n)` calls, so the operators, the
// quotes and the whitespace between operands carry no members. A JS or Dart
// class is the literal text, where a space IS one -- hence the two modes.
/** @param {string} klass @returns {string} */
function stripSqlConcatenation(klass) {
	return klass.replace(/\|\||'|\s/g, '');
}

/**
 * @param {string} klass
 * @param {{ sql?: boolean }} [options]
 * @returns {number[]}
 */
export function parseCharClassCodePoints(klass, { sql = false } = {}) {
	const src = sql ? stripSqlConcatenation(klass) : klass.replace(/\\\\/g, '\\');
	/** @type {(number | '-')[]} */
	const tokens = [];
	/** @type {Record<string, number>} */
	const SHORT = { t: 9, n: 10, v: 11, f: 12, r: 13 };
	for (let i = 0; i < src.length; ) {
		const rest = src.slice(i);
		const chrCall = /^chr\((\d+)\)/.exec(rest);
		if (chrCall) {
			tokens.push(Number(chrCall[1]));
			i += chrCall[0].length;
			continue;
		}
		const uEsc = /^\\u\{?([0-9a-fA-F]{1,6})\}?/.exec(rest);
		if (uEsc) {
			tokens.push(parseInt(uEsc[1], 16));
			i += uEsc[0].length;
			continue;
		}
		const shortEsc = /^\\([tnvfr])/.exec(rest);
		if (shortEsc) {
			tokens.push(SHORT[shortEsc[1]]);
			i += 2;
			continue;
		}
		if (src[i] === '-') {
			tokens.push('-');
			i += 1;
			continue;
		}
		tokens.push(/** @type {number} */ (src.codePointAt(i)));
		i += String.fromCodePoint(/** @type {number} */ (src.codePointAt(i))).length;
	}
	/** @type {number[]} */
	const out = [];
	for (let k = 0; k < tokens.length; k++) {
		const prev = tokens[k - 1];
		const next = tokens[k + 1];
		if (tokens[k] === '-' && typeof prev === 'number' && typeof next === 'number') {
			for (let cp = prev + 1; cp <= next; cp++) out.push(cp);
			k += 1;
			continue;
		}
		const here = tokens[k];
		if (typeof here === 'number') out.push(here);
	}
	return out;
}

/** @param {number[]} cps @returns {string[]} */
function asHex(cps) {
	return cps.map((cp) => cp.toString(16).padStart(4, '0'));
}

// Anchored on the DECLARATION (`<name> … = …`) rather than on the first
// mention: both files name their class in a doc comment above the code, and a
// guard that silently reads a prose paragraph certifies nothing.
/** @param {string} src @param {string} declName @returns {string[]} */
export function parseNamedCharClass(src, declName) {
	const decl = new RegExp(`\\b${declName}\\b[^=\\n]{0,60}=[\\s\\S]{0,200}?\\[([\\s\\S]*?)\\]\\+`).exec(src);
	return decl === null ? [] : asHex(parseCharClassCodePoints(decl[1]));
}

// A `'<from>': '<to>'` table written the same way in TypeScript and in Dart.
/** @param {string} src @param {string} declName @returns {string[]} */
export function parseCaseFoldMap(src, declName) {
	const decl = new RegExp(`\\b${declName}\\b[^=\\n]{0,60}=[\\s\\S]{0,60}?\\{([\\s\\S]*?)\\}`).exec(src);
	if (decl === null) return [];
	const cp = (/** @type {string} */ t) => asHex(parseCharClassCodePoints(t)).join('+');
	return [...decl[1].matchAll(/'((?:\\u[0-9a-fA-F]{4}|[^'])+)'\s*:\s*'((?:\\u[0-9a-fA-F]{4}|[^'])+)'/g)].map(
		(m) => `${cp(m[1])}>${cp(m[2])}`,
	);
}

// The argument list of `name(...)` in `body`, split on its TOP-LEVEL commas --
// every argument here is itself a call, so a regex split lands inside one.
/** @param {string} body @param {string} name @returns {string[]} */
export function callArguments(body, name) {
	const open = body.indexOf(`${name}(`);
	if (open < 0) return [];
	let depth = 0;
	let current = '';
	/** @type {string[]} */
	const args = [];
	for (let i = open + name.length; i < body.length; i++) {
		const ch = body[i];
		if (ch === '(') {
			depth += 1;
			if (depth === 1) continue;
		} else if (ch === ')') {
			depth -= 1;
			if (depth === 0) {
				args.push(current);
				return args;
			}
		} else if (ch === ',' && depth === 1) {
			args.push(current);
			current = '';
			continue;
		}
		current += ch;
	}
	return [];
}

/** The one live SQL function allowed to spell the class out. */
const SQL_EXERCISE_NORMALISER = 'collapse_exercise_whitespace';

/** @param {Ctx} ctx @returns {Site[]} */
function exerciseClassSqlSites(ctx) {
	/** @type {Site[]} */
	const out = [];
	for (const [name, { file, sql }] of ctx.sql.live) {
		// The definition itself, plus any OTHER live function that still rolls its
		// own -- an inlined `\s+` parses to no code points, which the empty-value
		// check reports rather than letting it agree with everything.
		const rollsItsOwn =
			name !== SQL_EXERCISE_NORMALISER &&
			/exercise_name/i.test(sql) &&
			/regexp_replace\s*\(/i.test(sql);
		if (name !== SQL_EXERCISE_NORMALISER && !rollsItsOwn) continue;
		const klass = /\[([\s\S]*?)\]\+/.exec(sql);
		out.push({
			key: 'whitespace',
			where: `${name}() in ${file}`,
			values: klass === null ? [] : asHex(parseCharClassCodePoints(klass[1], { sql: true })),
		});
	}
	return out;
}

// SQL writes the same table as a `translate(expr, from, to)` pair of chr()
// runs, which is one mapping per position.
/** @param {Ctx} ctx @returns {Site[]} */
function exerciseCaseFoldSqlSites(ctx) {
	const live = ctx.sql.live.get('normalise_exercise_name');
	if (!live) return [];
	const where = `normalise_exercise_name() in ${live.file}`;
	const args = callArguments(live.sql, 'translate');
	if (args.length !== 3) return [{ key: 'case_folds', where, values: [] }];
	const from = asHex(parseCharClassCodePoints(args[1], { sql: true }));
	const to = asHex(parseCharClassCodePoints(args[2], { sql: true }));
	return [
		{
			key: 'case_folds',
			where,
			values: from.length === to.length ? from.map((f, i) => `${f}>${to[i]}`) : [],
		},
	];
}

// ── The registry ───────────────────────────────────────────────────────────

/** @type {readonly Entry[]} */
export const REGISTRY = [
	{
		name: 'runs.source eligible-run vocabulary',
		why:
			'Every filter that decides which runs count towards a personal record, ' +
			'a badge or a total names the source values by hand. A copy that misses ' +
			'a widening drops a whole intake — watch, parkrun and race runs — out of ' +
			'that surface silently, and nothing rejects the row.',
		match: 'all',
		compare: 'set',
		rails: [
			{ label: 'runs_source_check (the column vocabulary)', sites: runsSourceCheckSites },
			{ label: 'live SQL functions filtering runs.source', sites: runsSourceFilterSites },
		],
	},
	{
		name: 'runners-nearby distance buckets',
		why:
			'The coarse buckets opt-in discovery reports instead of metres. If the ' +
			'phone and the web disagree with the SQL CASE, two clients state a ' +
			'different distance for the same pair of runners.',
		match: 'all',
		compare: 'ordered',
		rails: [
			{
				label: 'web (apps/web/src/lib/social/nearby.ts)',
				sites: (ctx) => [
					{
						key: 'bounds',
						where: 'NEARBY_BUCKET_BOUNDS_M',
						values: parseNumberList(ctx.read('apps/web/src/lib/social/nearby.ts'), 'NEARBY_BUCKET_BOUNDS_M'),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/nearby.dart)',
				sites: (ctx) => [
					{
						key: 'bounds',
						where: 'kNearbyBucketBoundsM',
						values: parseNumberList(ctx.read('apps/mobile_android/lib/nearby.dart'), 'kNearbyBucketBoundsM'),
					},
				],
			},
			{
				label: 'sql (discoverable_runners_near)',
				sites: (ctx) => {
					const fn = ctx.sql.live.get('discoverable_runners_near');
					if (!fn) return [];
					return [{ key: 'bounds', where: `discoverable_runners_near() in ${fn.file}`, values: parseNearbyCase(fn.sql) }];
				},
			},
		],
	},
	{
		name: 'achievement tier thresholds',
		why:
			'The clients render the ladder and compute what a runner has earned; ' +
			'the SQL awarder is what actually inserts the row. A threshold that ' +
			'disagrees shows a badge the server will never award, or awards one no ' +
			'surface explains.',
		match: 'key',
		compare: 'ordered',
		rails: [
			{
				label: 'web (apps/web/src/lib/social/badges.ts)',
				sites: (ctx) => parseBadgeCatalogue(ctx.read('apps/web/src/lib/social/badges.ts')),
			},
			{
				label: 'mobile (apps/mobile_android/lib/badges.dart)',
				sites: (ctx) => parseBadgeCatalogue(ctx.read('apps/mobile_android/lib/badges.dart')),
			},
			{
				label: 'sql (award_achievements_for_user)',
				sites: (ctx) => {
					const fn = ctx.sql.live.get('award_achievements_for_user');
					return fn ? parseAwarderLadders(fn.sql) : [];
				},
			},
		],
	},
	{
		name: 'rate-limit bucket vocabulary',
		why:
			'The bucket name is what a throttled caller is told. A bucket the SQL ' +
			'raises and the clients have no sentence for falls through to the ' +
			'generic wording, which names no activity and no wait.',
		match: 'all',
		compare: 'set',
		rails: [
			{ label: 'sql (live rate-limit call sites)', sites: rateLimitSqlSites },
			{
				label: 'web (apps/web/src/lib/i18n/rate_limit_message.ts)',
				sites: (ctx) => [
					{
						key: 'buckets',
						where: 'BUCKET_KEY',
						values: [...ctx.read('apps/web/src/lib/i18n/rate_limit_message.ts').matchAll(/^\t([a-z_]+):\s*'rateLimit\./gm)].map(
							(m) => m[1],
						),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/rate_limit_message.dart)',
				sites: (ctx) => [
					{
						key: 'buckets',
						where: 'rateLimitMessage switch',
						values: [...ctx.read('apps/mobile_android/lib/rate_limit_message.dart').matchAll(/case\s+'([a-z_]+)':/g)].map(
							(m) => m[1],
						),
					},
				],
			},
		],
	},
	{
		name: 'photo-bucket MIME allowlist',
		why:
			'decisions § 557 made the accepted image formats BE the formats the ' +
			'EXIF stripper can clean, because an accepted-but-unstrippable upload ' +
			'serves a geotagged original back through a signed URL. The bucket is ' +
			'the rail a raw storage upload actually meets, so a type listed there ' +
			'and nowhere else is the whole gap that ADR closes.',
		match: 'all',
		compare: 'set',
		rails: [
			{
				label: 'web (apps/web/src/lib/util/exif_strip.ts)',
				sites: (ctx) => [
					{
						key: 'mime',
						where: 'STRIPPABLE_IMAGE_MIME_TYPES',
						values: parseStringList(ctx.read('apps/web/src/lib/util/exif_strip.ts'), 'STRIPPABLE_IMAGE_MIME_TYPES'),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/exif_strip.dart)',
				sites: (ctx) => [
					{
						key: 'mime',
						where: 'kStrippableImageMimeTypes',
						values: parseStringList(ctx.read('apps/mobile_android/lib/exif_strip.dart'), 'kStrippableImageMimeTypes'),
					},
				],
			},
			{ label: 'sql (storage.buckets)', sites: (ctx) => bucketMimeSites(ctx.sql) },
		],
	},
	{
		name: 'Wear OS saved-route cap',
		why:
			'The watch persists at most this many routes, and the phone pushes at ' +
			'most this many. When the push cap was the larger of the two the watch ' +
			'showed the whole push in its live picker and kept only the first N, so ' +
			'the surplus vanished at the next restart with nothing reported.',
		match: 'all',
		compare: 'ordered',
		rails: [
			{
				label: 'watch (apps/watch_wear .../LocalRouteStore.kt)',
				sites: (ctx) => [
					{
						key: 'cap',
						where: 'LocalRouteStore.MAX_ROUTES',
						values: parseNamedInt(
							ctx.read('apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/LocalRouteStore.kt'),
							'MAX_ROUTES',
						),
					},
				],
			},
			{
				label: 'phone (apps/mobile_android/lib/wear_routes_bridge.dart)',
				sites: (ctx) => [
					{
						key: 'cap',
						where: 'WearRoutesBridge.kMaxRoutesPerPush',
						values: parseNamedInt(ctx.read('apps/mobile_android/lib/wear_routes_bridge.dart'), 'kMaxRoutesPerPush'),
					},
				],
			},
		],
	},
	{
		name: 'exercise-name whitespace class',
		why:
			'`gym_routine_exercises.exercise_key` is a STORED grouping key derived ' +
			'on three rails. A member one rail folds and another does not splits a ' +
			"lifter's history into two exercises, or merges two into one, with " +
			'nothing rejecting the row.',
		match: 'all',
		compare: 'set',
		rails: [
			{ label: 'sql (live functions deriving an exercise key)', sites: exerciseClassSqlSites },
			{
				label: 'web (apps/web/src/lib/gym/gym_prs.ts)',
				sites: (ctx) => [
					{
						key: 'whitespace',
						where: 'EXERCISE_WS',
						values: parseNamedCharClass(ctx.read('apps/web/src/lib/gym/gym_prs.ts'), 'EXERCISE_WS'),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/gym_prs.dart)',
				sites: (ctx) => [
					{
						key: 'whitespace',
						where: 'kExerciseWhitespace',
						values: parseNamedCharClass(
							ctx.read('apps/mobile_android/lib/gym_prs.dart'),
							'kExerciseWhitespace',
						),
					},
				],
			},
		],
	},
	{
		name: 'exercise-name case folds',
		why:
			"The code points the three rails' own case folding disagrees on, mapped " +
			'by hand so that none of them decides. JS full-lowercases U+0130 to `i` ' +
			"+ U+0307 where Dart and libc's towlower both yield a bare `i`; a rail " +
			'that stops applying the table silently re-keys every name holding one.',
		match: 'all',
		compare: 'set',
		rails: [
			{ label: 'sql (normalise_exercise_name)', sites: exerciseCaseFoldSqlSites },
			{
				label: 'web (apps/web/src/lib/gym/gym_prs.ts)',
				sites: (ctx) => [
					{
						key: 'case_folds',
						where: 'EXERCISE_CASE_MAP',
						values: parseCaseFoldMap(ctx.read('apps/web/src/lib/gym/gym_prs.ts'), 'EXERCISE_CASE_MAP'),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/gym_prs.dart)',
				sites: (ctx) => [
					{
						key: 'case_folds',
						where: 'kExerciseCaseMap',
						values: parseCaseFoldMap(
							ctx.read('apps/mobile_android/lib/gym_prs.dart'),
							'kExerciseCaseMap',
						),
					},
				],
			},
		],
	},
	{
		name: 'Apple Watch route point budget',
		why:
			'The phone thins a route to this many positions, the native bridge ' +
			're-checks the shape before queueing a durable WCSession transfer, and ' +
			'the watch drops the whole payload above it. A phone cap above the ' +
			"watch's queues a transfer the watch rejects on every retry, forever — " +
			'`transferUserInfo` is durable, so nothing gives up. The number lived in ' +
			'three languages behind a Dart test that read the two Swift files off ' +
			'disk and RETURNED SILENTLY when it could not (decisions § 793), so a ' +
			'rename on either Swift side left the pair unchecked and green.',
		match: 'all',
		compare: 'ordered',
		rails: [
			{
				label: 'phone dart (apps/mobile_android/lib/apple_watch_route_bridge.dart)',
				sites: (ctx) => [
					{
						key: 'cap',
						where: 'kMaxAppleWatchRoutePoints',
						values: parseNamedInt(
							ctx.read('apps/mobile_android/lib/apple_watch_route_bridge.dart'),
							'kMaxAppleWatchRoutePoints',
						),
					},
				],
			},
			{
				label: 'phone swift (apps/mobile_ios/ios/Runner/WatchIngestBridge.swift)',
				sites: (ctx) => [
					{
						key: 'cap',
						where: 'WatchIngestBridge.maxRoutePoints',
						values: parseNamedInt(
							ctx.read('apps/mobile_ios/ios/Runner/WatchIngestBridge.swift'),
							'maxRoutePoints',
						),
					},
				],
			},
			{
				label: 'watch swift (apps/watch_ios/WatchApp/ArmedRoute.swift)',
				sites: (ctx) => [
					{
						key: 'cap',
						where: 'ArmedRoute.maxPoints',
						values: parseNamedInt(
							ctx.read('apps/watch_ios/WatchApp/ArmedRoute.swift'),
							'maxPoints',
						),
					},
				],
			},
		],
	},
	{
		name: 'off-route hysteresis',
		why:
			'Alert past the threshold, re-arm only back under half of it. Four ' +
			'rails run the same latch — the watch firmware, the phone run screen, ' +
			'the Apple Watch navigator and the Wear OS banner — and a runner who ' +
			'gets a different answer from the wrist and the pocket about whether ' +
			'they are on the course trusts neither. Three rails derive the re-arm ' +
			'from the threshold; the Wear OS one writes both numbers by hand, so ' +
			'only a comparison across rails catches a threshold change that left ' +
			'its band asymmetric.',
		match: 'all',
		compare: 'ordered',
		rails: [
			{
				label: 'firmware (apps/custom_watch/core/src/course.rs)',
				sites: (ctx) => [
					{
						key: 'hysteresis',
						where: 'OFF_COURSE_THRESHOLD_M / OFF_COURSE_REARM_M',
						values: hysteresisPair(
							ctx.read('apps/custom_watch/core/src/course.rs'),
							'OFF_COURSE_THRESHOLD_M',
							'OFF_COURSE_REARM_M',
						),
					},
				],
			},
			{
				label: 'phone (apps/mobile_android/lib/screens/run_screen.dart)',
				sites: (ctx) => {
					const src = ctx.read('apps/mobile_android/lib/screens/run_screen.dart');
					const threshold = resolveNumber(src, '_offRouteThresholdMetres');
					return [
						{
							key: 'hysteresis',
							where:
								'_offRouteThresholdMetres (the re-arm is threshold / 2 at the call site)',
							values:
								threshold === null ? [] : [String(threshold), String(threshold / 2)],
						},
					];
				},
			},
			{
				label: 'apple watch (apps/watch_ios/WatchApp/RouteNavigator.swift)',
				sites: (ctx) => [
					{
						key: 'hysteresis',
						where: 'RouteNavigator.thresholdMetres / rearmMetres',
						values: hysteresisPair(
							ctx.read('apps/watch_ios/WatchApp/RouteNavigator.swift'),
							'thresholdMetres',
							'rearmMetres',
						),
					},
				],
			},
			{
				label: 'wear os (apps/watch_wear .../ui/RunWatchApp.kt)',
				sites: (ctx) => [
					{
						key: 'hysteresis',
						where: 'the offRouteDistanceM comparisons behind the banner',
						values: parseWearOffRoute(
							ctx.read(
								'apps/watch_wear/android/app/src/main/kotlin/com/runapp/watchwear/ui/RunWatchApp.kt',
							),
						),
					},
				],
			},
		],
	},
	{
		name: 'Minetti GAP polynomial coefficients',
		why:
			"Minetti et al. 2002's 5th-order energy-cost fit, written out as one " +
			'expression in four languages. Every grade-adjusted pace the product ' +
			'quotes comes off this polynomial, so a mistyped coefficient on one ' +
			'rail makes the same climb cost a different effort on the watch than on ' +
			'the phone — and it degrades gracefully enough that nothing would ' +
			'notice unless a test pinned the exact numbers.',
		match: 'all',
		compare: 'ordered',
		rails: [
			{
				label: 'web (apps/web/src/lib/runs/grade_adjusted_pace.ts)',
				sites: (ctx) => [
					{
						key: 'coefficients',
						where: 'minettiCostAtGrade',
						values: parseMinettiCoefficients(
							ctx.read('apps/web/src/lib/runs/grade_adjusted_pace.ts'),
						),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/grade_adjusted_pace.dart)',
				sites: (ctx) => [
					{
						key: 'coefficients',
						where: 'minettiCostAtGrade',
						values: parseMinettiCoefficients(
							ctx.read('apps/mobile_android/lib/grade_adjusted_pace.dart'),
						),
					},
				],
			},
			{
				label: 'firmware (apps/custom_watch/core/src/grade_adjusted_pace.rs)',
				sites: (ctx) => [
					{
						key: 'coefficients',
						where: 'minetti_cost_at_grade',
						values: parseMinettiCoefficients(
							ctx.read('apps/custom_watch/core/src/grade_adjusted_pace.rs'),
						),
					},
				],
			},
			{
				label: 'garmin (the Connect IQ GAP data field)',
				sites: (ctx) => [
					{
						key: 'coefficients',
						where: 'minettiCostAtGrade',
						values: parseMinettiCoefficients(ctx.read('apps/watch_garmin/source/GradeAdjustedPaceView.mc')),
					},
				],
			},
		],
	},
];

// ── Comparison ─────────────────────────────────────────────────────────────

/** @param {string[]} values @param {'set' | 'ordered'} compare @returns {string} */
function fingerprint(values, compare) {
	return (compare === 'set' ? [...values].sort() : values).join(', ');
}

/**
 * @param {Entry} entry
 * @param {Ctx} ctx
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkEntry(entry, ctx) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	/** @type {{ label: string, sites: Site[] }[]} */
	const rails = entry.rails.map((rail) => ({ label: rail.label, sites: rail.sites(ctx) }));

	// A rail that reads nothing is the failure mode a comparison cannot see:
	// two empty sets agree. Report it as the guard going blind, not as a match.
	// Two shapes of the same failure, and the second was found by hitting it:
	// a rail that yields NO sites, and a rail that yields a site carrying no
	// values. Neither is a disagreement a comparison can see — an empty list
	// fingerprints to the empty string and would match another empty one — so
	// both are reported as the guard going blind on that rail.
	for (const rail of rails) {
		if (rail.sites.length === 0) {
			errors.push(
				`${entry.name}: rail "${rail.label}" produced no sites.\n` +
					`  Either the value moved or the shape it is written in changed. ` +
					`This guard is blind on that rail until its extractor is taught the ` +
					`new form — an empty rail would otherwise agree with every other one.`,
			);
			continue;
		}
		for (const site of rail.sites) {
			if (site.values.length > 0) continue;
			errors.push(
				`${entry.name}: rail "${rail.label}" read no values at ${site.where}.\n` +
					`  The site was found but its contents were not, so the extractor no ` +
					`longer understands the shape it is written in.`,
			);
		}
	}
	if (errors.length > 0) return { errors, ok };

	if (entry.match === 'key') {
		const keySets = rails.map((r) => new Set(r.sites.map((s) => s.key)));
		const union = new Set(rails.flatMap((r) => r.sites.map((s) => s.key)));
		for (const key of [...union].sort()) {
			const missing = rails.filter((_, i) => !keySets[i].has(key)).map((r) => r.label);
			if (missing.length > 0) {
				errors.push(
					`${entry.name}: "${key}" is written on ${rails.length - missing.length} of ` +
						`${rails.length} rails — missing from ${missing.join(' and ')}.\n` +
						`  ${entry.why}`,
				);
				continue;
			}
			const found = rails.map((r) => ({
				label: r.label,
				site: /** @type {Site} */ (r.sites.find((s) => s.key === key)),
			}));
			const reference = found[0];
			const refPrint = fingerprint(reference.site.values, entry.compare);
			const disagree = found.slice(1).filter((f) => fingerprint(f.site.values, entry.compare) !== refPrint);
			if (disagree.length === 0) {
				ok.push(`${entry.name} / ${key}: ${refPrint}`);
				continue;
			}
			errors.push(
				`${entry.name}: "${key}" disagrees across rails.\n` +
					`  ${reference.label}\n    ${reference.site.where}: [${refPrint}]\n` +
					disagree
						.map((f) => `  ${f.label}\n    ${f.site.where}: [${fingerprint(f.site.values, entry.compare)}]`)
						.join('\n') +
					`\n  ${entry.why}`,
			);
		}
		return { errors, ok };
	}

	const sites = rails.flatMap((r) => r.sites.map((site) => ({ label: r.label, site })));
	const reference = sites[0];
	const refPrint = fingerprint(reference.site.values, entry.compare);
	const disagree = sites.slice(1).filter((s) => fingerprint(s.site.values, entry.compare) !== refPrint);
	if (disagree.length === 0) {
		ok.push(`${entry.name}: ${sites.length} site(s) agree on [${refPrint}]`);
		return { errors, ok };
	}
	for (const s of disagree) {
		const refValues = new Set(reference.site.values);
		const theirs = new Set(s.site.values);
		const absent = reference.site.values.filter((v) => !theirs.has(v));
		const extra = s.site.values.filter((v) => !refValues.has(v));
		errors.push(
			`${entry.name}: two homes disagree.\n` +
				`  ${reference.label}\n    ${reference.site.where}: [${refPrint}]\n` +
				`  ${s.label}\n    ${s.site.where}: [${fingerprint(s.site.values, entry.compare)}]\n` +
				(absent.length > 0 ? `  missing there: ${absent.join(', ')}\n` : '') +
				(extra.length > 0 ? `  only there:    ${extra.join(', ')}\n` : '') +
				`  ${entry.why}`,
		);
	}
	return { errors, ok };
}

/**
 * @param {readonly Entry[]} [registry]
 * @param {Ctx} [ctx]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(registry = REGISTRY, ctx = defaultContext()) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	for (const entry of registry) {
		const result = checkEntry(entry, ctx);
		errors.push(...result.errors);
		ok.push(...result.ok);
	}
	return { errors, ok };
}

/** @returns {Ctx} */
export function defaultContext() {
	return {
		read: (relPath) => readFileSync(join(REPO_ROOT, relPath), 'utf-8'),
		sql: indexMigrations(),
	};
}

function main() {
	const { errors, ok } = check();
	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);
	if (errors.length > 0) {
		console.error(
			`\n${errors.length} shared constant(s) disagree between their homes.\n` +
				`Each entry's rails are read from source, so the fix is to make the ` +
				`values match — not to update a transcription. decisions.md § 787.`,
		);
		return 1;
	}
	console.log(`\n${REGISTRY.length} registered shared constants agree across every home (${ok.length} checks).`);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

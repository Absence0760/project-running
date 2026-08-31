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
 * @typedef {{ live: Map<string, { file: string, sql: string }>, views: Map<string, { file: string, sql: string }>, statements: { file: string, sql: string }[] }} SqlIndex
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
	/** @type {Map<string, { file: string, sql: string }>} */
	const views = new Map();
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
			if (dropped) {
				live.delete(dropped[1].toLowerCase());
				continue;
			}
			// A view is replayed the same way, and anchored at the start of the
			// statement rather than searched for anywhere inside it: a function body
			// that itself issues DDL would otherwise register as a definition of the
			// view it names. The lexer has already dropped comments, so a historic
			// definition preserved in one cannot be picked up either.
			const viewCreated = /^\s*create\s+(?:or\s+replace\s+)?view\s+(?:public\.)?([a-z_][a-z0-9_]*)/i.exec(sql);
			if (viewCreated) {
				views.set(viewCreated[1].toLowerCase(), { file, sql });
				continue;
			}
			const viewDropped = /^\s*drop\s+view\s+(?:if\s+exists\s+)?(?:public\.)?([a-z_][a-z0-9_]*)/i.exec(sql);
			if (viewDropped) views.delete(viewDropped[1].toLowerCase());
		}
	}
	if (live.size === 0) {
		throw new Error(
			'check_shared_constants: parsed no function definitions out of the ' +
				'migrations. Every SQL rail below would report an empty set, which ' +
				'reads as agreement.',
		);
	}
	return { live, views, statements };
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

// ── Entry: the exercise-name whitespace class ──────────────────────

// The class is a character class on all three rails — a JS regex literal, a
// Dart RegExp source string (which doubles every backslash), and a Postgres
// ARE inside a SQL string literal — so one parser reads all three once the
// Dart doubling is collapsed. Ranges are EXPANDED, because the registered
// value is the set of code points and not its spelling: `\u2000-\u200a` on one
// rail and eleven separate escapes on another mean the same thing and must
// compare equal, while a rail that quietly drops U+2007 must not.
//
// The SQL rail is written with code-point escapes rather than `\s` for a
// reason this guard cannot check and the ADR records (decisions § 790): `\s`
// past ASCII is `[[:space:]]`, whose membership is the database's locale
// provider's opinion, so the old expression's answer moved between two
// deployments running the same migration set.
/** @param {string} src @param {string} anchor @returns {string[]} */
export function parseWhitespaceClass(src, anchor) {
	const at = src.indexOf(anchor);
	if (at < 0) return [];
	const open = src.indexOf('[', at);
	const close = src.indexOf(']', open);
	if (open < 0 || close < 0) return [];
	const body = src.slice(open + 1, close).replace(/\\\\/g, '\\');
	/** @type {number[]} */
	const out = [];
	const token = /\\u([0-9a-f]{4})(?:-\\u([0-9a-f]{4}))?/gi;
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = token.exec(body)) !== null) {
		const lo = parseInt(m[1], 16);
		const hi = m[2] === undefined ? lo : parseInt(m[2], 16);
		if (hi < lo || hi - lo > 0x400) return [];
		for (let cp = lo; cp <= hi; cp++) out.push(cp);
	}
	return [...new Set(out)]
		.sort((a, b) => a - b)
		.map((cp) => `U+${cp.toString(16).toUpperCase().padStart(4, '0')}`);
}

// ── Entry: the guided-run cue library ──────────────────────────────────────

// The only entry here whose subject is a DATA LIBRARY rather than a threshold
// or a vocabulary, and the reason registering `guided_runs` as a parity pair
// was not enough on its own. Both rails carry three workouts as literals — an
// id, a duration, and an ordered list of second marks — and each suite tests
// its own rail against itself ("ids are unique", "a finish cue at exactly
// duration"). Neither reads the other, so a cue added, moved or dropped on one
// rail passes both suites and every other guard in the tree, and the two
// surfaces then describe the same named workout differently: a different
// finish time under the same title, or a cue one platform lists and the other
// has never heard of. A registry line tells an agent to look; this is what
// fails the PR.
//
// Only the MARKS are compared. The cue text is a catalogue lookup on both
// rails and the key identifiers differ by convention — web's dotted
// `guidedRuns.easy30.cue0` against mobile's camelCase `guidedEasy30Cue0` —
// the same carve-out `badges` and `extended_nutrients` record for their own
// label keys.

export const WEB_GUIDED_RUNS = 'apps/web/src/lib/training/guided_runs.ts';
export const MOBILE_GUIDED_RUNS = 'apps/mobile_android/lib/guided_runs.dart';

/** Below this a parse has read a fragment of the library, not the library. */
export const GUIDED_RUN_MIN = 2;

/**
 * A second mark in the two forms both rails write: a bare integer, or minutes
 * times sixty. Deliberately not an evaluator — a mark spelled any other way is
 * a shape this guard cannot certify, and refusing it is the only honest
 * answer. Skipping it would drop a cue from one rail's compared list, which
 * the other rail cannot see and a comparison reads as agreement.
 * @param {string} expr @param {string} where @returns {number}
 */
export function parseGuidedSeconds(expr, where) {
	const text = expr.trim();
	const product = /^(\d+)\s*\*\s*60$/.exec(text);
	if (product !== null) return Number(product[1]) * 60;
	if (/^\d+$/.test(text)) return Number(text);
	throw new Error(
		`check_shared_constants: the guided-run library writes a second mark as ` +
			`"${text}" at ${where}. This guard evaluates a bare integer and ` +
			`\`<minutes> * 60\`; teach it the new form rather than leaving the mark ` +
			`uncompared.`,
	);
}

/**
 * One extractor for both rails, the way `parseBadgeCatalogue` reads two
 * catalogues written in different languages: a quoted `id` opens a block, then
 * the duration and the cue marks in whichever spelling its language uses
 * (`duration_sec` / `at_sec` in TypeScript, `durationSec` / `atSec` in Dart).
 *
 * Emits one site per run PLUS a `library order` site carrying the ids in
 * order, because `match: 'key'` compares key SETS: without it two rails
 * holding the same three workouts in a different order would agree, and the
 * order is what both surfaces list the library in.
 *
 * @param {string} src @param {string} anchor @param {string} where
 * @returns {Site[]}
 */
export function parseGuidedRunLibrary(src, anchor, where) {
	const at = src.indexOf(anchor);
	if (at < 0) {
		throw new Error(
			`check_shared_constants: no "${anchor}" in ${where}. The guided-run ` +
				`library moved or its signature changed, and a rail that reads nothing ` +
				`agrees with every other one.`,
		);
	}
	const body = src.slice(at);
	const ids = [...body.matchAll(/\bid:\s*'([a-z0-9-]+)'/g)];
	/** @type {Site[]} */
	const runs = [];
	for (let i = 0; i < ids.length; i++) {
		const start = ids[i].index ?? 0;
		const end = i + 1 < ids.length ? ids[i + 1].index ?? body.length : body.length;
		const block = body.slice(start, end);
		const id = ids[i][1];
		const site = `${id} in ${where}`;
		const duration = /\b(?:duration_sec|durationSec):\s*([^,\n]+)/.exec(block);
		if (duration === null) {
			throw new Error(
				`check_shared_constants: guided run "${id}" in ${where} carries no ` +
					`duration this guard can find. An uncompared duration is a workout ` +
					`whose countdown and finish cue can differ per platform.`,
			);
		}
		const cues = [...block.matchAll(/\b(?:at_sec|atSec):\s*([^,\n]+)/g)].map((m) =>
			parseGuidedSeconds(m[1], site),
		);
		if (cues.length === 0) {
			throw new Error(
				`check_shared_constants: guided run "${id}" in ${where} yielded no cue ` +
					`marks. A cue-less run compares equal to a cue-less run on the other ` +
					`rail, which is agreement about nothing.`,
			);
		}
		runs.push({
			key: id,
			where: site,
			values: [`duration=${parseGuidedSeconds(duration[1], site)}`, ...cues.map((s) => `cue@${s}`)],
		});
	}
	if (runs.length < GUIDED_RUN_MIN) {
		throw new Error(
			`check_shared_constants: read ${runs.length} guided run(s) out of ${where}, ` +
				`fewer than the ${GUIDED_RUN_MIN} that make it a library. The block shape ` +
				`changed and this guard would certify a fragment of it as the whole.`,
		);
	}
	return [{ key: 'library order', where: `run ids in ${where}`, values: runs.map((r) => r.key) }, ...runs];
}

// ── Entry: the public_runs metadata denylist ───────────────────────────────

// `public_runs.metadata` is a DENYLIST projection — `coalesce(r.metadata,'{}')
// - 'k1' - 'k2' …` — so every key `runs.metadata` grows is public to anonymous
// readers by default, and the one thing between a new key and the share page
// is somebody remembering a line. `rls_public_runs_view_denylist_test.sql`
// exists to make that memory unnecessary: it files a row carrying every
// stripped key, reads it back as `anon`, and its own header instructs the next
// author to extend the array.
//
// The instruction was ignored three times over. The array stood four keys
// behind the view — `watch_workout`, `safety_escalated_at`,
// `expected_return_at`, `guided_run_id` — and nothing could tell, because the
// test asserts the keys it NAMES rather than the keys the view STRIPS, so a
// shorter array passes exactly as green as a complete one. The failure the
// test was written to catch is therefore the one shape of failure it cannot
// see, and each of the four went unasserted from the migration that stripped
// it until this entry was added.
//
// Only the denylist is compared. The projected COLUMNS are a different
// question with its own rail (`database.types.ts` and the seed assertions),
// and the fixture deliberately carries public-safe keys the denylist must not
// name, so the two are not the same set.

export const PUBLIC_RUNS_DENYLIST_TEST =
	'apps/backend/supabase/tests/rls_public_runs_view_denylist_test.sql';

/**
 * The keys the metadata projection subtracts, read off ONE view definition.
 *
 * Anchored on the projection's two ends rather than on the file: `coalesce(…
 * metadata …` opens it and `as metadata` closes it, so a `- 'x'` anywhere else
 * in the view cannot join the set and a rewrite that drops either end is
 * reported instead of silently reading a shorter list.
 * @param {string} viewSql @param {string} where @returns {string[]}
 */
export function parseMetadataDenylist(viewSql, where) {
	const projection = /coalesce\s*\(\s*(?:[a-z_][a-z0-9_]*\.)?metadata\s*,[\s\S]*?\bas\s+metadata\b/i.exec(
		viewSql,
	);
	if (projection === null) {
		throw new Error(
			`check_shared_constants: no metadata projection in ${where}. This entry ` +
				`reads the \`coalesce(… metadata …) - 'key' … as metadata\` expression; ` +
				`the view kept its name and changed that shape, and a rail that reads ` +
				`nothing agrees with every other one.`,
		);
	}
	const keys = [...projection[0].matchAll(/-\s*'([^']*)'/g)].map((m) => m[1]);
	if (keys.length === 0) {
		throw new Error(
			`check_shared_constants: the metadata projection in ${where} subtracts no ` +
				`keys. An empty denylist is not a denylist — every owner-only key on ` +
				`the row would reach anonymous readers — and an empty set compares ` +
				`equal to whatever the test asserts.`,
		);
	}
	return keys;
}

/** @param {Ctx} ctx @returns {Site[]} */
export function publicRunsViewSites(ctx) {
	const view = ctx.sql.views.get('public_runs');
	if (view === undefined) {
		throw new Error(
			'check_shared_constants: the migration set defines no `public_runs` view. ' +
				'The live projection is the one the LAST `create or replace view ' +
				'public_runs` wrote, which is routinely in a migration named after ' +
				'something else; with none found this rail carries nothing.',
		);
	}
	const where = `public_runs in ${view.file}`;
	return [{ key: 'metadata denylist', where, values: parseMetadataDenylist(view.sql, where) }];
}

/**
 * The arguments of a call at `open` (the index of its `(`), balanced across
 * nesting and blind to parentheses inside string literals.
 * @param {string} sql @param {number} open @returns {string | null}
 */
function callArguments(sql, open) {
	let depth = 0;
	let quoted = false;
	for (let i = open; i < sql.length; i++) {
		const char = sql[i];
		if (quoted) {
			if (char !== "'") continue;
			if (sql[i + 1] === "'") i++;
			else quoted = false;
			continue;
		}
		if (char === "'") quoted = true;
		else if (char === '(') depth++;
		else if (char === ')' && --depth === 0) return sql.slice(open + 1, i);
	}
	return null;
}

/** @param {string} args @returns {string[]} */
function splitTopLevel(args) {
	/** @type {string[]} */
	const parts = [];
	let depth = 0;
	let quoted = false;
	let start = 0;
	for (let i = 0; i < args.length; i++) {
		const char = args[i];
		if (quoted) {
			if (char !== "'") continue;
			if (args[i + 1] === "'") i++;
			else quoted = false;
			continue;
		}
		if (char === "'") quoted = true;
		else if (char === '(' || char === '[') depth++;
		else if (char === ')' || char === ']') depth--;
		else if (char === ',' && depth === 0) {
			parts.push(args.slice(start, i));
			start = i + 1;
		}
	}
	parts.push(args.slice(start));
	return parts;
}

/**
 * The keys every `jsonb_build_object(…)` in the file builds — the bag the test
 * actually files. Odd arguments are values and are ignored; a key written as
 * anything but a bare literal is not counted, which fails loudly below rather
 * than vouching for coverage this parser cannot see. A key may be preceded by
 * `--` comment lines: the lexer leaves those in place inside a dollar-quoted
 * body (correctly — it is a string literal), and seed.sql annotates each group
 * of keys with the migration that added it.
 * @param {string[]} statements @returns {Set<string>}
 */
export function jsonbBuildObjectKeys(statements) {
	/** @type {Set<string>} */
	const keys = new Set();
	for (const sql of statements) {
		for (const call of [...sql.matchAll(/\bjsonb_build_object\s*\(/gi)]) {
			const args = callArguments(sql, (call.index ?? 0) + call[0].length - 1);
			if (args === null) continue;
			splitTopLevel(args).forEach((part, index) => {
				if (index % 2 !== 0) return;
				const literal = /^(?:\s*--[^\n]*\n)*\s*'([^']*)'\s*$/.exec(part);
				if (literal) keys.add(literal[1]);
			});
		}
	}
	return keys;
}

/**
 * The array the pgtap test asserts. The file goes through the Postgres lexer
 * first so the array's own `--` group comments cannot be read as content and a
 * commented-out array cannot be read as the live one.
 * @param {string} src @param {string} where @returns {string[]}
 */
export function parsePgtapDenylist(src, where) {
	/** @type {string | null} */
	let body = null;
	for (const sql of splitSqlStatements(src)) {
		const opener = /\bdenylist\s+text\s*\[\s*\]\s*:=\s*array\s*\[/i.exec(sql);
		if (opener === null) continue;
		const open = opener.index + opener[0].length - 1;
		const close = sql.indexOf(']', open);
		if (close < 0) continue;
		body = sql.slice(open + 1, close);
	}
	if (body === null) {
		throw new Error(
			`check_shared_constants: no \`denylist text[] := array[…]\` in ${where}. ` +
				`That array is what this entry holds the view against; renamed or moved, ` +
				`the rail reads nothing and agrees with every other one.`,
		);
	}
	const keys = [...body.matchAll(/'([^']*)'/g)].map((m) => m[1]);
	if (keys.length === 0) {
		throw new Error(
			`check_shared_constants: the \`denylist\` array in ${where} is empty. The ` +
				`test would then loop over nothing and pass against any view at all.`,
		);
	}
	return keys;
}

/**
 * The pgtap rail, and the one anti-vacuity check the set comparison cannot
 * make: the test reads its fixture row back and asserts each named key is
 * ABSENT, so a key the fixture never built is asserted against a bag that
 * could not have carried it — green whatever the view does with it.
 * @param {Ctx} ctx @returns {Site[]}
 */
export function pgtapDenylistSites(ctx) {
	const src = ctx.read(PUBLIC_RUNS_DENYLIST_TEST);
	const asserted = parsePgtapDenylist(src, PUBLIC_RUNS_DENYLIST_TEST);
	const built = jsonbBuildObjectKeys(splitSqlStatements(src));
	const unbuilt = asserted.filter((key) => !built.has(key));
	if (unbuilt.length > 0) {
		throw new Error(
			`check_shared_constants: ${PUBLIC_RUNS_DENYLIST_TEST} asserts ` +
				`${unbuilt.join(', ')} but its fixture never puts ${
					unbuilt.length === 1 ? 'that key' : 'those keys'
				} in the row. ` +
				`An absent key reads back absent whatever the view does with it, so the ` +
				`assertion passes without measuring anything. Add it to the ` +
				`jsonb_build_object above the array.`,
		);
	}
	return [
		{
			key: 'metadata denylist',
			where: `denylist array in ${PUBLIC_RUNS_DENYLIST_TEST}`,
			values: asserted,
		},
	];
}

export const PUBLIC_RUNS_SEED = 'apps/backend/supabase/seed.sql';

/**
 * The keys `seed.sql`'s public_runs projection block asserts are gone.
 *
 * Anchored on the single `IF … THEN` whose body raises the strip-list
 * exception, because the same `v_public_metadata ? 'key'` spelling is used a
 * few lines above to assert that `activity_type` and `title` SURVIVE — reading
 * the file at large would fold those two into the denylist and report a
 * disagreement that is really two assertions pointing opposite ways.
 * @param {string} src @param {string} where @returns {string[]}
 */
export function parseSeedDenylist(src, where) {
	const block = /IF\s+v_public_metadata\s*\?[\s\S]*?strip list incomplete/i.exec(src);
	if (block === null) {
		throw new Error(
			`check_shared_constants: no public_runs strip-list assertion in ${where}. ` +
				`This entry reads the \`IF v_public_metadata ? '…' OR …\` chain whose ` +
				`body raises "strip list incomplete"; renamed or removed, the rail reads ` +
				`nothing and agrees with every other one.`,
		);
	}
	const keys = [...block[0].matchAll(/\?\s*'([^']*)'/g)].map((m) => m[1]);
	if (keys.length === 0) {
		throw new Error(
			`check_shared_constants: the strip-list assertion in ${where} names no ` +
				`keys, so it raises for nothing and passes against any view.`,
		);
	}
	return keys;
}

/** @param {Ctx} ctx @returns {Site[]} */
export function seedDenylistSites(ctx) {
	const src = ctx.read(PUBLIC_RUNS_SEED);
	const asserted = parseSeedDenylist(src, PUBLIC_RUNS_SEED);
	const built = jsonbBuildObjectKeys(splitSqlStatements(src));
	const unbuilt = asserted.filter((key) => !built.has(key));
	if (unbuilt.length > 0) {
		throw new Error(
			`check_shared_constants: ${PUBLIC_RUNS_SEED} asserts ${unbuilt.join(', ')} ` +
				`is stripped but the seeded public run never carries ` +
				`${unbuilt.length === 1 ? 'that key' : 'those keys'}. An absent key reads ` +
				`back absent whatever the view does with it, so the assertion passes ` +
				`without measuring anything.`,
		);
	}
	return [
		{
			key: 'metadata denylist',
			where: `public_runs strip-list assertion in ${PUBLIC_RUNS_SEED}`,
			values: asserted,
		},
	];
}

// ── Bounds: a client input bound against the column the database bounds ────

// A second registry, with a different comparison. The entries above ask
// whether every home says the SAME thing; these ask whether the client's bound
// sits INSIDE the database's, which is not the same question and is not
// symmetric. A client capped BELOW the column is merely conservative; one
// capped above — or not capped at all — hands the runner a raw postgres 23514
// (or a 22003 from the column's own `numeric(p,s)` precision, the same defect
// wearing a different SQLSTATE) that names a constraint and no field.
//
// The registry is the client module itself: `COLUMN_LIMITS` / `kColumnLimits`
// are keyed by `<table>.<column>`, so the key IS the locator and this file
// holds no copy of any number. decisions.md § 792.

export const WEB_COLUMN_LIMITS = 'apps/web/src/lib/core/column_limits.ts';
export const MOBILE_COLUMN_LIMITS = 'apps/mobile_android/lib/column_limits.dart';

/**
 * One extractor for both clients, the way `parseBadgeCatalogue` reads two
 * catalogues written in different languages: a quoted `<table>.<column>` key,
 * then the kind and the integers of whichever form its language spells the
 * bound in — a TS object literal or a Dart const constructor.
 * @param {string} src
 * @returns {Map<string, { kind: string, values: number[] }>}
 */
export function parseColumnLimits(src) {
	/** @type {Map<string, { kind: string, values: number[] }>} */
	const out = new Map();
	const re = /'([a-z_]+\.[a-z_]+)':\s*(\{[^}]*\}|ColumnLimit\.[a-z]+\([^)]*\))/g;
	/** @type {RegExpExecArray | null} */
	let m;
	while ((m = re.exec(src)) !== null) {
		const body = m[2];
		const kind = /'value'|\.value\(/.test(body) ? 'value' : /'length'|\.length\(/.test(body) ? 'length' : '';
		if (kind === '') continue;
		out.set(m[1], { kind, values: [...body.matchAll(/-?\d+(?:\.\d+)?/g)].map((n) => Number(n[0])) });
	}
	return out;
}

/**
 * Every balanced `check ( … )` in a statement, with the constraint's name when
 * it has one. Balanced rather than `[^)]*` because every bound on a nullable
 * column is written `col is null or (col > 0 and col <= 300)`.
 * @param {string} sql
 * @returns {{ name: string | null, body: string }[]}
 */
export function checkBodies(sql) {
	/** @type {{ name: string | null, body: string }[]} */
	const out = [];
	let i = 0;
	for (;;) {
		const opener = /\bcheck\s*\(/i.exec(sql.slice(i));
		if (!opener) break;
		const start = i + opener.index + opener[0].length;
		let depth = 1;
		let j = start;
		while (j < sql.length && depth > 0) {
			if (sql[j] === '(') depth++;
			else if (sql[j] === ')') depth--;
			j++;
		}
		const named = /constraint\s+([a-z_][a-z0-9_]*)\s+check\s*\($/i.exec(sql.slice(0, start));
		out.push({ name: named ? named[1] : null, body: sql.slice(start, j - 1) });
		i = j;
	}
	return out;
}

/**
 * The bound a single CHECK body puts on one column: a value range, a
 * `char_length` cap, or neither.
 * @param {string} body
 * @param {string} column
 * @returns {{ min: number | null, minExclusive: boolean, max: number | null, maxExclusive: boolean, lengthMax: number | null }}
 */
export function boundFromCheck(body, column) {
	const ref = `(?:char_length|length)\\s*\\(\\s*(?:[a-z_]+\\.)?${column}\\s*\\)|(?:[a-z_]+\\.)?\\b${column}\\b`;
	const bound = {
		/** @type {number | null} */ min: null,
		minExclusive: false,
		/** @type {number | null} */ max: null,
		maxExclusive: false,
		/** @type {number | null} */ lengthMax: null,
	};
	/** @type {RegExpExecArray | null} */
	let m;
	const between = new RegExp(`(${ref})\\s+between\\s+(-?\\d+(?:\\.\\d+)?)\\s+and\\s+(-?\\d+(?:\\.\\d+)?)`, 'gi');
	while ((m = between.exec(body)) !== null) {
		if (/length/i.test(m[1])) bound.lengthMax = Number(m[3]);
		else {
			bound.min = Number(m[2]);
			bound.max = Number(m[3]);
		}
	}
	const compare = new RegExp(`(${ref})\\s*(<=|>=|<|>)\\s*(-?\\d+(?:\\.\\d+)?)`, 'gi');
	while ((m = compare.exec(body)) !== null) {
		const n = Number(m[3]);
		if (/length/i.test(m[1])) {
			if (m[2] === '<=') bound.lengthMax = n;
			else if (m[2] === '<') bound.lengthMax = n - 1;
			continue;
		}
		if (m[2] === '<=') bound.max = n;
		else if (m[2] === '<') {
			bound.max = n;
			bound.maxExclusive = true;
		} else if (m[2] === '>=') bound.min = n;
		else {
			bound.min = n;
			bound.minExclusive = true;
		}
	}
	return bound;
}

/** The largest magnitude a `numeric(p, s)` column can hold. */
/** @param {number} precision @param {number} scale @returns {number} */
export function numericCeiling(precision, scale) {
	return 10 ** (precision - scale) - 10 ** -scale;
}

/**
 * The bound the migration set leaves on one column, by REPLAY: every live CHECK
 * that names it, intersected, plus the ceiling its `numeric(p, s)` declaration
 * imposes on its own. A `drop constraint` removes the named one it drops, the
 * same replay the function index does one object over.
 * @param {SqlIndex} sql
 * @param {string} table
 * @param {string} column
 */
export function sqlColumnBound(sql, table, column) {
	const touches = new RegExp(
		`(?:create\\s+table\\s+(?:if\\s+not\\s+exists\\s+)?|alter\\s+table\\s+(?:if\\s+exists\\s+)?(?:only\\s+)?)(?:public\\.)?${table}\\b`,
		'i',
	);
	/** @type {{ name: string | null, file: string, bound: ReturnType<typeof boundFromCheck> }[]} */
	let live = [];
	/** @type {number | null} */
	let precisionMax = null;
	/** @type {string[]} */
	const files = [];
	for (const { file, sql: statement } of sql.statements) {
		if (!touches.test(statement)) continue;
		const dropped = /drop\s+constraint\s+(?:if\s+exists\s+)?([a-z_][a-z0-9_]*)/gi;
		/** @type {RegExpExecArray | null} */
		let d;
		while ((d = dropped.exec(statement)) !== null) {
			const name = d[1].toLowerCase();
			live = live.filter((c) => c.name !== name);
		}
		const declared = new RegExp(`\\b${column}\\s+numeric\\s*\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)`, 'i').exec(statement);
		if (declared) precisionMax = numericCeiling(Number(declared[1]), Number(declared[2]));
		for (const { name, body } of checkBodies(statement)) {
			const bound = boundFromCheck(body, column);
			if (bound.min === null && bound.max === null && bound.lengthMax === null) continue;
			live.push({ name: name === null ? null : name.toLowerCase(), file, bound });
			if (!files.includes(file)) files.push(file);
		}
	}
	/** @type {number | null} */
	let min = null;
	let minExclusive = false;
	/** @type {number | null} */
	let max = precisionMax;
	let maxExclusive = false;
	/** @type {number | null} */
	let lengthMax = null;
	for (const { bound } of live) {
		if (bound.min !== null && (min === null || bound.min > min)) {
			min = bound.min;
			minExclusive = bound.minExclusive;
		}
		if (bound.max !== null && (max === null || bound.max < max)) {
			max = bound.max;
			maxExclusive = bound.maxExclusive;
		}
		if (bound.lengthMax !== null && (lengthMax === null || bound.lengthMax < lengthMax)) {
			lengthMax = bound.lengthMax;
		}
	}
	return { min, minExclusive, max, maxExclusive, lengthMax, precisionMax, sites: live.length, files };
}

/**
 * @param {Ctx} ctx
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkColumnBounds(ctx) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const web = parseColumnLimits(ctx.read(WEB_COLUMN_LIMITS));
	const mobile = parseColumnLimits(ctx.read(MOBILE_COLUMN_LIMITS));
	if (web.size === 0 || mobile.size === 0) {
		errors.push(
			`column limits: read ${web.size} entries from ${WEB_COLUMN_LIMITS} and ` +
				`${mobile.size} from ${MOBILE_COLUMN_LIMITS}.\n` +
				`  A rail that reads nothing agrees with every other one, so this is ` +
				`reported as the guard going blind rather than as a match.`,
		);
		return { errors, ok };
	}
	for (const key of [...new Set([...web.keys(), ...mobile.keys()])].sort()) {
		const w = web.get(key);
		const mo = mobile.get(key);
		if (!w || !mo) {
			errors.push(
				`column limits: "${key}" is bounded on ${w ? 'web' : 'mobile'} only.\n` +
					`  The unbounded client is the one that hands the runner a raw 23514.`,
			);
			continue;
		}
		if (w.kind !== mo.kind || w.values.join(',') !== mo.values.join(',')) {
			errors.push(
				`column limits: "${key}" disagrees between the clients.\n` +
					`  web:    ${w.kind} [${w.values.join(', ')}]\n` +
					`  mobile: ${mo.kind} [${mo.values.join(', ')}]\n` +
					`  One number per field: a stricter phone silently truncates what the ` +
					`web accepted, and a looser one refuses what the web stored.`,
			);
			continue;
		}
		const [table, column] = key.split('.');
		const db = sqlColumnBound(ctx.sql, table, column);
		if (db.sites === 0 && db.precisionMax === null) {
			errors.push(
				`column limits: "${key}" has no CHECK and no numeric precision in the ` +
					`migrations.\n  Either the column moved or its bound was dropped; ` +
					`this guard certifies nothing about that key until one exists.`,
			);
			continue;
		}
		if (w.kind === 'length') {
			const [clientMax] = w.values;
			if (db.lengthMax === null) {
				errors.push(`column limits: "${key}" is capped at ${clientMax} characters on both clients, but no char_length CHECK bounds the column.`);
				continue;
			}
			if (clientMax > db.lengthMax) {
				errors.push(
					`column limits: "${key}" is capped ABOVE its own CHECK.\n` +
						`  clients: ${clientMax} characters\n  database: ${db.lengthMax} (${db.files.join(', ')})\n` +
						`  A composer capped above the constraint hands the user a 23514 they cannot act on.`,
				);
				continue;
			}
			ok.push(`column limits / ${key}: clients ${clientMax} <= database ${db.lengthMax} characters`);
			continue;
		}
		const [clientMin, clientMax] = w.values;
		/** @type {string[]} */
		const failed = [];
		if (db.min !== null && (db.minExclusive ? !(clientMin > db.min) : !(clientMin >= db.min))) {
			failed.push(`min ${clientMin} is not ${db.minExclusive ? '>' : '>='} the database's ${db.min}`);
		}
		if (db.max === null) failed.push('the database bounds this column from below only, and nothing caps the client');
		else if (db.maxExclusive ? !(clientMax < db.max) : !(clientMax <= db.max)) {
			failed.push(`max ${clientMax} is not ${db.maxExclusive ? '<' : '<='} the database's ${db.max}`);
		}
		if (failed.length > 0) {
			errors.push(
				`column limits: "${key}" is not inside its own CHECK.\n` +
					`  ${failed.join('\n  ')}\n` +
					`  database: ${db.min === null ? '(none)' : `${db.minExclusive ? '>' : '>='} ${db.min}`}, ` +
					`${db.max === null ? '(none)' : `${db.maxExclusive ? '<' : '<='} ${db.max}`}` +
					`${db.precisionMax !== null ? ` (numeric precision ceiling ${db.precisionMax})` : ''}` +
					`${db.files.length > 0 ? ` — ${db.files.join(', ')}` : ''}\n` +
					`  A value the client admits and the column rejects is a raw postgres ` +
					`error the runner cannot act on.`,
			);
			continue;
		}
		ok.push(
			`column limits / ${key}: clients [${clientMin}, ${clientMax}] inside database ` +
				`(${db.min === null ? '-inf' : db.min}, ${db.max === null ? 'inf' : db.max})`,
		);
	}
	return { errors, ok };
}

// ── Bounds: the create rate-limit ceilings ─────────────────────────────────

// `enforce_create_rate_limit(bucket, user, max, window_s)` carries its numbers
// at the call site, and `check_rate_limit` keys the counter by BUCKET — so two
// live call sites debiting one bucket with two different ceilings give the
// caller a limit that depends on which path they took last, and the refusal
// can name neither. The doc table is the second home the numbers already had
// in prose; this reads it rather than trusting it.

export const RATE_LIMIT_DOC = 'docs/backend/api_database.md';

const RATE_LIMIT_ENFORCE =
	/enforce_create_rate_limit\s*\(\s*'([a-z_]+)'\s*,\s*[^,]+,\s*(\d+)\s*,\s*(\d+)\s*\)/gi;

/** @param {Ctx} ctx @returns {Site[]} */
export function rateLimitCeilingSqlSites(ctx) {
	/** @type {Map<string, Site>} */
	const byBucket = new Map();
	/** @type {string[]} */
	const conflicts = [];
	for (const [name, { file, sql }] of ctx.sql.live) {
		RATE_LIMIT_ENFORCE.lastIndex = 0;
		/** @type {RegExpExecArray | null} */
		let m;
		while ((m = RATE_LIMIT_ENFORCE.exec(sql)) !== null) {
			const values = [m[2], m[3]];
			const seen = byBucket.get(m[1]);
			if (seen && seen.values.join('/') !== values.join('/')) {
				conflicts.push(`${m[1]}: ${seen.where} says ${seen.values.join('/')}, ${name}() says ${values.join('/')}`);
				continue;
			}
			byBucket.set(m[1], { key: m[1], where: `${name}() in ${file}`, values });
		}
	}
	if (conflicts.length > 0) {
		throw new Error(
			`check_shared_constants: one rate-limit bucket, two ceilings — ${conflicts.join('; ')}. ` +
				`check_rate_limit keys the counter by bucket, so the caller's real limit ` +
				`is whichever call site ran, and the refusal names neither.`,
		);
	}
	return [...byBucket.values()];
}

// A row of the "Create rate-limit buckets" table: `| \`bucket\` | 30 | 60 |`.
// Anchored on the backticked bucket name, which is what makes the guard read
// the row it means rather than the third number on the line.
/** @param {Ctx} ctx @returns {Site[]} */
export function rateLimitCeilingDocSites(ctx) {
	const doc = ctx.read(RATE_LIMIT_DOC);
	return [...doc.matchAll(/^\|\s*`([a-z_]+)`\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|/gm)].map((m) => ({
		key: m[1],
		where: `${RATE_LIMIT_DOC} bucket table`,
		values: [m[2], m[3]],
	}));
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
		name: 'create rate-limit ceilings',
		why:
			'The bucket vocabulary entry above proves every bucket has a sentence; ' +
			'this proves the sentence is about the limit the database actually ' +
			'enforces. The numbers live at the SQL call site and were transcribed ' +
			'into prose that nothing read, which is the shape that outlives the ' +
			'number it describes.',
		match: 'key',
		compare: 'ordered',
		rails: [
			{ label: 'sql (live enforce_create_rate_limit call sites)', sites: rateLimitCeilingSqlSites },
			{ label: `docs (${RATE_LIMIT_DOC})`, sites: rateLimitCeilingDocSites },
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
			'The exercise grouping key is derived on three rails and PERSISTED by ' +
			'the clients as gym_routine_exercises.exercise_key and ' +
			'exercises.name_key, while four SQL RPCs re-derive it from ' +
			'gym_sets.exercise_name at read time. A name one rail folds and another ' +
			'does not splits one exercise into two buckets: the local PR tracker ' +
			'says PR where gym_workout_summaries.is_pr says no, and ' +
			'gym_exercise_set_history returns an empty history for a lift that ' +
			'has one. Nothing rejects either row.',
		match: 'all',
		compare: 'set',
		rails: [
			{
				label: 'web (apps/web/src/lib/gym/gym_prs.ts)',
				sites: (ctx) => [
					{
						key: 'whitespace',
						where: 'EXERCISE_WS',
						values: parseWhitespaceClass(ctx.read('apps/web/src/lib/gym/gym_prs.ts'), 'EXERCISE_WS ='),
					},
				],
			},
			{
				label: 'mobile (apps/mobile_android/lib/gym_prs.dart)',
				sites: (ctx) => [
					{
						key: 'whitespace',
						where: 'kExerciseWhitespace',
						values: parseWhitespaceClass(
							ctx.read('apps/mobile_android/lib/gym_prs.dart'),
							'kExerciseWhitespace =',
						),
					},
				],
			},
			{
				label: 'sql (normalise_exercise_name)',
				sites: (ctx) => {
					const fn = ctx.sql.live.get('normalise_exercise_name');
					if (!fn) return [];
					return [
						{
							key: 'whitespace',
							where: `normalise_exercise_name() in ${fn.file}`,
							values: parseWhitespaceClass(fn.sql, 'regexp_replace'),
						},
					];
				},
			},
		],
	},
	{
		name: 'guided-run cue library',
		why:
			'A mark moved, a duration changed or a workout renamed on one rail ' +
			'passes both suites, because each tests its own rail against itself and ' +
			'neither reads the other. The two surfaces then describe the same named ' +
			'workout differently — a different finish time under the same title, or ' +
			'a cue one platform lists and the other has never heard of.',
		match: 'key',
		compare: 'ordered',
		rails: [
			{
				label: `web (${WEB_GUIDED_RUNS})`,
				sites: (ctx) =>
					parseGuidedRunLibrary(ctx.read(WEB_GUIDED_RUNS), 'guidedRunLibrary(t: GuidedTranslate', WEB_GUIDED_RUNS),
			},
			{
				label: `mobile (${MOBILE_GUIDED_RUNS})`,
				sites: (ctx) =>
					parseGuidedRunLibrary(
						ctx.read(MOBILE_GUIDED_RUNS),
						'guidedRunLibrary(AppLocalizations',
						MOBILE_GUIDED_RUNS,
					),
			},
		],
	},
	{
		name: 'public_runs metadata denylist',
		why:
			'The view projects metadata by SUBTRACTION, so a key added to ' +
			'runs.metadata reaches anonymous readers unless a migration strips it, ' +
			'and the pgtap suite is what proves each one is gone. The test asserts ' +
			'the keys it names rather than the keys the view strips, so an array ' +
			'left behind is still green — which is how four keys went unasserted ' +
			'from the migration that stripped each of them.',
		match: 'all',
		compare: 'set',
		rails: [
			{ label: 'sql (the live public_runs projection)', sites: publicRunsViewSites },
			{ label: `pgtap (${PUBLIC_RUNS_DENYLIST_TEST})`, sites: pgtapDenylistSites },
			{ label: `seed (${PUBLIC_RUNS_SEED})`, sites: seedDenylistSites },
		],
	},
	{
		name: 'Art 20 export user_profiles projection',
		why:
			'user_profiles reaches the export archive through an enumerated ' +
			'select rather than through exportPersonalDataSpecs, so the ' +
			'table-level completeness guard never covered it and eight columns ' +
			'were absent from every archive. height_cm is the sharpest: ' +
			'withdraw_health_data_consent() clears date_of_birth, gender and ' +
			'height_cm as ONE Art 9 set (decisions.md § 718) and the archive was ' +
			'exporting two of the three. The Go rail is the only one either ' +
			'client reaches today (§ 724), but the Edge Function rail is still ' +
			'deployed and a subject who reaches it must not get a thinner ' +
			'archive than one who does not.',
		match: 'all',
		compare: 'set',
		rails: [
			{
				label: 'go (apps/job_worker/internal/supabase.go FetchExportProfile)',
				sites: (ctx) => [
					{
						key: 'projection',
						where: 'FetchExportProfile q.Set("select", ...)',
						values: goExportProfileColumns(ctx.read('apps/job_worker/internal/supabase.go')),
					},
				],
			},
			{
				label: 'edge function (apps/backend/supabase/functions/export-data/backup_spec.ts)',
				sites: (ctx) => [
					{
						key: 'projection',
						where: 'PROFILE_SELECT',
						values: tsExportProfileColumns(
							ctx.read('apps/backend/supabase/functions/export-data/backup_spec.ts'),
						),
					},
				],
			},
		],
	},
];

/// The column list `FetchExportProfile` asks PostgREST for. Read out of the
/// Go string literal rather than matched in place, so a rail that stops being
/// extractable reports as blind instead of as empty.
///
/// The literal is located and then SLICED rather than matched by a repeated
/// group: `(?:"..."\s*\+?\s*)+` is ambiguous at every repetition, which is
/// exponential backtracking on a near-miss input. Nothing here is
/// attacker-controlled, but a guard that can hang the job it runs in is a
/// guard that gets disabled.
/** @param {string} src @returns {string[]} */
export function goExportProfileColumns(src) {
	// Anchored on the function, because supabase.go issues many such calls and
	// an unanchored read silently certifies whichever one happens to be first.
	const start = src.search(/func \([^)]*\) FetchExportProfile\(/);
	if (start === -1) return [];
	const body = src.slice(start, start + 4000);
	return splitColumns(sliceLiteral(body, 'q.Set("select",', ')'));
}

/// The same list on the Edge Function rail.
/** @param {string} src @returns {string[]} */
export function tsExportProfileColumns(src) {
	return splitColumns(sliceLiteral(src, 'export const PROFILE_SELECT', ';'));
}

/// The text between a literal opener and the first `end` after it. Both
/// searches are plain `indexOf`, so the cost is linear in the source.
/** @param {string} src @param {string} opener @param {string} end @returns {string} */
function sliceLiteral(src, opener, end) {
	const at = src.indexOf(opener);
	if (at === -1) return '';
	const from = at + opener.length;
	const to = src.indexOf(end, from);
	return to === -1 ? '' : src.slice(from, to);
}

/** @param {string} literal @returns {string[]} */
function splitColumns(literal) {
	const joined = [...literal.matchAll(/["']([^"']*)["']/g)].map((m) => m[1]).join('');
	return joined
		.split(',')
		.map((c) => c.trim())
		.filter((c) => c.length > 0);
}

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
	const bounds = checkColumnBounds(ctx);
	errors.push(...bounds.errors);
	ok.push(...bounds.ok);
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
	console.log(
		`\n${REGISTRY.length} registered shared constants agree across every home, and ` +
			`every registered client bound sits inside its column's own CHECK ` +
			`(${ok.length} checks).`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

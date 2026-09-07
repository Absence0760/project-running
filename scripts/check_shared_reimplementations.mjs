#!/usr/bin/env node
// Guardrail: no web module privately reimplements a helper the shared `lib/`
// tree already exports.
//
// Why it exists (decisions § 1397). The tree has hit this four times and
// every guard it had stayed green through all four. `check_parity_pair_registry.mjs`
// compares the two REGISTRIES and not the two behaviours (§ 852), so a private
// copy is simply not a pair anyone declared; `check_shared_constants.mjs` only
// compares rails it has been told about. The four:
//
//   § 852   a hand-written Dart fold table beside the generated one
//   § 1340  `dm_recipients.ts` held a fourth private `fold`, missing the one
//           step — the final-sigma collapse — the canonical exists to add
//   § 1334-integration  the exercise-catalogue picker held a byte-identical
//           private copy of `compareFoldedNames`
//   § 1398  `planSlug` derived a slug with `toLowerCase()` where `clubSlug`
//           folds, which is § 1251's `İzmir` -> `i-zmir` reversal again
//
// ANCHORING. A guard keyed on a NAME fails the moment someone renames; one
// keyed on the existence of a DECLARATION passes a copy that declares nothing;
// one keyed on a spelling (`fail on the literal "normalize('NFD')"`) fails
// correct code and passes a copy written differently. So both anchors here are
// keyed on what cannot be removed without changing behaviour:
//
//   A. the function's normalised BODY — every token it runs, with only the
//      things that are free to change stripped: comments, whitespace, the
//      function's own name, and the SPELLING of its parameters and locals
//      (alpha-renamed to $0..$n by declaration order). What survives is the
//      operations it calls, the properties it reads, the literals it passes
//      and its control-flow shape. Two functions with the same fingerprint run
//      the same code.
//
//   B. the DISTINCTIVE OPERATIONS it reaches for — method calls carrying a
//      string or regex literal argument, e.g. `normalize('NFD')` or
//      `replace(/\p{Diacritic}/gu,'')`. A rewritten copy, or one that omits a
//      step, still has to reach for the same primitives; § 1340's copy shared
//      three with the canonical.
//
// Both anchors survive renaming the function, its parameters, its locals, and
// any reformatting or comment edit. Neither survives a copy that reaches for
// genuinely different primitives — which is the honest floor: a
// reimplementation that shares no operation and no body shape with the
// original is not detectable by reading either one.
//
// FALSE POSITIVES. Anchor A's are near-zero at the size floor: free
// identifiers stay verbatim, so two functions collide only when they call the
// same things in the same order. Anchor B's are real and measured — two
// functions can share a vocabulary without one being a copy of the other
// (`platformIcon` and `detectPlatform` both speak of `'android'` / `'mac'` /
// `'windows'` / `'linux'` because that is the vocabulary, not because either
// wrote the other). They go in REGISTERED, which states what each actually is.
//
// FALSE NEGATIVES, stated rather than discovered later:
//   - Only a group with an EXPORTED `apps/web/src/lib/**` member is reported.
//     Duplication with nothing shared to import is a different finding, and
//     the house rule ("three similar lines is better than a premature helper")
//     tolerates it. The nine copies of `escapeJsonLd` are invisible here.
//   - Anchor A finds identical copies, not the whole equivalence class: the
//     tree holds eleven haversines and only the two structurally identical
//     ones are one group.
//   - Anonymous callbacks are not extracted; a copy pasted into an inline
//     arrow is missed. Named function declarations and named `const` arrows
//     are, which is every shape a copied helper has taken here.
//   - Cross-LANGUAGE reimplementation (§ 852's Dart table against the web
//     fold) is out of reach of a reader of one language, and stays with
//     `check_parity_pair_registry.mjs` and the shared-constant rails.
//
// Run: `node scripts/check_shared_reimplementations.mjs`
// CI:  the `parity-types` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_shared_reimplementations.test.mjs`

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** The tree read. Every known instance of the class has lived under it. */
export const SCAN_ROOT = 'apps/web/src';

/**
 * A body shorter than this is not evidence of anything: `return a.id;` is
 * identical in a hundred places and copying it costs nobody. Measured over the
 * tree at the time of writing — 3,068 extracted functions — the floor at 20
 * normalised tokens leaves 36 cross-file identical groups, 8 of which hold a
 * shared `lib/` export. Below it the count runs away into accessors.
 */
export const MIN_BODY_TOKENS = 20;

/**
 * How many shared distinctive operations make a coincidence a copy, and how
 * widely an operation may occur before it stops being distinctive.
 *
 * Both were measured rather than picked. At `MIN_SHARED_OPS = 1` the tree
 * yields 37 pairs and substantially all of them are noise — two functions
 * querying `from('coach_messages')`, two logging `error('[coach] ...')`, nine
 * calling `createElement('div')`. At 2, with an operation held by at most 3
 * functions tree-wide, it yields 4 pairs and 3 of them are real.
 */
export const MIN_SHARED_OPS = 2;
export const MAX_OP_HOLDERS = 3;

/**
 * @typedef {object} Member
 * @property {string} file repo-relative
 * @property {string} name
 * @property {boolean} exported
 */
/**
 * @typedef {object} Finding
 * @property {'clone' | 'ops'} kind
 * @property {string} key stable identity: sorted `file:name` members
 * @property {Member[]} members
 * @property {string} detail what the two share
 */
/**
 * @typedef {object} Registration
 * @property {'clone' | 'ops'} kind
 * @property {string} key must equal a finding's key
 * @property {string} reason what the thing actually IS
 */

/**
 * The escape register. Every entry states what the pair actually is, and the
 * guard fails when one goes STALE — a registration matching no finding means
 * the duplication was resolved (delete the entry) or the guard stopped seeing
 * it (which is the thing worth knowing).
 *
 * An entry is not a verdict that the duplication is fine. Three of these are
 * "real, owed a fix, filed" — registered so the guard can be a ratchet against
 * the NEXT copy instead of waiting for a round with the budget to consolidate
 * eleven haversines.
 *
 * @type {Registration[]}
 */
export const REGISTERED = [
	{
		kind: 'ops',
		key: 'apps/web/src/lib/social/club_slug.ts:clubSlug|apps/web/src/routes/plans/[id]/+page.svelte:planSlug',
		reason:
			'Not a copy, once the copied part was removed. `planSlug` derived its slug with `toLowerCase()` where `clubSlug` folds, which is § 1251\'s `İstanbul` -> `i-stanbul` reversal; it now folds through the same generated table (§ 1398). What is left shared is the kebab transform, because that is what a slug IS. They are not one contract: the club slug is a PERSISTED public identity with a length cap, a fallback and a Dart twin under a registered parity pair, and this is a download filename with two call sites — so extracting a common `slugify` would restructure one half of a pair whose other half cannot be run in this lane. Filed rather than done.',
	},
	{
		kind: 'clone',
		key: 'apps/web/src/lib/format/time.ts:formatDuration|apps/web/src/lib/runs/race_day.ts:fmtSplitTime',
		reason:
			'Real duplicate, filed. `fmtSplitTime` is `formatDuration` rebuilt in the race-day module. Not fixed here because `race_day.ts` is a mid-round tree for another lane and the change is a behavioural one (`formatDuration` is the localised formatter, `fmtSplitTime` is not).',
	},
	{
		kind: 'clone',
		key: 'apps/web/src/lib/integrations/import.ts:haversine|apps/web/src/lib/routes/geocoding_math.ts:haversineM',
		reason:
			'Real duplicate, filed. Two of the ELEVEN great-circle distances the web tree carries. Consolidating them is a route/geo refactor with a parity-pair obligation on `run_stats.haversineMetres` (whose clamp is a recorded near-miss, § 305) and does not fit one lane.',
	},
	{
		kind: 'clone',
		key: 'apps/web/src/lib/nutrition/diary_day.ts:isoDateOf|apps/web/src/lib/nutrition/meal_detail.ts:localDateKey',
		reason:
			'Real duplicate, filed. Both render a local calendar day as `yyyy-mm-dd`. `diary_day` is half of a registered parity pair, so moving the function is a lockstep edit on the Dart side too — out of this lane, which may not run Flutter.',
	},
	{
		kind: 'clone',
		key:
			'apps/web/src/lib/routes/gpx.ts:escapeXml|apps/web/src/lib/routes/route_gpx.ts:escapeXml|apps/web/src/lib/share/og_recap_image.ts:xmlEscape|apps/web/src/lib/share/og_route_image.ts:xmlEscape|apps/web/src/lib/share/og_run_image.ts:xmlEscape|apps/web/src/lib/share/recap_share_image.ts:xmlEscape|apps/web/src/lib/share/sitemap.ts:xmlEscape',
		reason:
			'Real duplicate, filed. Seven copies of XML entity escaping under two names. `route_gpx` is half of a registered parity pair, so the consolidated home has to be chosen with the Dart side in view.',
	},
	{
		kind: 'clone',
		key:
			'apps/web/src/lib/share/share_event_meta.ts:renderShareEventHeadTags|apps/web/src/lib/share/share_race_meta.ts:renderShareRaceHeadTags|apps/web/src/lib/share/share_route_meta.ts:renderShareRouteHeadTags',
		reason:
			'Deliberate. Each renders the head tags for one `/share/{entity}` surface and they are identical only because the four surfaces currently carry the same tag set. They are per-entity by design (§ 205 gives each its own JSON-LD shape), so collapsing them would have to be undone the first time one surface needs a tag the others do not.',
	},
	{
		kind: 'clone',
		key:
			'apps/web/src/lib/share/share_session_meta.ts:renderShareSessionHeadTags|apps/web/src/lib/share/share_workout_meta.ts:renderShareWorkoutHeadTags',
		reason:
			'Deliberate, and the same reason as the three-way sibling group above: one head-tag renderer per /share/{entity} surface, identical today only because the two carry the same tag set, and per-entity by design so a collapse would have to be undone the first time one needs a tag the other does not.',
	},
	{
		kind: 'clone',
		key: 'apps/web/src/lib/social/recurrence.ts:addDays|apps/web/src/lib/training/training.ts:addDays',
		reason:
			'Deliberate. Both are `Date` day arithmetic through the y/m/d constructor, and BOTH modules are halves of registered TS-Dart parity pairs whose Dart sides each carry their own. Merging them on the web side alone would break the one-file-per-pair correspondence the syncer agent reads.',
	},
	{
		kind: 'clone',
		key: 'apps/web/src/lib/training/training.ts:formatISO|apps/web/src/lib/training/training_load.ts:localDateKey',
		reason:
			'Deliberate, and the same parity-pair reason as `addDays` above: both modules are web halves of registered TS-Dart pairs whose Dart sides each carry their own copy, so merging them on the web side alone would break the one-file-per-pair correspondence the syncer agent reads.',
	},
	{
		kind: 'ops',
		key:
			'apps/web/src/lib/core/data.ts:fetchGymWorkoutWithSets|apps/web/src/lib/share/share_workout_lookup.ts:lookupSharedWorkout',
		reason:
			'Not a reimplementation. Two different reads of the same two tables — one as the owner through RLS, one as the anonymous share path through a lookup that must not widen. Sharing `eq(\'workout_id\')` and `order(\'set_index\')` is what querying the same table looks like. `core/data.ts` is another lane\'s tree this round in any case.',
	},
	{
		kind: 'ops',
		key:
			'apps/web/src/lib/integrations/garmin-fit.ts:parseFitBuffer|apps/web/src/lib/integrations/strava-zip-disposition.ts:classifyStravaRow',
		reason:
			'Not a reimplementation, but adjacent to a real rule. Both test an activity label for `run` / `walk` / `hike` because both classify a third party\'s activity string into ours. They are different parsers of different formats; what they share is the vocabulary. The enumeration itself is the shape `gear_backfill` records as a hazard (§ 598) and belongs to the integrations tree.',
	},
	{
		kind: 'ops',
		key:
			'apps/web/src/lib/settings/settings.ts:detectPlatform|apps/web/src/routes/settings/devices/+page.svelte:platformIcon',
		reason:
			'False positive, and the one worth keeping written down. `detectPlatform` maps a USER AGENT to a platform token; `platformIcon` maps that token to an icon ligature. They share `includes(\'android\')` / `(\'mac\')` / `(\'windows\')` / `(\'linux\')` because they speak about the same vocabulary from opposite ends, not because either is a copy of the other.',
	},
];

const ID_START = /[\p{L}_$]/u;
const ID_PART = /[\p{L}\p{N}_$]/u;

/**
 * Keywords after which a `/` opens a regex rather than dividing. Without this
 * the lexer reads `/\p{Diacritic}/gu` in `return x.replace(/.../)` as two
 * divisions and the fingerprint of every folding function is wrong.
 */
const REGEX_OK_KEYWORDS = new Set([
	'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
	'case', 'do', 'else', 'yield', 'await', 'throw',
]);

const PUNCT3 = ['...', '===', '!==', '**=', '<<=', '>>=', '&&=', '||=', '??=', '>>>'];
const PUNCT2 = [
	'=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--',
	'+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '**', '<<', '>>',
];

/** @typedef {{ kind: 'ident' | 'string' | 'template' | 'regex' | 'number' | 'punct', text: string }} Token */

/**
 * TS/JS source to a token stream with comments and whitespace dropped.
 *
 * Hand-rolled rather than `typescript`'s own scanner because `typescript` is a
 * dependency of `apps/web`, not of the root, and every guard in `scripts/`
 * advertises "stdlib only, no install needed" in its CI block. Reaching for a
 * hoisted package would make this the one guard whose result depends on npm's
 * hoisting behaviour.
 *
 * @param {string} src
 * @returns {Token[]}
 */
export function tokenize(src) {
	/** @type {Token[]} */
	const out = [];
	let i = 0;
	const n = src.length;
	while (i < n) {
		const c = src[i];
		if (c === ' ' || c === '\t' || c === '\r' || c === '\n') { i++; continue; }
		if (c === '/' && src[i + 1] === '/') { while (i < n && src[i] !== '\n') i++; continue; }
		if (c === '/' && src[i + 1] === '*') {
			i += 2;
			while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++;
			i += 2;
			continue;
		}
		if (c === '"' || c === "'") {
			let j = i + 1;
			while (j < n && src[j] !== c) { if (src[j] === '\\') j++; j++; }
			out.push({ kind: 'string', text: src.slice(i, j + 1) });
			i = j + 1;
			continue;
		}
		if (c === '`') {
			let j = i + 1;
			let depth = 0;
			while (j < n) {
				if (src[j] === '\\') { j += 2; continue; }
				if (depth === 0 && src[j] === '`') break;
				if (src[j] === '$' && src[j + 1] === '{') { depth++; j += 2; continue; }
				if (depth > 0 && src[j] === '}') { depth--; j++; continue; }
				j++;
			}
			out.push({ kind: 'template', text: src.slice(i, j + 1) });
			i = j + 1;
			continue;
		}
		if (c === '/') {
			const p = out.length ? out[out.length - 1] : null;
			const regexOk =
				!p ||
				(p.kind === 'punct' && ![')', ']', '}', '++', '--'].includes(p.text)) ||
				(p.kind === 'ident' && REGEX_OK_KEYWORDS.has(p.text));
			if (regexOk) {
				let j = i + 1;
				let inClass = false;
				let closed = false;
				while (j < n) {
					const d = src[j];
					if (d === '\\') { j += 2; continue; }
					if (d === '\n') break;
					if (d === '[') inClass = true;
					else if (d === ']') inClass = false;
					else if (d === '/' && !inClass) { closed = true; break; }
					j++;
				}
				if (closed) {
					let k = j + 1;
					while (k < n && ID_PART.test(src[k])) k++;
					out.push({ kind: 'regex', text: src.slice(i, k) });
					i = k;
					continue;
				}
			}
		}
		if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(src[i + 1] ?? ''))) {
			let j = i;
			while (j < n && /[0-9a-fA-FxXoObBeE._n]/.test(src[j])) j++;
			out.push({ kind: 'number', text: src.slice(i, j) });
			i = j;
			continue;
		}
		if (ID_START.test(c)) {
			let j = i;
			while (j < n && ID_PART.test(src[j])) j++;
			out.push({ kind: 'ident', text: src.slice(i, j) });
			i = j;
			continue;
		}
		const three = src.slice(i, i + 3);
		const two = src.slice(i, i + 2);
		if (PUNCT3.includes(three)) { out.push({ kind: 'punct', text: three }); i += 3; continue; }
		if (PUNCT2.includes(two)) { out.push({ kind: 'punct', text: two }); i += 2; continue; }
		out.push({ kind: 'punct', text: c });
		i++;
	}
	return out;
}

/**
 * Index of the token closing the group `toks[start]` opens, or -1.
 * @param {Token[]} toks
 * @param {number} start
 * @param {string} open
 * @param {string} close
 */
function matchGroup(toks, start, open, close) {
	if (!toks[start] || toks[start].text !== open) return -1;
	let d = 0;
	for (let i = start; i < toks.length; i++) {
		if (toks[i].kind !== 'punct') continue;
		if (toks[i].text === open) d++;
		else if (toks[i].text === close) { d--; if (d === 0) return i; }
	}
	return -1;
}

/** @typedef {{ name: string, exported: boolean, params: Token[], body: Token[] }} ExtractedFunction */

/**
 * Every named function declaration and named `const`/`let`/`var` arrow in
 * `src`, with its parameter and body token ranges.
 *
 * Anonymous callbacks are deliberately not extracted — see the false-negative
 * list at the top.
 *
 * @param {string} src
 * @returns {ExtractedFunction[]}
 */
export function extractFunctions(src) {
	const toks = tokenize(src);
	/** @type {ExtractedFunction[]} */
	const fns = [];
	for (let i = 0; i < toks.length; i++) {
		const t = toks[i];
		if (t.kind !== 'ident') continue;

		if (t.text === 'function') {
			let j = i + 1;
			if (toks[j] && toks[j].text === '*') j++;
			if (!toks[j] || toks[j].kind !== 'ident') continue;
			const name = toks[j].text;
			j++;
			if (toks[j] && toks[j].text === '<') {
				const e = matchGroup(toks, j, '<', '>');
				if (e < 0) continue;
				j = e + 1;
			}
			const pClose = matchGroup(toks, j, '(', ')');
			if (pClose < 0) continue;
			let k = pClose + 1;
			while (k < toks.length && toks[k].text !== '{' && toks[k].text !== ';') k++;
			if (!toks[k] || toks[k].text !== '{') continue;
			const bClose = matchGroup(toks, k, '{', '}');
			if (bClose < 0) continue;
			const exported =
				(i >= 1 && toks[i - 1].text === 'export') ||
				(i >= 2 && toks[i - 1].text === 'async' && toks[i - 2].text === 'export');
			fns.push({ name, exported, params: toks.slice(j + 1, pClose), body: toks.slice(k + 1, bClose) });
			continue;
		}

		if (t.text === 'const' || t.text === 'let' || t.text === 'var') {
			let j = i + 1;
			if (!toks[j] || toks[j].kind !== 'ident') continue;
			const name = toks[j].text;
			j++;
			if (toks[j] && toks[j].text === ':') {
				while (j < toks.length && toks[j].text !== '=' && toks[j].text !== ';') j++;
			}
			if (!toks[j] || toks[j].text !== '=') continue;
			j++;
			if (toks[j] && toks[j].text === 'async') j++;
			if (toks[j] && toks[j].text === '<') {
				const e = matchGroup(toks, j, '<', '>');
				if (e < 0) continue;
				j = e + 1;
			}
			if (!toks[j] || toks[j].text !== '(') continue;
			const pOpen = j;
			const pClose = matchGroup(toks, pOpen, '(', ')');
			if (pClose < 0) continue;
			let k = pClose + 1;
			if (toks[k] && toks[k].text === ':') {
				while (k < toks.length && toks[k].text !== '=>' && toks[k].text !== ';') k++;
			}
			if (!toks[k] || toks[k].text !== '=>') continue;
			k++;
			const exported = i >= 1 && toks[i - 1].text === 'export';
			const params = toks.slice(pOpen + 1, pClose);
			if (toks[k] && toks[k].text === '{') {
				const bClose = matchGroup(toks, k, '{', '}');
				if (bClose < 0) continue;
				fns.push({ name, exported, params, body: toks.slice(k + 1, bClose) });
			} else {
				let d = 0;
				let e = k;
				while (e < toks.length) {
					const x = toks[e];
					if (x.kind === 'punct') {
						if (x.text === '(' || x.text === '[' || x.text === '{') d++;
						else if (x.text === ')' || x.text === ']' || x.text === '}') { if (d === 0) break; d--; }
						else if (x.text === ';' && d === 0) break;
					}
					e++;
				}
				fns.push({ name, exported, params, body: toks.slice(k, e) });
			}
			continue;
		}
	}
	return fns;
}

const DECLARERS = new Set(['const', 'let', 'var', 'function', 'class']);

/**
 * The names a parameter list or a destructuring pattern BINDS.
 *
 * At the top level a name is a binding when it opens the list or follows a
 * comma. Inside a `{}` or `[]` pattern every name binds EXCEPT one immediately
 * followed by `:`, which is the property being read — `{ c: renamed }` binds
 * `renamed` and not `c`. Getting that backwards leaves the real binding
 * spelled out in the fingerprint, so renaming it would change the answer,
 * which is the one thing the fingerprint must not depend on.
 *
 * @param {Token[]} toks
 * @returns {Set<string>}
 */
export function patternNames(toks) {
	/** @type {Set<string>} */
	const names = new Set();
	const MODIFIERS = ['readonly', 'public', 'private', 'protected'];
	let depth = 0;
	let expectName = true;
	// Everything after a top-level `:` or `=` belongs to a TYPE or a default
	// value, not to the binding — and it runs to the next top-level comma, so a
	// nested group inside it is part of it. `a: { lng: number; lat: number }` is
	// an inline object type and binds only `a`; reading its braces as a
	// destructuring pattern binds `number`, and any `number` in the body is then
	// alpha-renamed — which made two byte-identical haversines disagree.
	let inAnnotation = false;
	for (let i = 0; i < toks.length; i++) {
		const t = toks[i];
		if (t.kind === 'punct') {
			if (t.text === '(' || t.text === '[' || t.text === '{') {
				depth++;
				if (!inAnnotation) expectName = true;
			} else if (t.text === ')' || t.text === ']' || t.text === '}') depth--;
			else if (depth === 0 && t.text === ',') { inAnnotation = false; expectName = true; }
			else if (depth === 0 && (t.text === ':' || t.text === '=')) inAnnotation = true;
			continue;
		}
		if (t.kind !== 'ident' || inAnnotation) continue;
		if (depth > 0) {
			const next = toks[i + 1];
			const isPropertyKey = next && next.kind === 'punct' && next.text === ':';
			if (!isPropertyKey && !MODIFIERS.includes(t.text)) names.add(t.text);
			continue;
		}
		if (expectName && !MODIFIERS.includes(t.text)) names.add(t.text);
		expectName = false;
	}
	return names;
}


/**
 * The names the function BINDS: its parameters (including destructured ones)
 * and everything a `const` / `let` / `var` / `function` / `catch` inside it
 * declares. These are the names free to be renamed without changing what the
 * function does, so they are exactly the ones the fingerprint erases.
 *
 * @param {ExtractedFunction} fn
 * @returns {Set<string>}
 */
export function declaredNames(fn) {
	/** @type {Set<string>} */
	const names = new Set();
	for (const name of patternNames(fn.params)) names.add(name);
	for (let i = 0; i < fn.body.length; i++) {
		const t = fn.body[i];
		if (t.kind !== 'ident') continue;
		if (DECLARERS.has(t.text)) {
			let j = i + 1;
			const opener = fn.body[j];
			if (opener && opener.kind === 'punct' && (opener.text === '{' || opener.text === '[')) {
				const close = opener.text === '{' ? '}' : ']';
				let d = 0;
				let end = j;
				for (let k = j; k < fn.body.length; k++) {
					const x = fn.body[k];
					if (x.kind === 'punct' && x.text === opener.text) d++;
					else if (x.kind === 'punct' && x.text === close) { d--; if (d === 0) { end = k; break; } }
				}
				for (const name of patternNames(fn.body.slice(j, end + 1))) names.add(name);
				j = end;
				continue;
			}
			if (opener && opener.kind === 'ident') names.add(opener.text);
			continue;
		}
		if (
			t.text === 'catch' &&
			fn.body[i + 1] && fn.body[i + 1].text === '(' &&
			fn.body[i + 2] && fn.body[i + 2].kind === 'ident'
		) {
			names.add(fn.body[i + 2].text);
		}
	}
	return names;
}

/**
 * The normalised body: every token the function runs, with bound names
 * alpha-renamed to `$0..$n` by first occurrence. A name after `.` or `?.` is a
 * PROPERTY and stays verbatim even when it collides with a local — `.length`
 * is behaviour, not a spelling.
 *
 * @param {ExtractedFunction} fn
 * @returns {{ fingerprint: string, size: number }}
 */
export function bodyFingerprint(fn) {
	const bound = declaredNames(fn);
	/** @type {Map<string, string>} */
	const alias = new Map();
	/** @type {string[]} */
	const out = [];
	for (let i = 0; i < fn.body.length; i++) {
		const t = fn.body[i];
		if (t.kind === 'ident') {
			const prev = fn.body[i - 1];
			const isProperty = prev && prev.kind === 'punct' && (prev.text === '.' || prev.text === '?.');
			if (!isProperty && bound.has(t.text)) {
				let a = alias.get(t.text);
				if (a === undefined) {
					a = '$' + alias.size;
					alias.set(t.text, a);
				}
				out.push(a);
				continue;
			}
		}
		out.push(t.text);
	}
	// Joined with a separator rather than concatenated: without one the token
	// pair `a` `b` and the single token `ab` produce the same string, and two
	// functions that do not run the same code would share a fingerprint. U+0000
	// cannot occur inside a token — a source string containing one spells it
	// `\\0`, which is two characters.
	return { fingerprint: out.join('\u0000'), size: out.length };
}

/**
 * The distinctive operations the function performs: each method call carrying
 * at least one string or regex literal argument, rendered `name(lit,lit)`.
 *
 * The literal is what makes it distinctive and what a copy cannot drop:
 * `normalize('NFD')` is not `normalize('NFC')`, and `replace(/\p{Diacritic}/gu, '')`
 * has no shorter spelling that behaves the same. A call with no literal
 * argument (`toLowerCase()`, `map(f)`) says nothing about which helper this is.
 *
 * @param {ExtractedFunction} fn
 * @returns {string[]}
 */
export function distinctiveOperations(fn) {
	/** @type {string[]} */
	const ops = [];
	const b = fn.body;
	for (let i = 0; i < b.length; i++) {
		const t = b[i];
		if (t.kind !== 'ident') continue;
		const prev = b[i - 1];
		if (!prev || prev.kind !== 'punct' || (prev.text !== '.' && prev.text !== '?.')) continue;
		const open = b[i + 1];
		if (!open || open.kind !== 'punct' || open.text !== '(') continue;
		let d = 0;
		/** @type {string[]} */
		const literals = [];
		for (let j = i + 1; j < b.length; j++) {
			const x = b[j];
			if (x.kind === 'punct' && (x.text === '(' || x.text === '[' || x.text === '{')) d++;
			else if (x.kind === 'punct' && (x.text === ')' || x.text === ']' || x.text === '}')) {
				d--;
				if (d === 0) break;
			} else if (d === 1 && (x.kind === 'string' || x.kind === 'regex')) literals.push(x.text);
		}
		if (literals.length === 0) continue;
		ops.push(t.text + '(' + literals.join(',') + ')');
	}
	return ops;
}

/**
 * The `<script>` bodies of a Svelte component, joined. Everything outside them
 * is markup, which holds no function declarations.
 * @param {string} src
 */
export function svelteScript(src) {
	return [...src.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]).join('\n;\n');
}

/** @param {string} file */
const isSharedLib = (file) => file.startsWith(SCAN_ROOT + '/lib/');

/**
 * @param {{ file: string, source: string }[]} files
 * @returns {Finding[]}
 */
export function findReimplementations(files) {
	/** @type {(Member & { fingerprint: string, size: number, ops: Set<string> })[]} */
	const all = [];
	for (const { file, source } of files) {
		const src = file.endsWith('.svelte') ? svelteScript(source) : source;
		for (const fn of extractFunctions(src)) {
			const { fingerprint, size } = bodyFingerprint(fn);
			all.push({
				file,
				name: fn.name,
				exported: fn.exported,
				fingerprint,
				size,
				ops: new Set(distinctiveOperations(fn)),
			});
		}
	}

	/** @type {Finding[]} */
	const findings = [];

	/** @type {Map<string, typeof all>} */
	const byFingerprint = new Map();
	for (const fn of all) {
		if (fn.size < MIN_BODY_TOKENS) continue;
		const bucket = byFingerprint.get(fn.fingerprint);
		if (bucket) bucket.push(fn);
		else byFingerprint.set(fn.fingerprint, [fn]);
	}
	for (const members of byFingerprint.values()) {
		if (new Set(members.map((m) => m.file)).size < 2) continue;
		if (!members.some((m) => m.exported && isSharedLib(m.file))) continue;
		findings.push({
			kind: 'clone',
			key: memberKey(members),
			members: members.map(toMember),
			detail: 'identical normalised body, ' + members[0].size + ' tokens',
		});
	}

	/** @type {Map<string, number>} */
	const opHolders = new Map();
	for (const fn of all) for (const op of fn.ops) opHolders.set(op, (opHolders.get(op) ?? 0) + 1);
	const owners = all.filter((a) => a.exported && isSharedLib(a.file) && a.ops.size > 0);
	/** @type {Set<string>} */
	const seen = new Set();
	for (const other of all) {
		if (other.ops.size === 0) continue;
		for (const owner of owners) {
			if (owner === other || owner.file === other.file) continue;
			const shared = [...other.ops].filter(
				(op) => owner.ops.has(op) && (opHolders.get(op) ?? 0) <= MAX_OP_HOLDERS,
			);
			if (shared.length < MIN_SHARED_OPS) continue;
			const key = memberKey([owner, other]);
			if (seen.has(key)) continue;
			seen.add(key);
			findings.push({
				kind: 'ops',
				key,
				members: [owner, other].map(toMember),
				detail: shared.length + ' shared distinctive operations: ' + shared.join(' '),
			});
		}
	}

	findings.sort((a, b) => (a.kind === b.kind ? (a.key < b.key ? -1 : 1) : a.kind < b.kind ? -1 : 1));
	return findings;
}

/** @param {Member} m */
const toMember = (m) => ({ file: m.file, name: m.name, exported: m.exported });
/** @param {Member[]} members */
const memberKey = (members) =>
	[...new Set(members.map((m) => m.file + ':' + m.name))].sort().join('|');

/**
 * @param {Finding[]} findings
 * @param {Registration[]} registered
 * @returns {{ unregistered: Finding[], stale: Registration[] }}
 */
export function reconcile(findings, registered) {
	const found = new Map(findings.map((f) => [f.kind + ' ' + f.key, f]));
	const known = new Set(registered.map((r) => r.kind + ' ' + r.key));
	return {
		unregistered: findings.filter((f) => !known.has(f.kind + ' ' + f.key)),
		stale: registered.filter((r) => !found.has(r.kind + ' ' + r.key)),
	};
}

/**
 * @param {string} dir absolute
 * @param {string[]} acc
 */
function walk(dir, acc) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
			walk(p, acc);
		} else acc.push(p);
	}
	return acc;
}

/** Source files the guard reads: web TS and Svelte, minus tests and ambients. */
export function readScannedFiles() {
	const abs = walk(path.join(rootDir, SCAN_ROOT), []);
	return abs
		.filter((f) => /\.(ts|svelte)$/.test(f) && !/\.test\.ts$/.test(f) && !/\.d\.ts$/.test(f))
		.map((f) => ({ file: path.relative(rootDir, f), source: fs.readFileSync(f, 'utf8') }))
		.sort((a, b) => (a.file < b.file ? -1 : 1));
}

function main() {
	const files = readScannedFiles();
	const findings = findReimplementations(files);
	const { unregistered, stale } = reconcile(findings, REGISTERED);

	for (const f of unregistered) {
		console.error(
			'A shared helper is reimplemented privately (' + f.kind + '): ' + f.detail + '\n' +
			f.members.map((m) => '    ' + m.file + ':' + m.name + (m.exported ? ' [exported]' : '')).join('\n'),
		);
	}
	for (const r of stale) {
		console.error(
			'STALE registration (' + r.kind + '), no finding matches it: ' + r.key + '\n' +
			'    Registered as: ' + r.reason,
		);
	}

	if (unregistered.length > 0 || stale.length > 0) {
		console.error(
			'\n' + unregistered.length + ' unregistered, ' + stale.length + ' stale, over ' +
			files.length + ' files.\n' +
			'Import the shared export instead of rewriting it. If the duplication is\n' +
			'deliberate, add an entry to REGISTERED in scripts/check_shared_reimplementations.mjs\n' +
			'saying what the thing actually IS; if a registration is stale, delete it.',
		);
		process.exit(1);
	}
	console.log(
		'No unregistered private reimplementation over ' + files.length + ' files (' +
		REGISTERED.length + ' registered).',
	);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();

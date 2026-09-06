#!/usr/bin/env node
// Guardrail: a source file that declares a cross-platform twin is a REGISTERED
// parity pair or a recorded judgement that it is not one, and the file it names
// exists. The judgement is re-derived rather than remembered.
//
// `check_parity_pair_registry.mjs` cross-checks the two registries — CLAUDE.md's
// lockstep bullet and the shared-library-syncer agent's table — against each
// other. Both can agree perfectly about a pair that is in neither of them. That
// is not a hypothetical: `turn_cues` diverged in THREE implementations at once
// while registered nowhere (decisions § 641), and the web/mobile accent fold sat
// diverged for eighteen days while both doc comments claimed lockstep
// (decisions § 760). CLAUDE.md states the failure mode outright — "a pair added
// here without a row there is a pair whose divergence is never detected" — and
// the guard it points at can only see pairs one of the two registries already
// names.
//
// So the subject here is the SOURCE, not the registries. A header comment
// saying "Dart twin of `apps/web/src/lib/x/y.ts`" is a claim of lockstep made in
// the place a reader will actually see it, and it is the earliest artifact of a
// pair's existence — it is written when the second half is written, months
// before anyone thinks about a registry. Four properties:
//
//   1. The counterpart path a declaration names EXISTS. A file that moved
//      leaves the claim pointing at nothing, and the reader then cannot find
//      the half they were told to keep in step. This is the same defect
//      `check_parity_pair_registry`'s property 4 exists for, one layer out: that
//      one reads the registries, so a stale path in a SOURCE header is invisible
//      to it. Checked wherever a declaration sits, header or not — a dangling
//      path is a dangling path, and no resolution guessing is involved.
//
//   2. The declaration corresponds to a row of the syncer table carrying BOTH
//      files. The table is the operative registry — the syncer agent is the only
//      automated detector of parity divergence, and it works from that table
//      alone. A declared pair missing from it is a pair whose divergence is
//      never caught, while its own header reads as though it is covered. Both
//      halves must sit in the SAME row: two files each registered against some
//      other partner are two pairs, not one, and the flattened membership test
//      this guard used to run could not tell those apart.
//
//   3. A claim the registries cannot carry — a screen, a widget, render glue,
//      a header that names the pair it DRIVES rather than its own — resolves to
//      a NOT_PAIRS entry instead. A twin-shaped sentence gets exactly two
//      honest answers, "registered" and "judged not a pair with this reason",
//      and no third one where the guard simply cannot see it.
//
//   4. Every NOT_PAIRS entry is still true. § 1244 answered "is this a lockstep
//      pair?" with NO for five module pairs and recorded the answer by REWORDING
//      the headers, which left the judgement as prose nothing re-derives: if one
//      of them later grows real shared logic the honest answer flips and only a
//      reader notices. Each entry now carries the shared top-level symbol set
//      measured at the time it was written, and the guard re-measures it. A
//      converging surface, a file that moved, or a pair that has since been
//      registered each fail — the shape `UNREGISTERED_DEFINER_RELATIONS` uses in
//      `apps/backend/scripts/pgtap_definer_neutralisers.mjs` (decisions § 1273).
//
// Registration is checked by PATH rather than by name. The registry keys a pair
// on its WEB basename, so `gear_rotation_pick.dart` (the pair `rotation_pick`)
// is registered under a name its own filename does not carry; a name-keyed check
// would report it and teach the next reader to distrust the guard.
//
// KNOWN_GAPS is the register of declarations that violate property 1 or 2
// TODAY. Every entry is a real defect, not an exemption on the merits — closing
// one means editing CLAUDE.md, the syncer table, or the header, none of which
// this guard can do. An entry that has stopped being a violation FAILS, so the
// register can only shrink, and an entry naming a declaration that no longer
// exists fails too rather than sitting as cover. NOT_PAIRS is the opposite kind
// of list: those entries are judgements on the merits, and each carries the
// measurement that would flip it.
//
// Run: `node scripts/check_twin_claims.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list. Deliberately NOT gated on
//      `needs.changes.outputs.code`: half its input is markdown, and deleting a
//      syncer row is a docs-only diff that orphans every declaration it covered.
// Unit tests: `node --test scripts/check_twin_claims.test.mjs`

import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { SYNCER_DOC, parseSyncerRows, pathsInCell } from './check_parity_pair_registry.mjs';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/// Where a twin half can live. `packages/core_models` is here because three
/// pairs (`profile_query`, `strava_sync_result`, `import_completeness`) keep
/// their Dart half there rather than under `apps/mobile_android/lib`.
export const SOURCE_ROOTS = [
	'apps/web/src/lib',
	'apps/mobile_android/lib',
	'packages/core_models/lib',
];

/// The verbs that ASSERT a twin relationship, as opposed to mentioning one.
/// `in lockstep with` is deliberately absent — it is the phrase this repo uses
/// for every kind of coupling, including a client and an SQL CHECK.
const VERB = String.raw`(?:[Dd]art twin(?: of)?|TS twin(?: of)?|[Dd]art mirror of|TS.?.?Dart parity pair(?:\s*(?:with|:))?|[Mm]irrors|[Tt]win of|[Pp]orted from|[Dd]art port of|TS port of)`;

/// A DECLARATION of a twin naming a REPO-ROOTED path. The path has to follow
/// the verb within a short window, or a sentence about keeping a jsonb key
/// registry in lockstep reads as a parity pair.
///
/// Three forms found in the tree were unreadable until decisions § 1243: a
/// backticked path carrying a `:symbol` suffix (`run_stats.ts` names
/// `…/run_stats.dart:movingTimeOf`), a path written with NO backticks at all
/// (`workout_kind_color.ts`), and `Dart twin` / `ported from` / `Dart port of`
/// in place of the `… of` verbs.
export const DECLARATION = new RegExp(
	`${VERB}[^\`]{0,60}\`?((?:apps|packages)\\/[A-Za-z0-9_./-]+\\.(?:ts|dart))(?::[A-Za-z0-9_]+)?\`?`,
	'g',
);

/// The same declaration with the counterpart named RELATIVELY — `the mobile
/// twin of web's \`safety/off_route_flag.ts\``, `Dart twin of web
/// \`core/undo_queue.ts\``. Eleven of these sat unread, and two of them
/// (`off_route_flag`, `weigh_in_flag`) were live § 641-class pairs in neither
/// registry. Resolved by unique suffix match against the files under
/// `SOURCE_ROOTS`; an ambiguous or unresolvable suffix is reported rather than
/// guessed at.
///
/// Backticks are REQUIRED here where `DECLARATION` makes them optional, and
/// that asymmetry is measured rather than stylistic: dropping them from the
/// relative form makes the tail of an already-matched anchored path match as a
/// second, bogus counterpart (`apps/mobile_android/lib/recurrence.dart` yields
/// `e.dart`), which produced ten phantom declarations in the tree.
export const RELATIVE_DECLARATION = new RegExp(
	`${VERB}[^\`]{0,60}\`([A-Za-z0-9_][A-Za-z0-9_./-]*\\.(?:ts|dart))(?::[A-Za-z0-9_]+)?\``,
	'g',
);

/// Negation was READ here for one round and then removed, and the reason is
/// worth keeping: `gym_session_draft.dart` opens with "Not a twin of web's
/// `gym_session_draft.ts`" while `rate_limit_message.dart` puts its "is NOT
/// part of the enforced lockstep" two clauses AFTER the path, so a window that
/// looks backwards from the verb reads one honest header and misses the other.
/// The rule below subsumes both without looking at the wording at all: every
/// twin-shaped claim must resolve to a registered pair OR to a NOT_PAIRS entry,
/// so a header that denies a pair and a header that overstates one land in the
/// same place — the register, where the judgement is written down once and
/// re-measured.

/// A floor under the census. A reworded header convention, or a header-block
/// scanner that stops recognising `///`, would otherwise report zero
/// declarations as zero violations.
///
/// It is only a floor worth having if it sits near the real count. At 60
/// against a census of 106 it had 46 of slack, so the 25 % of the tree the
/// reader could not see (decisions § 1243) passed it unremarked — the guard's
/// own failure mode, undetected by the check written for it.
export const MIN_DECLARATIONS = 178;

/**
 * @typedef {{ file: string, counterpart: string, reason: string }} KnownGap
 * @typedef {{ web: string, mobile: string, reason: string, shared: readonly string[] }} NotPair
 * @typedef {{ file: string, counterpart: string, scope: 'header' | 'body', exists: boolean, registered: boolean, ambiguous: readonly string[] }} Declaration
 */

/// Declarations that violate property 1 or 2 today. Each is a defect with a
/// home somewhere this guard cannot reach.
/** @type {readonly KnownGap[]} */
export const KNOWN_GAPS = /** @type {KnownGap[]} */ ([]);

/// The judgements: two files a reader might take for a lockstep pair, and the
/// reason they are not one. `shared` is the set of top-level public names the
/// two files BOTH declare, measured when the entry was written — the thing that
/// moves first when a relationship the register calls unrelated starts becoming
/// one. It is compared as an exact set, in both directions: growth is the
/// convergence the entry exists to catch, and shrinkage is how a symbol reader
/// that has gone blind would present itself.
///
/// A name shared here is not evidence of a pair — the three deploy-gate pairs
/// share NOTHING (web `isWeighInEnabled` against Dart `weighInGate`) and are
/// registered pairs regardless. The set is a change detector for a decision a
/// person made, not a classifier.
/** @type {readonly NotPair[]} */
export const NOT_PAIRS = [
	{
		web: 'apps/web/src/lib/billing/revenuecat.ts',
		mobile: 'apps/mobile_android/lib/revenuecat.dart',
		reason:
			'Each wraps a different SDK against a different store — the web half mints ' +
			'a hosted-checkout URL, the mobile half drives the native purchase sheet. ' +
			'What they share is the not-configured sentinel contract, not an algorithm ' +
			'(decisions § 1244).',
		shared: ['isRevenueCatConfigured', 'managementUrl'],
	},
	{
		web: 'apps/web/src/lib/integrations/strava.ts',
		mobile: 'apps/mobile_android/lib/strava.dart',
		reason:
			'Same three function NAMES, three different implementations: the web state ' +
			'token is `crypto.randomUUID`, the mobile one 16 bytes of `Random.secure` ' +
			'hex; the web redirect URI is derived from the page origin, the mobile one ' +
			'is a parameter for a custom-scheme callback that has no web analogue. ' +
			'The shared surface is the widest of any entry here, so this is the one to ' +
			're-judge first if the native callback ever lands (decisions § 1244).',
		shared: ['isStravaConfigured', 'mintStravaOAuthState', 'stravaAuthUrl'],
	},
	{
		web: 'apps/web/src/lib/routes/route_describe_client.ts',
		mobile: 'apps/mobile_android/lib/route_describe_client.dart',
		reason:
			'Network glue — a session read plus an HTTP POST — on two different HTTP ' +
			'stacks. The pure half both call is the already-registered ' +
			'`route_description` pair (decisions § 1244).',
		shared: ['AiDescriptionResult', 'requestAiDescription'],
	},
	{
		web: 'apps/web/src/lib/training/fitness.ts',
		mobile: 'apps/mobile_android/lib/widgets/fitness_card.dart',
		reason:
			'The Dart file is a WIDGET that renders the numbers; the lockstep belongs ' +
			'to the registered `fitness` pair whose Dart half is `fitness.dart` ' +
			'(decisions § 1244).',
		shared: [],
	},
	{
		web: 'apps/web/src/lib/core/auth_gates.ts',
		mobile: 'apps/mobile_android/lib/screens/sign_up_screen.dart',
		reason:
			'The mobile consent gates live inline in a screen, which is a widget rather ' +
			'than a pure helper, so no syncer row can carry them. The password-pair half ' +
			'of the module IS twinned, as the registered `auth_gates` pair.',
		shared: [],
	},
	{
		web: 'apps/web/src/lib/gym/gym_session_draft.ts',
		mobile: 'apps/mobile_android/lib/gym_session_draft.dart',
		reason:
			'Mobile writes and replays the draft inside the session screen and keeps ' +
			'only the one predicate here; the web module is the whole codec. Its own ' +
			'header says so — "Not a twin of web\'s `gym_session_draft.ts`" — which is ' +
			'the negated declaration this entry answers.',
		shared: [],
	},
	{
		web: 'apps/web/src/lib/i18n/rate_limit_message.ts',
		mobile: 'apps/mobile_android/lib/rate_limit_message.dart',
		reason:
			'Render glue for the registered PARSE-ONLY `rate_limit_errors` pair. The ' +
			'sentences live in the seven web catalogues and the seven ARBs, whose key ' +
			'identifiers differ by convention, so CLAUDE.md states outright that this ' +
			'half is not part of the enforced lockstep (decisions § 744).',
		shared: ['rateLimitErrorMessage', 'rateLimitMessage', 'rateLimitWait'],
	},
	{
		web: 'apps/web/src/lib/core/password_change.ts',
		mobile: 'apps/mobile_android/lib/screens/settings_account_screen.dart',
		reason:
			'A mis-attribution rather than an overstatement: the sentence names the real ' +
			'pair (`password_change.dart`) and then the screen that pair DRIVES, and the ' +
			'reader takes the second path as a second claim. A screen is a widget and no ' +
			'syncer row can carry one.',
		shared: [],
	},
	{
		web: 'apps/web/src/lib/core/data.ts',
		mobile: 'apps/mobile_android/lib/screens/settings_safety_screen.dart',
		reason:
			'A screen naming the 12,000-line web data module it mirrors one call into. ' +
			'Neither end is a pure helper and the claim is about one operation, not a ' +
			'module.',
		shared: [],
	},
	{
		web: 'apps/web/src/lib/training/current_week.ts',
		mobile: 'apps/mobile_android/lib/widgets/this_week_strip.dart',
		reason:
			'The widget that RENDERS the strip, whose header names someone else\'s pair — ' +
			'"(`current_week.dart`, byte-identical twin of web\'s `current_week.ts`)" — so ' +
			'the reader attributes a registered pair to the file that mentions it. The ' +
			'lockstep belongs to `current_week`; this widget is presentation only, the ' +
			'same shape as `fitness_card.dart`.',
		shared: [],
	},
];

/// Lines that may sit between the top of a file and the block that documents
/// it. A module puts its imports above its doc comment far more often than
/// below it, and a scanner that stops at the first non-comment line therefore
/// read an EMPTY header for every such file — 37 of them carrying a
/// twin-shaped claim the guard never saw at all, `run_stats.ts` and
/// `elevation.dart` among them. decisions § 1243.
const PROLOGUE = /^(?:import\b|export\s.+\bfrom\b|library\b|part\b|@JS\b|['"]use strict['"])/;

/// A top-level CONSTANT is data, not the module's behaviour, and the three
/// deploy-gate modules (`adaptive_fitness_flag`, `off_route_flag`,
/// `weigh_in_flag`) each put one — the env-var key — between the imports and
/// the block that documents the gate. Stepping over it is what makes those
/// headers readable; measured, it adds exactly two declarations to the tree
/// and no noise. A FUNCTION still ends the header, so § 1243's pin that a
/// declaration written below the first statement is not a header holds.
const CONSTANT = /^(?:export\s+)?(?:const|final)\s/;

/**
 * The header comment of a source file: every comment line above the first line
 * of real code, folded onto one line so a declaration split over a wrap still
 * reads as one. Imports, blank lines and documented top-level constants are
 * stepped over rather than treated as code.
 *
 * @param {string} text
 * @returns {string}
 */
export function headerComment(text) {
	/** @type {string[]} */
	const head = [];
	for (const line of text.split('\n')) {
		const t = line.trim();
		if (t === '' || t.startsWith('//') || t.startsWith('/*') || t.startsWith('*')) {
			head.push(line);
			continue;
		}
		if (PROLOGUE.test(t) || CONSTANT.test(t)) continue;
		break;
	}
	return head.join('\n').replace(/\n\s*(?:\/\/\/?|\*)\s?/g, ' ');
}

/**
 * Every comment BLOCK in the file, each folded onto one line the way the header
 * is. Returned as separate strings rather than one: a code line has to break
 * the fold outright, or a verb in one block reaches a path in the next and the
 * guard invents a declaration neither of them makes. Used for property 1 only —
 * a path that does not exist is a dead reference wherever it is written, and
 * checking it needs no judgement about whether the sentence around it is a
 * claim of lockstep.
 *
 * @param {string} text
 * @returns {string[]}
 */
export function commentBlocks(text) {
	/** @type {string[]} */
	const blocks = [];
	/** @type {string[]} */
	let current = [];
	const flush = () => {
		const folded = current.join('\n').replace(/\n\s*(?:\/\/\/?|\*)\s?/g, ' ');
		if (folded.trim() !== '') blocks.push(folded);
		current = [];
	};
	for (const line of text.split('\n')) {
		const t = line.trim();
		if (t === '' || t.startsWith('//') || t.startsWith('/*') || t.startsWith('*')) current.push(line);
		else flush();
	}
	flush();
	return blocks;
}

/**
 * @param {string} dir
 * @param {string[]} [out]
 * @returns {string[]}
 */
function walk(dir, out = []) {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const p = join(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === '.svelte-kit') continue;
			walk(p, out);
		} else out.push(p);
	}
	return out;
}

/// Every syncer row as the SET of source paths it names, one set per row. A
/// pair is registered when one set holds both halves — two files each paired
/// with some third module are two rows, not one, which the flattened
/// membership test this replaced could not see. The mirror-test column is
/// deliberately not read: a declaration names the module, never its suite.
/**
 * @param {string} syncerText
 * @returns {{ rows: Set<string>[], errors: string[] }}
 */
export function registeredRows(syncerText) {
	const { rows: parsed, errors } = parseSyncerRows(syncerText);
	/** @type {Set<string>[]} */
	const rows = [];
	for (const row of parsed.values()) {
		/** @type {Set<string>} */
		const paths = new Set();
		for (const cell of row.cells.slice(0, 2)) for (const p of pathsInCell(cell)) paths.add(p);
		rows.push(paths);
	}
	return { rows, errors };
}

/**
 * @param {readonly Set<string>[]} rows
 * @param {string} a
 * @param {string} b
 * @returns {boolean}
 */
export function isRegisteredPair(rows, a, b) {
	return rows.some((r) => r.has(a) && r.has(b));
}

/**
 * Resolve a relatively-named counterpart against the tree. Returns every source
 * path whose tail matches, so the caller can tell "one answer" from "no answer"
 * and from "a guess".
 *
 * @param {string} rel
 * @param {readonly string[]} paths
 * @returns {string[]}
 */
export function resolveRelative(rel, paths) {
	return paths.filter((p) => p === rel || p.endsWith(`/${rel}`));
}

/**
 * Every twin declaration in the tree, with the properties evaluated.
 *
 * @param {readonly {path: string, text: string}[]} sources
 * @param {readonly Set<string>[]} rows
 * @param {{ exists?: (path: string) => boolean, paths?: readonly string[] }} [opts]
 * @returns {Declaration[]}
 */
export function collectDeclarations(sources, rows, opts = {}) {
	const exists = opts.exists ?? ((/** @type {string} */ p) => existsSync(join(REPO_ROOT, p)));
	const paths = opts.paths ?? sources.map((s) => s.path);
	/** @type {Declaration[]} */
	const found = [];

	for (const { path, text } of sources) {
		const isWeb = path.startsWith('apps/web/');
		const header = headerComment(text);
		/** @type {Set<string>} */
		const seen = new Set();

		for (const [scope, haystacks] of /** @type {['header' | 'body', string[]][]} */ ([
			['header', [header]],
			['body', commentBlocks(text)],
		])) {
			for (const [pattern, anchored] of /** @type {[RegExp, boolean][]} */ ([
				[DECLARATION, true],
				[RELATIVE_DECLARATION, false],
			])) {
				for (const m of haystacks.flatMap((h) => [...h.matchAll(new RegExp(pattern.source, 'g'))])) {
					const named = m[1];
					if (anchored === false && /^(?:apps|packages)\//.test(named)) continue;
					if (/\.test\.ts$|_test\.dart$/.test(named)) continue;
					// Same-platform: a reference, not a twin. A web file naming another
					// `.ts` is talking about a sibling.
					if (isWeb === named.endsWith('.ts')) continue;

					const candidates = anchored ? [named] : resolveRelative(named, paths);
					const counterpart = candidates.length === 1 ? candidates[0] : named;
					if (seen.has(counterpart)) continue;
					seen.add(counterpart);

					found.push({
						file: path,
						counterpart,
						scope,
						exists: anchored ? exists(named) : candidates.length > 0,
						registered:
							candidates.length === 1 && isRegisteredPair(rows, path, candidates[0]),
						ambiguous: candidates.length > 1 ? candidates : [],
					});
				}
			}
		}
	}
	return found;
}

/// The public top-level names a source file declares — what a sibling module
/// could import from it. TypeScript's are the `export`ed ones; Dart's are every
/// top-level declaration whose name does not start with `_`.
const TS_EXPORTS = [
	/^export\s+(?:declare\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)/,
	/^export\s+(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/,
	/^export\s+(?:const|let|var)\s+([A-Za-z_$][\w$]*)/,
	/^export\s+(?:type|interface|enum)\s+([A-Za-z_$][\w$]*)/,
];

const DART_DECLS = [
	/^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+)*(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_$][\w$]*)/,
	/^(?:const|final)\s+(?:[\w$<>,?\s]+?\s+)?([A-Za-z_$][\w$]*)\s*=/,
	/^[A-Za-z_$][\w$<>,?.[\]]*(?:\s+[\w$<>,?.[\]]+)*?\s+(?:get\s+)?([A-Za-z_$][\w$]*)\s*(?:\(|=>|\{)/,
];

/// Words the third Dart pattern would otherwise capture out of a top-level
/// statement. Anchoring at column 0 removes indented control flow; these are
/// what remains.
const DART_KEYWORDS = new Set([
	'if', 'for', 'while', 'switch', 'return', 'await', 'yield', 'else', 'do', 'try',
	'catch', 'finally', 'assert', 'throw', 'new', 'const', 'final', 'var', 'void',
	'get', 'set', 'late', 'part', 'library', 'import', 'export', 'typedef', 'class',
	'enum', 'mixin', 'extension', 'abstract', 'static', 'external', 'operator',
]);

/**
 * @param {string} path
 * @param {string} text
 * @returns {Set<string>}
 */
export function topLevelNames(path, text) {
	const patterns = path.endsWith('.ts') ? TS_EXPORTS : DART_DECLS;
	/** @type {Set<string>} */
	const out = new Set();
	for (const line of text.split('\n')) {
		for (const p of patterns) {
			const m = line.match(p);
			if (m === null) continue;
			if (!m[1].startsWith('_') && !DART_KEYWORDS.has(m[1])) out.add(m[1]);
			break;
		}
	}
	return out;
}

/**
 * @param {readonly Declaration[]} declarations
 * @param {readonly KnownGap[]} [gaps]
 * @param {readonly NotPair[]} [notPairs]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkDeclarations(declarations, gaps = KNOWN_GAPS, notPairs = NOT_PAIRS) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const key = (/** @type {{file: string, counterpart: string}} */ d) => `${d.file} -> ${d.counterpart}`;
	const known = new Map(gaps.map((g) => [key(g), g]));
	const judged = new Set(notPairs.flatMap((n) => [`${n.web} -> ${n.mobile}`, `${n.mobile} -> ${n.web}`]));
	const seen = new Set();

	for (const d of declarations) {
		const k = key(d);
		const gap = known.get(k);
		if (gap) seen.add(k);

		const broken = !d.exists || !d.registered;
		if (gap && !broken) {
			errors.push(
				`${k} — listed in KNOWN_GAPS ("${gap.reason}") but it is now a well-formed ` +
					`registered pair. Delete the entry; a register that keeps a closed gap ` +
					`stops being a list of what is still owed.`,
			);
			continue;
		}
		if (gap) {
			ok.push(`${k} -> known gap: ${gap.reason}`);
			continue;
		}
		if (!d.exists) {
			errors.push(
				`${d.file} declares a twin at \`${d.counterpart}\`, which does not exist. ` +
					`A reader told to keep two halves in step cannot find the other one, and ` +
					`the registries never see this claim — they hold paths of their own. Point ` +
					`the header at where the file moved to.`,
			);
			continue;
		}
		// A body declaration is checked for existence only. The registration
		// property needs the claim to be about the MODULE, and a sentence beside
		// one function ("Mirrors `core/data.ts:createClub`") is about that call —
		// 14 of them sit in the tree, none registrable. § 1243 pinned the same
		// line from the other side: a claim written below the first statement is
		// not a header.
		if (d.scope === 'body') {
			ok.push(`${k} -> named outside the header; existence checked, registration not claimed`);
			continue;
		}
		if (d.ambiguous.length > 0) {
			errors.push(
				`${d.file} declares a twin at the relative path \`${d.counterpart}\`, which ` +
					`matches ${d.ambiguous.length} files (${d.ambiguous.join(', ')}). The guard ` +
					`will not guess which pair is meant — write the repo-rooted path.`,
			);
			continue;
		}
		if (judged.has(k)) {
			ok.push(`${k} -> judged not a pair; NOT_PAIRS carries the reason`);
			continue;
		}
		if (!d.registered) {
			errors.push(
				`${d.file} declares a twin at \`${d.counterpart}\`, but no row of the ` +
					`shared-library-syncer table carries both files. The syncer is the only ` +
					`automated detector of parity divergence and works from that table alone, ` +
					`so this pair's divergence is never caught while its own header reads as ` +
					`though it is covered — the § 641 / § 760 failure. Register it in BOTH ` +
					`CLAUDE.md's lockstep bullet and the syncer table, or — if the two are not a ` +
					`pair and cannot become one — record the judgement in NOT_PAIRS with its ` +
					`reason and the shared top-level names measured today.`,
			);
			continue;
		}
		ok.push(`${k} -> registered`);
	}

	for (const [k, gap] of known) {
		if (seen.has(k)) continue;
		errors.push(
			`KNOWN_GAPS lists \`${k}\` ("${gap.reason}"), but no header declares it. The file ` +
				`was renamed, deleted, or its header reworded — drop the entry rather than ` +
				`leaving it standing as cover for a declaration that is gone.`,
		);
	}

	if (declarations.length < MIN_DECLARATIONS) {
		errors.push(
			`only ${declarations.length} twin declaration(s) found across ${SOURCE_ROOTS.length} ` +
				`source roots, under the floor of ${MIN_DECLARATIONS}. Either the header ` +
				`convention changed or DECLARATION stopped matching it, and this guard is ` +
				`reporting an empty census as a clean one.`,
		);
	}

	return { errors, ok };
}

/**
 * Property 4: every judgement in NOT_PAIRS is still the honest answer.
 *
 * @param {readonly NotPair[]} entries
 * @param {readonly Set<string>[]} rows
 * @param {{ read?: (path: string) => string | null }} [opts]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkNotPairs(entries, rows, opts = {}) {
	const read =
		opts.read ??
		((/** @type {string} */ p) => {
			const abs = join(REPO_ROOT, p);
			return existsSync(abs) ? readFileSync(abs, 'utf-8') : null;
		});
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	for (const entry of entries) {
		const label = `${entry.web} !↔ ${entry.mobile}`;
		const webText = read(entry.web);
		const mobileText = read(entry.mobile);
		if (webText === null || mobileText === null) {
			errors.push(
				`NOT_PAIRS entry ${label} names a file that does not exist ` +
					`(${webText === null ? entry.web : entry.mobile}). The judgement was about two ` +
					`files that were both there — re-make it against wherever the code went, or ` +
					`drop the entry.`,
			);
			continue;
		}
		if (isRegisteredPair(rows, entry.web, entry.mobile)) {
			errors.push(
				`NOT_PAIRS entry ${label} says the two are not a lockstep pair, but a syncer row ` +
					`now carries both. The registries and this register contradict each other; ` +
					`delete the entry if the pair is real.`,
			);
			continue;
		}

		const webNames = topLevelNames(entry.web, webText);
		const mobileNames = topLevelNames(entry.mobile, mobileText);
		if (webNames.size === 0 || mobileNames.size === 0) {
			errors.push(
				`NOT_PAIRS entry ${label}: the symbol reader found no top-level names in ` +
					`${webNames.size === 0 ? entry.web : entry.mobile}. A file with no public ` +
					`surface cannot be half of anything, so this is the reader having gone blind ` +
					`— every entry would then measure an empty shared set and pass.`,
			);
			continue;
		}

		const shared = [...webNames].filter((n) => mobileNames.has(n)).sort();
		const recorded = [...entry.shared].sort();
		if (shared.join(' ') !== recorded.join(' ')) {
			errors.push(
				`NOT_PAIRS entry ${label} recorded [${recorded.join(', ')}] as the top-level names ` +
					`both files declare; they now declare [${shared.join(', ')}]. Re-read the ` +
					`reason ("${entry.reason.slice(0, 90)}…") against what the two files do today: ` +
					`a surface that has converged is a pair that should be registered, and one ` +
					`that has diverged means the entry describes something that no longer exists. ` +
					`Update the set only once the reason still holds.`,
			);
			continue;
		}
		ok.push(`${label} -> judged not a pair; shared surface unchanged (${shared.length})`);
	}

	return { errors, ok };
}

/** @returns {{path: string, text: string}[]} */
export function readSources(roots = SOURCE_ROOTS) {
	/** @type {{path: string, text: string}[]} */
	const out = [];
	for (const root of roots) {
		for (const abs of walk(join(REPO_ROOT, root))) {
			if (!/\.(ts|dart)$/.test(abs)) continue;
			if (/\.test\.ts$|_test\.dart$/.test(abs)) continue;
			out.push({ path: relative(REPO_ROOT, abs), text: readFileSync(abs, 'utf-8') });
		}
	}
	return out;
}

function main() {
	const { rows, errors: registryErrors } = registeredRows(readFileSync(SYNCER_DOC, 'utf-8'));
	const declarations = collectDeclarations(readSources(), rows);
	const { errors, ok } = checkDeclarations(declarations);
	const judged = checkNotPairs(NOT_PAIRS, rows);
	const all = [...registryErrors, ...errors, ...judged.errors];

	for (const line of [...ok, ...judged.ok]) console.log(`[OK] ${line}`);
	for (const line of all) console.error(`[FAIL] ${line}`);

	if (all.length > 0) {
		console.error(`\n${all.length} twin declaration problem(s).`);
		return 1;
	}
	console.log(
		`\n${declarations.length} twin declaration(s) across ${SOURCE_ROOTS.length} source roots; ` +
			`every one names a file that exists and a pair the syncer table carries, ` +
			`bar the ${KNOWN_GAPS.length} in KNOWN_GAPS. ${NOT_PAIRS.length} judged-not-a-pair ` +
			`entries re-measured.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

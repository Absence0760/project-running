#!/usr/bin/env node
// Guardrail: a source file that declares a cross-platform twin is a REGISTERED
// parity pair, and the file it names exists.
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
// before anyone thinks about a registry. Two properties:
//
//   1. The counterpart path a declaration names EXISTS. A file that moved
//      leaves the claim pointing at nothing, and the reader then cannot find
//      the half they were told to keep in step. This is the same defect
//      `check_parity_pair_registry`'s property 4 exists for, one layer out: that
//      one reads the registries, so a stale path in a SOURCE header is invisible
//      to it.
//
//   2. The declaration corresponds to a row of the syncer table carrying BOTH
//      files. The table is the operative registry — the syncer agent is the only
//      automated detector of parity divergence, and it works from that table
//      alone. A declared pair missing from it is a pair whose divergence is
//      never caught, while its own header reads as though it is covered.
//
// Registration is checked by PATH rather than by name. The registry keys a pair
// on its WEB basename, so `gear_rotation_pick.dart` (the pair `rotation_pick`)
// is registered under a name its own filename does not carry; a name-keyed check
// would report it and teach the next reader to distrust the guard.
//
// KNOWN_GAPS is the register of declarations that violate one of the two
// properties TODAY. Every entry is a real defect, not an exemption on the merits
// — closing one means editing CLAUDE.md, the syncer table, or the header, none
// of which this guard can do. An entry that has stopped being a violation FAILS,
// so the register can only shrink, and an entry naming a declaration that no
// longer exists fails too rather than sitting as cover.
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

/// Where a twin half can live. `packages/core_models` is here because two pairs
/// (`profile_query`, `strava_sync_result`) keep their Dart half there rather
/// than under `apps/mobile_android/lib`.
export const SOURCE_ROOTS = [
	'apps/web/src/lib',
	'apps/mobile_android/lib',
	'packages/core_models/lib',
];

/// A DECLARATION of a twin, not a mention of one. The verb has to be one that
/// asserts the relationship, and the path has to follow within a short window,
/// or a sentence about keeping a jsonb key registry in lockstep reads as a
/// parity pair. `Mirrors` is included because four Dart halves are written that
/// way; `in lockstep with` deliberately is NOT — it is the phrase this repo uses
/// for every kind of coupling, including a client and an SQL CHECK.
///
/// Three forms found in the tree were unreadable until decisions § 1243: a
/// backticked path carrying a `:symbol` suffix (`run_stats.ts` names
/// `…/run_stats.dart:movingTimeOf`), a path written with NO backticks at all
/// (`workout_kind_color.ts`), and `Dart twin` / `ported from` / `Dart port of`
/// in place of the `… of` verbs. The path stays anchored to a repo root: a
/// relative counterpart (`web's \`training/x.ts\``) is a fourth form and is
/// deliberately still unread, because resolving one means guessing a root and
/// the guess reaches non-pairs — see the followups entry.
export const DECLARATION =
	/(?:[Dd]art twin(?: of)?|TS twin(?: of)?|[Dd]art mirror of|TS.?.?Dart parity pair(?:\s*(?:with|:))?|[Mm]irrors|[Tt]win of|[Pp]orted from|[Dd]art port of|TS port of)[^`]{0,60}`?((?:apps|packages)\/[A-Za-z0-9_./-]+\.(?:ts|dart))(?::[A-Za-z0-9_]+)?`?/g;

/// A floor under the census. A reworded header convention, or a header-block
/// scanner that stops recognising `///`, would otherwise report zero
/// declarations as zero violations.
///
/// It is only a floor worth having if it sits near the real count. At 60
/// against a census of 106 it had 46 of slack, so the 25 % of the tree the
/// reader could not see (decisions § 1243) passed it unremarked — the guard's
/// own failure mode, undetected by the check written for it.
export const MIN_DECLARATIONS = 155;

/**
 * @typedef {{ file: string, counterpart: string, reason: string }} KnownGap
 * @typedef {{ file: string, counterpart: string, exists: boolean, registered: boolean }} Declaration
 */

/// Declarations that violate a property today. Each is a defect with a home
/// somewhere this guard cannot reach.
/** @type {readonly KnownGap[]} */
export const KNOWN_GAPS = /** @type {KnownGap[]} */ ([]);

/// Lines that may sit between the top of a file and the block that documents
/// it. A module puts its imports above its doc comment far more often than
/// below it, and a scanner that stops at the first non-comment line therefore
/// read an EMPTY header for every such file — 37 of them carrying a
/// twin-shaped claim the guard never saw at all, `run_stats.ts` and
/// `elevation.dart` among them. decisions § 1243.
const PROLOGUE = /^(?:import\b|export\s.+\bfrom\b|library\b|part\b|@JS\b|['"]use strict['"])/;

/**
 * The header comment of a source file: every comment line above the first line
 * of real code, folded onto one line so a declaration split over a wrap still
 * reads as one. Imports and blank lines are stepped over rather than treated as
 * code, so a doc block below an import prologue is still the header.
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
		if (PROLOGUE.test(t)) continue;
		break;
	}
	return head.join('\n').replace(/\n\s*(?:\/\/\/?|\*)\s?/g, ' ');
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

/// Every source path a syncer row names in its two SOURCE columns. The
/// mirror-test column is deliberately not read: a declaration names the module,
/// never its suite.
/**
 * @param {string} syncerText
 * @returns {{ paths: Set<string>, errors: string[] }}
 */
export function registeredPaths(syncerText) {
	const { rows, errors } = parseSyncerRows(syncerText);
	/** @type {Set<string>} */
	const paths = new Set();
	for (const row of rows.values()) {
		for (const cell of row.cells.slice(0, 2)) for (const p of pathsInCell(cell)) paths.add(p);
	}
	return { paths, errors };
}

/**
 * Every twin declaration in the tree, with the two properties evaluated.
 *
 * @param {readonly {path: string, text: string}[]} sources
 * @param {Set<string>} registered
 * @param {(path: string) => boolean} [exists]
 * @returns {Declaration[]}
 */
export function collectDeclarations(sources, registered, exists = (p) => existsSync(join(REPO_ROOT, p))) {
	/** @type {Declaration[]} */
	const found = [];
	for (const { path, text } of sources) {
		const isWeb = path.startsWith('apps/web/');
		for (const m of headerComment(text).matchAll(DECLARATION)) {
			const counterpart = m[1];
			// Same-platform: a reference, not a twin. A web file naming another
			// `.ts` is talking about a sibling.
			if (isWeb === counterpart.endsWith('.ts')) continue;
			if (/\.test\.ts$|_test\.dart$/.test(counterpart)) continue;
			found.push({
				file: path,
				counterpart,
				exists: exists(counterpart),
				registered: registered.has(path) && registered.has(counterpart),
			});
		}
	}
	return found;
}

/**
 * @param {readonly Declaration[]} declarations
 * @param {readonly KnownGap[]} [gaps]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkDeclarations(declarations, gaps = KNOWN_GAPS) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const key = (/** @type {{file: string, counterpart: string}} */ d) => `${d.file} -> ${d.counterpart}`;
	const known = new Map(gaps.map((g) => [key(g), g]));
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
		if (!d.registered) {
			errors.push(
				`${d.file} declares a twin at \`${d.counterpart}\`, but no row of the ` +
					`shared-library-syncer table carries both files. The syncer is the only ` +
					`automated detector of parity divergence and works from that table alone, ` +
					`so this pair's divergence is never caught while its own header reads as ` +
					`though it is covered — the § 641 / § 760 failure. Register it in BOTH ` +
					`CLAUDE.md's lockstep bullet and the syncer table, or reword the header to ` +
					`say what the relationship actually is.`,
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
	const { paths, errors: registryErrors } = registeredPaths(readFileSync(SYNCER_DOC, 'utf-8'));
	const declarations = collectDeclarations(readSources(), paths);
	const { errors, ok } = checkDeclarations(declarations);
	const all = [...registryErrors, ...errors];

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of all) console.error(`[FAIL] ${line}`);

	if (all.length > 0) {
		console.error(`\n${all.length} twin declaration problem(s).`);
		return 1;
	}
	console.log(
		`\n${declarations.length} twin declaration(s) across ${SOURCE_ROOTS.length} source roots; ` +
			`every one names a file that exists and a pair the syncer table carries, ` +
			`bar the ${KNOWN_GAPS.length} in KNOWN_GAPS.`,
	);
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

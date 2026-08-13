#!/usr/bin/env node
// Guardrail: the TS↔Dart parity-pair registry says the same thing in both
// places it is written down.
//
//   CLAUDE.md — the "TS↔Dart parity helpers must stay in lockstep" bullet,
//     which is the human-facing list a session reads to decide whether an
//     edit it just made needs mirroring to the other platform.
//   .claude/agents/shared-library-syncer.md — the "The pairs (canonical list)"
//     table, which is the list the shared-library-syncer AGENT works from.
//
// Why this exists: decisions.md § 604. The two had drifted 19 pairs apart —
// 15 registered in the prose and absent from the table, 4 the other way. The
// table is the operative half: the syncer is the only automated detector of
// parity divergence, and its own instructions tell it to stop rather than
// invent a claim about a pair the table does not list. So a pair missing from
// it is a pair whose divergence is never caught, silently, while CLAUDE.md
// reads as though it is covered. `roadbook` was in that state on the day a
// change altered it on web, on Dart and in the watch port at once.
//
// That is not a hypothetical failure mode for this repo: decisions.md § 305
// records two helpers whose doc comments claimed lockstep for a long time
// while they carried different algorithms and each suite pinned the opposite
// answer. Undetected divergence is the expensive kind.
//
// Four properties, all cheap:
//
//   1. Every pair named in CLAUDE.md has a row in the syncer table.
//   2. Every row in the syncer table is named in CLAUDE.md. The reverse
//      direction matters because CLAUDE.md is what a session reads FIRST: a
//      pair missing from it reads as a single-platform helper, and the edit
//      never reaches the agent that would have caught the divergence.
//   3. Where CLAUDE.md annotates the two file paths, they agree with the row.
//   4. Every path either registry names exists on disk. A rename that leaves
//      a registry pointing at nothing is the same defect one step later —
//      and it was already live: profile_query.ts's own header named a Dart
//      twin at a path that does not exist.
//
// Check 4 overlaps deliberately with `lib_structure_guards.test.ts`, which
// already asserts the table's web `.ts` paths exist. That one lives in the web
// unit suite, which is gated on a non-docs diff — so it is skipped by exactly
// the markdown-only edit that breaks a path. Keeping the check here as well
// covers the Dart and mirror-test paths it never read, and covers all of them
// on a docs PR.
//
// The vacuous-pass case is checked throughout: each parser fails loudly if its
// anchor text is gone or it matched nothing, rather than reporting two empty
// sets as agreement. A guard that inspects nothing enforces nothing. The
// bidirectionality of check 1+2 is itself an anti-vacuity property — a reworded
// entry drops out of one set and is immediately reported as missing from it,
// so a parser that quietly stops understanding the prose cannot pass.
//
// Run: `node scripts/check_parity_pair_registry.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_parity_pair_registry.test.mjs`

import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const CLAUDE_DOC = join(REPO_ROOT, 'CLAUDE.md');
export const SYNCER_DOC = join(REPO_ROOT, '.claude', 'agents', 'shared-library-syncer.md');

const CLAUDE_BULLET = 'TS↔Dart parity helpers must stay in lockstep.';
const CLAUDE_LIST = 'The pairs are:';
const SYNCER_HEADING = '## The pairs (canonical list)';

const WEB_LIB = 'apps/web/src/lib/';
const MOBILE_ROOT = 'apps/mobile_android/';

/// A pair carrying its two file paths, written as
/// `name` (web `area/name.ts` ↔ mobile `name.dart` …). The optional inner
/// backticked run absorbs an annotation such as exif_strip's `stripJpegExif`.
const ANNOTATED = /`([a-z0-9_]+)`\s*\(web\s+`([A-Za-z0-9_./-]+\.ts)`\s*(?:`[^`]*`\s*)*↔\s*mobile\s+`([A-Za-z0-9_./-]+\.dart)`/g;

/// The run of bare, un-annotated names the list opens with (`training`,
/// `segments`, …) before the first entry that spells its paths out.
const BARE_HEAD = /^\s*((?:`[a-z0-9_]+`,\s*)+)/;

/// The `track_projection` pair is written as a trailing clause rather than a
/// list entry, because its Dart half is a pair of helpers inside a widget file
/// rather than a module of its own.
const TAIL_PAIR = /plus the `track_projection\.ts`/;

/// A repo-relative source path named inside a table cell.
const REPO_PATH = /`((?:apps|packages)\/[A-Za-z0-9_./-]+\.(?:ts|dart))`/g;

/// The mirror-test column's two forms: a web path relative to
/// `apps/web/src/lib/`, and a Dart path relative to `apps/mobile_android/`
/// unless it is already repo-relative (core_models' suite is).
const TEST_PATH = /`([A-Za-z0-9_./-]+(?:\.test\.ts|_test\.dart))`/g;

/// Every pair named in CLAUDE.md's lockstep bullet, mapped to the two paths it
/// annotates (null when it names none — the bare head entries and the tail
/// clause carry no paths, and are checked for membership only).
export function parseClaudePairs(text) {
	const pairs = new Map();
	const errors = [];

	const bulletAt = text.indexOf(CLAUDE_BULLET);
	if (bulletAt === -1) {
		errors.push(
			`CLAUDE.md has no "${CLAUDE_BULLET}" bullet. Either the parity-pair registry ` +
				`was removed, or it was reworded and this guard now checks nothing.`,
		);
		return { pairs, errors };
	}

	// The bullet is one line; anything past its newline belongs to the
	// watch-port paragraph, whose entries are one-way ports and explicitly NOT
	// part of the enforced web↔mobile lockstep.
	const lineEnd = text.indexOf('\n', bulletAt);
	const bullet = text.slice(bulletAt, lineEnd === -1 ? text.length : lineEnd);

	const listAt = bullet.indexOf(CLAUDE_LIST);
	if (listAt === -1) {
		errors.push(
			`the CLAUDE.md lockstep bullet has no "${CLAUDE_LIST}" enumeration. The list ` +
				`was reworded; update this guard's anchor rather than leaving it matching ` +
				`nothing.`,
		);
		return { pairs, errors };
	}
	const body = bullet.slice(listAt + CLAUDE_LIST.length);

	const head = body.match(BARE_HEAD);
	if (head === null) {
		errors.push(
			`the CLAUDE.md pair list does not open with the run of bare names ` +
				`(\`training\`, \`segments\`, …). Its shape changed and this guard would ` +
				`silently drop those pairs.`,
		);
	} else {
		for (const m of head[1].matchAll(/`([a-z0-9_]+)`/g)) pairs.set(m[1], null);
	}

	let annotated = 0;
	for (const m of body.matchAll(ANNOTATED)) {
		annotated++;
		pairs.set(m[1], { ts: m[2], dart: m[3] });
	}
	if (annotated === 0) {
		errors.push(
			`no entry in the CLAUDE.md pair list is written as \`name\` (web \`x.ts\` ↔ ` +
				`mobile \`x.dart\`). The annotation form changed and this guard can no ` +
				`longer read the list.`,
		);
	}

	if (TAIL_PAIR.test(body)) pairs.set('track_projection', null);

	return { pairs, errors };
}

/// Every row of the syncer agent's canonical table, keyed by the pair name its
/// web path ends in, carrying the raw cells so the path checks can read them.
export function parseSyncerRows(text) {
	const rows = new Map();
	const errors = [];

	const headingAt = text.indexOf(SYNCER_HEADING);
	if (headingAt === -1) {
		errors.push(
			`.claude/agents/shared-library-syncer.md has no "${SYNCER_HEADING}" heading. ` +
				`The table moved or was renamed and this guard now checks nothing.`,
		);
		return { rows, errors };
	}

	const lines = text.slice(headingAt).split('\n');
	lines.forEach((line, i) => {
		if (!line.startsWith('|')) return;
		const cells = line.split('|').slice(1, -1);
		if (cells.length < 3) return;
		const web = cells[0].match(/`(apps\/web\/src\/lib\/[A-Za-z0-9_./-]+\/([A-Za-z0-9_]+)\.ts)`/);
		if (web === null) return;
		rows.set(web[2], {
			line: i + 1,
			web: web[1],
			cells,
		});
	});

	if (rows.size === 0) {
		errors.push(
			`the syncer table under "${SYNCER_HEADING}" yielded no rows. Its column shape ` +
				`changed and this guard is enforcing nothing.`,
		);
	}

	return { rows, errors };
}

/// Repo-relative paths a table cell names, with the mirror-test column's two
/// relative forms resolved.
export function pathsInCell(cell) {
	const found = [];
	for (const m of cell.matchAll(REPO_PATH)) found.push(m[1]);
	for (const m of cell.matchAll(TEST_PATH)) {
		const raw = m[1];
		if (raw.startsWith('apps/') || raw.startsWith('packages/')) {
			found.push(raw);
		} else if (raw.endsWith('.test.ts')) {
			found.push(WEB_LIB + raw);
		} else {
			found.push(MOBILE_ROOT + raw);
		}
	}
	return [...new Set(found)];
}

function endsWithPath(full, suffix) {
	return full === suffix || full.endsWith(`/${suffix}`);
}

export function checkRegistries(claudeText, syncerText, exists = (p) => existsSync(join(REPO_ROOT, p))) {
	const claude = parseClaudePairs(claudeText);
	const syncer = parseSyncerRows(syncerText);
	const errors = [...claude.errors, ...syncer.errors];
	const ok = [];

	// A parser that failed its anchor checks reports an empty set; comparing it
	// would bury the real error under dozens of derived ones.
	if (errors.length > 0) return { errors, ok };

	const missingFromSyncer = [...claude.pairs.keys()].filter((n) => !syncer.rows.has(n)).sort();
	if (missingFromSyncer.length > 0) {
		errors.push(
			`${missingFromSyncer.length} pair(s) named in CLAUDE.md have no row in the ` +
				`shared-library-syncer table: ${missingFromSyncer.join(', ')}.\n` +
				`  The table is the list the agent works from — its own instructions tell ` +
				`it to stop rather than invent a parity claim about a pair it cannot find ` +
				`there — so these are pairs whose divergence is never detected. Add a row ` +
				`per pair to .claude/agents/shared-library-syncer.md (decisions.md § 604).`,
		);
	}

	const missingFromClaude = [...syncer.rows.keys()].filter((n) => !claude.pairs.has(n)).sort();
	if (missingFromClaude.length > 0) {
		errors.push(
			`${missingFromClaude.length} pair(s) in the shared-library-syncer table are ` +
				`not named in CLAUDE.md's lockstep bullet: ${missingFromClaude.join(', ')}.\n` +
				`  CLAUDE.md is what a session reads first, so an unlisted pair reads as a ` +
				`single-platform helper and the edit never reaches the agent. Add each to ` +
				`the "The pairs are:" enumeration (decisions.md § 604).`,
		);
	}

	for (const [name, annotation] of claude.pairs) {
		const row = syncer.rows.get(name);
		if (!row || annotation === null) continue;
		const expectedWeb = WEB_LIB + annotation.ts;
		if (row.web !== expectedWeb) {
			errors.push(
				`${name} — CLAUDE.md names web \`${annotation.ts}\` (${expectedWeb}) but the ` +
					`syncer row points at \`${row.web}\`. One of the two registries is aimed ` +
					`at the wrong file.`,
			);
		}
		const mobilePaths = pathsInCell(row.cells[1]);
		if (!mobilePaths.some((p) => endsWithPath(p, annotation.dart))) {
			errors.push(
				`${name} — CLAUDE.md names mobile \`${annotation.dart}\`, which the syncer ` +
					`row's mobile cell does not mention (it names ` +
					`${mobilePaths.length > 0 ? mobilePaths.map((p) => `\`${p}\``).join(', ') : 'no path at all'}).`,
			);
		}
	}

	let checkedPaths = 0;
	for (const [name, row] of syncer.rows) {
		for (const cell of row.cells) {
			for (const path of pathsInCell(cell)) {
				checkedPaths++;
				if (!exists(path)) {
					errors.push(
						`${name} — the syncer row names \`${path}\`, which does not exist. A ` +
							`registry pointing at a moved or deleted file is a pair nothing ` +
							`checks; fix the row or retire the pair.`,
					);
				}
			}
		}
	}
	if (checkedPaths === 0) {
		errors.push(
			`no file paths were extracted from any syncer row, so nothing was checked for ` +
				`existence. The cells' path formatting changed.`,
		);
	}

	if (errors.length === 0) {
		ok.push(`${claude.pairs.size} pair(s) registered identically in both registries`);
		ok.push(`${checkedPaths} registered path(s) exist on disk`);
	}

	return { errors, ok };
}

function main() {
	const { errors, ok } = checkRegistries(
		readFileSync(CLAUDE_DOC, 'utf-8'),
		readFileSync(SYNCER_DOC, 'utf-8'),
	);

	for (const line of ok) console.log(`[OK] ${line}`);
	for (const line of errors) console.error(`[FAIL] ${line}`);

	if (errors.length > 0) {
		console.error(`\n${errors.length} parity-pair registry problem(s).`);
		return 1;
	}
	return 0;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exit(main());

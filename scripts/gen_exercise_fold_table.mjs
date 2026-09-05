#!/usr/bin/env node
// Generates the frozen case-fold table the exercise grouping key is lower-cased
// through, from the Unicode data the running Node carries.
//
//   node scripts/gen_exercise_fold_table.mjs          # rewrite the two client tables
//   node scripts/gen_exercise_fold_table.mjs --sql    # print the SQL literals a migration pastes
//
// Output (committed, never hand-edit — re-run this instead):
//   apps/web/src/lib/gym/exercise_fold_table.ts
//   apps/mobile_android/lib/exercise_fold_table.dart
//   apps/mobile_ios/lib/exercise_fold_table.dart      (the twin, decisions § 39)
//
// Why a table at all. `normaliseExerciseName` is derived on three rails and the
// answer is PERSISTED as `gym_sets.exercise_key`, `gym_routine_exercises.
// exercise_key` and `exercises.name_key`. Every rail used to reach for its own
// runtime's lowercase: JS full case mapping from Node's ICU, Dart simple case
// mapping from an older table, Postgres `lower()` under the pinned ICU root
// collation. Measured over every assignable code point after the two folds
// § 830 named, the three disagreed at 465 code points web-to-mobile, 410
// mobile-to-server and 55 web-to-server — and each of those is a name one rail
// cannot persist without a 23514 from the other two rails' CHECK.
//
// Freezing the table removes the runtime from the answer entirely, the way
// § 790 removed the locale provider from the whitespace class. The authority is
// Unicode's SIMPLE lowercase mapping, not the full one, for two reasons that
// are the same reason: a per-code-point table cannot express a context (full
// lowercase carries Final_Sigma, which the ς→σ fold in `gym_prs` already
// collapses in both directions) and it cannot express a 1:many mapping (full
// lowercase has exactly one unconditional expansion, U+0130 → i + U+0307,
// where the simple mapping gives the bare `i` this key has taken since § 830).
// Under the simple mapping every entry is 1:1, which is what lets the SQL rail
// be a `translate()`.
//
// The input is the running Node's Unicode tables, so re-running this under a
// newer Node produces a NEWER table. That is a deliberate act, not a drift to
// be corrected: the shipped table is frozen at the version stamped into it, and
// moving it means writing a migration that replaces `normalise_exercise_name`
// and re-validates the three CHECKs alongside the regenerated client files.
// There is deliberately no "re-render and compare" guard for that reason;
// `scripts/check_shared_constants.mjs` compares the three RAILS instead.

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const WEB_OUTPUT_PATH = 'apps/web/src/lib/gym/exercise_fold_table.ts';
export const MOBILE_OUTPUT_PATH = 'apps/mobile_android/lib/exercise_fold_table.dart';
export const IOS_OUTPUT_PATH = 'apps/mobile_ios/lib/exercise_fold_table.dart';

/**
 * The one code point whose UNCONDITIONAL full lowercase mapping is longer than
 * one code point, and the simple mapping this table takes instead.
 * SpecialCasing.txt carries exactly one such entry; `buildFoldTable` throws if
 * a newer Unicode adds a second rather than silently tabling a truncation.
 */
export const SIMPLE_OVERRIDES = new Map([[0x0130, 0x0069]]);

/**
 * Every code point Unicode simple lowercase does not leave alone, ascending.
 *
 * @returns {Array<{ cp: number, folded: number }>}
 */
export function buildFoldTable() {
	/** @type {Array<{ cp: number, folded: number }>} */
	const entries = [];

	for (let cp = 0; cp <= 0x10ffff; cp++) {
		if (cp >= 0xd800 && cp <= 0xdfff) continue;
		const source = String.fromCodePoint(cp);
		const lowered = source.toLowerCase();
		if (lowered === source) continue;

		const override = SIMPLE_OVERRIDES.get(cp);
		const points = [...lowered].map((c) => /** @type {number} */ (c.codePointAt(0)));
		if (override === undefined && points.length !== 1) {
			throw new Error(
				`U+${cp.toString(16).toUpperCase()} lowercases to ${points.length} code points ` +
					`and no simple mapping is declared for it. A per-code-point table cannot ` +
					`carry a 1:many fold, and the SQL rail's translate() cannot either — add ` +
					`its Unicode SIMPLE lowercase mapping to SIMPLE_OVERRIDES, and check that ` +
					`the three rails still agree before shipping the table.`,
			);
		}
		entries.push({ cp, folded: override ?? points[0] });
	}

	assertInvariants(entries);
	return entries;
}

/**
 * The claims the three rails are allowed to rely on. Each is cheap to state and
 * expensive to discover from a wrong key in production.
 *
 * @param {Array<{ cp: number, folded: number }>} entries
 */
export function assertInvariants(entries) {
	const keys = new Set(entries.map((e) => e.cp));
	for (let i = 1; i < entries.length; i++) {
		if (entries[i - 1].cp >= entries[i].cp) {
			throw new Error('the table is not strictly ascending by code point');
		}
	}
	for (const { cp, folded } of entries) {
		if (folded === cp) throw new Error(`U+${cp.toString(16)} maps to itself`);
		if (keys.has(folded)) {
			throw new Error(
				`U+${cp.toString(16)} folds to U+${folded.toString(16)}, which the table also folds. ` +
					`Every rail applies the table in ONE pass — Postgres translate() and both ` +
					`clients' per-code-point lookup — so a chain would make the fold depend on ` +
					`the order the pass happens to visit, and fold(fold(x)) would stop equalling ` +
					`fold(x) for a key the CHECK re-derives.`,
			);
		}
	}
	const ascii = entries.filter((e) => e.cp < 0x80);
	const expected = Array.from({ length: 26 }, (_, i) => ({ cp: 0x41 + i, folded: 0x61 + i }));
	if (JSON.stringify(ascii) !== JSON.stringify(expected)) {
		throw new Error(
			'the ASCII half of the table is not exactly A-Z -> a-z. The SQL rail takes a ' +
				'26-pair fast path for an all-ASCII name, which is only answer-identical to ' +
				'the full table while that is true.',
		);
	}
}

/**
 * A Postgres `U&'...'` literal, wrapped across lines by string continuation so
 * a 1,488-entry table is a reviewable block rather than one 8 KB line. Non-BMP
 * code points take the `\+XXXXXX` form; the BMP ones `\XXXX`.
 *
 * @param {number[]} points @param {string} indent @returns {string}
 */
export function sqlLiteral(points, indent) {
	const escaped = points.map((cp) =>
		cp > 0xffff
			? `\\+${cp.toString(16).toUpperCase().padStart(6, '0')}`
			: `\\${cp.toString(16).toUpperCase().padStart(4, '0')}`,
	);
	/** @type {string[]} */
	const lines = [];
	for (let i = 0; i < escaped.length; i += 16) lines.push(escaped.slice(i, i + 16).join(''));
	return `U&'${lines.join(`'\n${indent}'`)}'`;
}

/**
 * @param {number[]} values
 * @param {string} indent
 * @returns {string}
 */
function wrapHex(values, indent) {
	/** @type {string[]} */
	const lines = [];
	for (let i = 0; i < values.length; i += 8) {
		lines.push(
			indent +
				values
					.slice(i, i + 8)
					.map((cp) => `0x${cp.toString(16).toUpperCase().padStart(4, '0')},`)
					.join(' '),
		);
	}
	return lines.join('\n');
}

/**
 * @param {Array<{ cp: number, folded: number }>} entries
 * @param {string} unicodeVersion
 * @returns {string}
 */
export function renderTs(entries, unicodeVersion) {
	return `// GENERATED by scripts/gen_exercise_fold_table.mjs from Unicode ${unicodeVersion}
// — do not hand-edit; re-run the generator instead. The table is FROZEN at the
// version stamped below: regenerating it under a newer Node moves the fold, so
// it ships with a migration that replaces \`normalise_exercise_name\` and
// re-validates the three CHECKs that name it (decisions § 1175).
//
// Unicode SIMPLE lowercase mapping, the authority the exercise grouping key is
// folded through on all three rails — here, \`apps/mobile_android/lib/
// exercise_fold_table.dart\`, and the \`translate()\` inside
// \`public.normalise_exercise_name\`. Every entry is 1:1 and no value is itself
// a key, so one pass in any order gives the same answer.
//
// ${entries.length} code points, ${entries.filter((e) => e.cp > 0xffff).length} of them outside the BMP — iterate by CODE POINT,
// never by UTF-16 code unit. \`scripts/check_shared_constants.mjs\` compares the
// three rails.

/// Unicode version the mapping was frozen at. Read by the guard, which requires
/// all three rails to name the same one.
export const EXERCISE_FOLD_UNICODE_VERSION = '${unicodeVersion}';

/// Code points the fold rewrites, ascending.
export const EXERCISE_FOLD_KEYS: readonly number[] = [
${wrapHex(
	entries.map((e) => e.cp),
	'\t',
)}
];

/// What each key folds to, indexed alongside EXERCISE_FOLD_KEYS.
export const EXERCISE_FOLD_VALUES: readonly number[] = [
${wrapHex(
	entries.map((e) => e.folded),
	'\t',
)}
];
`;
}

/**
 * @param {Array<{ cp: number, folded: number }>} entries
 * @param {string} unicodeVersion
 * @returns {string}
 */
export function renderDart(entries, unicodeVersion) {
	return `// GENERATED by scripts/gen_exercise_fold_table.mjs from Unicode ${unicodeVersion}
// — do not hand-edit; re-run the generator instead. The table is FROZEN at the
// version stamped below: regenerating it under a newer Node moves the fold, so
// it ships with a migration that replaces \`normalise_exercise_name\` and
// re-validates the three CHECKs that name it (decisions § 1175).
//
// Unicode SIMPLE lowercase mapping, the authority the exercise grouping key is
// folded through on all three rails — here, \`apps/web/src/lib/gym/
// exercise_fold_table.ts\`, and the \`translate()\` inside
// \`public.normalise_exercise_name\`. Every entry is 1:1 and no value is itself
// a key, so one pass in any order gives the same answer.
//
// Dart's own \`toLowerCase()\` is not this table and must not be reached for:
// it is simple case mapping from an older Unicode revision, measured to leave
// 465 of these code points alone (decisions § 1175).
//
// ${entries.length} code points, ${entries.filter((e) => e.cp > 0xffff).length} of them outside the BMP — fold over \`runes\`,
// never over code units. \`scripts/check_shared_constants.mjs\` compares the
// three rails.
library;

/// Unicode version the mapping was frozen at. Read by the guard, which requires
/// all three rails to name the same one.
const String kExerciseFoldUnicodeVersion = '${unicodeVersion}';

/// Code points the fold rewrites, ascending.
const List<int> kExerciseFoldKeys = <int>[
${wrapHex(
	entries.map((e) => e.cp),
	'  ',
)}
];

/// What each key folds to, indexed alongside [kExerciseFoldKeys].
const List<int> kExerciseFoldValues = <int>[
${wrapHex(
	entries.map((e) => e.folded),
	'  ',
)}
];
`;
}

/**
 * The two literals a migration pastes into `translate()`. Printed rather than
 * written, because a migration is immutable once it has shipped.
 *
 * @param {Array<{ cp: number, folded: number }>} entries
 * @returns {string}
 */
export function renderSql(entries) {
	const indent = '          ';
	return (
		`${indent}${sqlLiteral(
			entries.map((e) => e.cp),
			indent,
		)},\n${indent}${sqlLiteral(
			entries.map((e) => e.folded),
			indent,
		)}\n`
	);
}

function main() {
	const entries = buildFoldTable();
	const unicodeVersion = process.versions.unicode ?? 'unknown';

	if (process.argv.includes('--sql')) {
		process.stdout.write(renderSql(entries));
		return;
	}

	const dart = renderDart(entries, unicodeVersion);
	writeFileSync(join(REPO_ROOT, WEB_OUTPUT_PATH), renderTs(entries, unicodeVersion), 'utf8');
	writeFileSync(join(REPO_ROOT, MOBILE_OUTPUT_PATH), dart, 'utf8');
	writeFileSync(join(REPO_ROOT, IOS_OUTPUT_PATH), dart, 'utf8');
	console.log(
		`${entries.length} folded code points (${entries.filter((e) => e.cp > 0xffff).length} non-BMP), Unicode ${unicodeVersion}\n` +
			`  ${WEB_OUTPUT_PATH}\n  ${MOBILE_OUTPUT_PATH}\n  ${IOS_OUTPUT_PATH}\n` +
			`  --sql prints the literals for the migration that moves the SQL rail with them`,
	);
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) main();

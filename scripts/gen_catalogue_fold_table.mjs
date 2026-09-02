#!/usr/bin/env node
// Generates the accent-fold table the mobile catalogue browse helper folds
// search keys with, from the Unicode data the running Node already carries.
//
//   node scripts/gen_catalogue_fold_table.mjs
//
// Output (committed, never hand-edit — re-run this instead):
//   apps/mobile_android/lib/catalogue_fold_table.dart
//   (mirror it into apps/mobile_ios/lib/ — the twin invariant, decisions § 39)
//
// Why a generated table at all. `apps/web/src/lib/segments/catalogue_browse.ts`
// folds a search key by decomposing to NFD, dropping everything with the
// Unicode `Diacritic` property, lowercasing, and collapsing the Greek final
// sigma. Dart's core library has no normalisation and no `Diacritic` property,
// so the Dart twin has to carry the answer rather than compute it. It used to
// carry a HAND-WRITTEN one — 19 base letters' worth of precomposed Latin plus
// five combining-mark ranges — which stopped at Latin Extended-A and left
// 14,719 code points folding differently from web, 13,746 of them letters:
// every Vietnamese letter, all of Greek, 57 Cyrillic, the pinyin tone letters,
// 11,172 Hangul syllables and the 1,002 CJK compatibility ideographs. A reader
// typing `hai` reached `Đèo Hải Vân` on the web and not on the phone, and
// `sortCatalogue`'s by-name order — which compares folded names — disagreed
// between the two platforms. decisions § 852.
//
// The pipeline is per-code-point by construction, which is what makes a table
// a faithful port: measured over every scalar value in two neighbouring
// contexts, the ONLY code point whose fold depends on what surrounds it was
// U+03A3 (the Final_Sigma rule in `toLowerCase`), and web now collapses ς onto
// σ for that reason (decisions § 853). The one residual is canonical
// REORDERING: a string carrying two adjacent combining marks in non-canonical
// order folds through NFD's reordering on web and rune-by-rune here. Both
// orders are the same text and any normalised input (NFC or NFD) is already
// canonically ordered, so this can only be reached by a deliberately
// denormalised name.
//
// Hangul is not in the table — its canonical decomposition is arithmetic
// (UAX #15's Hangul Syllable Decomposition), so the Dart side computes it and
// this generator ASSERTS the arithmetic reproduces NFD for all 11,172
// syllables rather than trusting it.
//
// The input is the running Node's Unicode tables, so the output moves when
// Node's ICU does. `scripts/check_catalogue_fold_table.mjs` compares the
// committed file with a fresh render and names that as one of the two causes.

import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const OUTPUT_PATH = 'apps/mobile_android/lib/catalogue_fold_table.dart';

/** First and last Hangul syllable, and the jamo bases UAX #15 decomposes to. */
export const HANGUL = {
	sBase: 0xac00,
	lBase: 0x1100,
	vBase: 0x1161,
	tBase: 0x11a7,
	vCount: 21,
	tCount: 28,
	nCount: 21 * 28,
	sCount: 19 * 21 * 28,
};

/**
 * The web fold, verbatim: NFD, drop every `Diacritic`, lowercase, then collapse
 * the Greek final sigma onto the medial one. Kept identical to `fold` in
 * `apps/web/src/lib/segments/catalogue_browse.ts`; the web suite's
 * `catalogue_fold_table.test.ts` is what holds the two together, by running
 * web's own `fold` against this table.
 *
 * @param {string} value
 * @returns {string}
 */
export function webFold(value) {
	return value
		.normalize('NFD')
		.replace(/\p{Diacritic}/gu, '')
		.toLowerCase()
		.replace(/ς/g, 'σ');
}

/**
 * UAX #15 Hangul Syllable Decomposition. Returns null for a code point outside
 * the syllable block.
 *
 * @param {number} cp
 * @returns {number[] | null}
 */
export function decomposeHangul(cp) {
	const index = cp - HANGUL.sBase;
	if (index < 0 || index >= HANGUL.sCount) return null;
	const t = index % HANGUL.tCount;
	const out = [
		HANGUL.lBase + Math.floor(index / HANGUL.nCount),
		HANGUL.vBase + Math.floor((index % HANGUL.nCount) / HANGUL.tCount),
	];
	if (t !== 0) out.push(HANGUL.tBase + t);
	return out;
}

/**
 * Every code point the fold does not leave alone, excluding the Hangul
 * syllables the Dart side decomposes arithmetically.
 *
 * @returns {{ entries: Array<{ cp: number, folded: string }>, deleted: number, hangul: number }}
 */
export function buildFoldTable() {
	/** @type {Array<{ cp: number, folded: string }>} */
	const entries = [];
	let deleted = 0;
	let hangul = 0;

	for (let cp = 0; cp <= 0x10ffff; cp++) {
		if (cp >= 0xd800 && cp <= 0xdfff) continue;
		const source = String.fromCodePoint(cp);
		const folded = webFold(source);

		const jamo = decomposeHangul(cp);
		if (jamo !== null) {
			const arithmetic = String.fromCodePoint(...jamo);
			if (arithmetic !== folded) {
				throw new Error(
					`Hangul decomposition arithmetic disagrees with NFD at U+${cp.toString(16).toUpperCase()}: ` +
						`arithmetic ${JSON.stringify(arithmetic)}, fold ${JSON.stringify(folded)}. ` +
						`The Dart side computes this rather than tabling it, so the table cannot ship.`,
				);
			}
			hangul++;
			continue;
		}

		if (folded === source) continue;
		if (folded === '') deleted++;
		entries.push({ cp, folded });
	}

	return { entries, deleted, hangul };
}

/**
 * A Dart single-quoted string literal for `value`, ASCII-only: a generated
 * table full of bare combining marks and bidi letters is a file no reviewer can
 * read a diff of.
 *
 * @param {string} value
 * @returns {string}
 */
export function dartLiteral(value) {
	let out = "'";
	for (const ch of value) {
		const cp = /** @type {number} */ (ch.codePointAt(0));
		if (ch === '\\') out += '\\\\';
		else if (ch === "'") out += "\\'";
		else if (ch === '$') out += '\\$';
		else if (cp >= 0x20 && cp <= 0x7e) out += ch;
		else out += `\\u{${cp.toString(16).toUpperCase()}}`;
	}
	return `${out}'`;
}

/**
 * @param {number[]} values
 * @param {(n: number) => string} render
 * @param {number} perLine
 * @returns {string}
 */
function wrap(values, render, perLine) {
	/** @type {string[]} */
	const lines = [];
	for (let i = 0; i < values.length; i += perLine) {
		lines.push(`  ${values.slice(i, i + perLine).map(render).join(' ')}`);
	}
	return lines.join('\n');
}

/**
 * @param {ReturnType<typeof buildFoldTable>} table
 * @param {string} unicodeVersion
 * @returns {string}
 */
export function renderDart(table, unicodeVersion) {
	const { entries } = table;
	const keys = entries.map((e) => e.cp);
	const values = entries.map((e) => e.folded);

	return `// GENERATED by scripts/gen_catalogue_fold_table.mjs from Unicode ${unicodeVersion}
// — do not hand-edit; re-run the generator instead, then mirror the file into
// apps/mobile_ios/lib/ (decisions § 39). Drift is caught by
// scripts/check_catalogue_fold_table.mjs.
//
// The accent fold \`catalogue_browse.dart\` searches and sorts with, which must
// answer exactly as web's \`fold\` — NFD, drop every code point with the Unicode
// \`Diacritic\` property, lowercase, collapse the Greek final sigma. Dart's core
// library has none of those operations, so the answer is tabled rather than
// computed (decisions § 852).
//
// Letters with NO canonical decomposition are absent on purpose, and web keeps
// them too: the stroke and ligature letters (ø, đ, ħ, ł, ŧ, æ, œ, ð, þ, ß, ı)
// are base letters in their own right, and folding them would invent an
// equivalence Unicode does not have.
//
// Shape at the time of generation: ${entries.length} code points the fold
// rewrites, ${table.deleted} of them to nothing (the combining marks and the
// spacing diacritics web deletes outright). The ${table.hangul} Hangul
// syllables are NOT here: their decomposition is arithmetic,
// \`catalogue_browse.dart\` computes it, and this generator asserts the
// arithmetic reproduces NFD for every one of them.
library;

/// Unicode version of the data this table was derived from. A newer Node folds
/// more letters, and regenerating is how they arrive.
const String kCatalogueFoldUnicodeVersion = '${unicodeVersion}';

/// UAX #15 Hangul Syllable Decomposition constants. \`Ka\` (U+AC00) is the first
/// syllable; a syllable decomposes to a leading jamo, a vowel, and a trailing
/// jamo when it has one. None of the three carries a diacritic or a case, so
/// the decomposition IS the fold.
const int kHangulSyllableBase = 0x${HANGUL.sBase.toString(16).toUpperCase()};
const int kHangulLeadBase = 0x${HANGUL.lBase.toString(16).toUpperCase()};
const int kHangulVowelBase = 0x${HANGUL.vBase.toString(16).toUpperCase()};
const int kHangulTrailBase = 0x${HANGUL.tBase.toString(16).toUpperCase()};
const int kHangulTrailCount = ${HANGUL.tCount};
const int kHangulVowelTrailCount = ${HANGUL.nCount};
const int kHangulSyllableCount = ${HANGUL.sCount};

/// Code points the fold rewrites, ascending. Binary-searched, so the order is
/// load-bearing: [kCatalogueFoldValues] is indexed by the position found here.
const List<int> kCatalogueFoldKeys = <int>[
${wrap(
	keys,
	(cp) => `0x${cp.toString(16).toUpperCase().padStart(4, '0')},`,
	8,
)}
];

/// What each key folds to. An empty string means the code point is dropped.
const List<String> kCatalogueFoldValues = <String>[
${wrap(
	values.map((_, i) => i),
	(i) => `${dartLiteral(values[i])},`,
	8,
)}
];
`;
}

/** @returns {string} */
export function render() {
	const table = buildFoldTable();
	return renderDart(table, process.versions.unicode ?? 'unknown');
}

function main() {
	const table = buildFoldTable();
	const unicodeVersion = process.versions.unicode ?? 'unknown';
	writeFileSync(join(REPO_ROOT, OUTPUT_PATH), renderDart(table, unicodeVersion), 'utf8');
	console.log(
		`${OUTPUT_PATH}: ${table.entries.length} folded code points ` +
			`(${table.deleted} deleted outright) + ${table.hangul} arithmetic Hangul syllables, ` +
			`Unicode ${unicodeVersion}`,
	);
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) main();

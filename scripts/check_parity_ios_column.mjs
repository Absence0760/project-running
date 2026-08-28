#!/usr/bin/env node
// Guardrail: `docs/product/parity.md` states what an iOS cell means exactly
// once, and the whole iOS column obeys that one statement.
//
// The matrix used to define its own iOS vocabulary in three places at once —
// the banner, the column key and the intentional-asymmetries list — and the
// three disagreed about whether shipped-but-unrun Dart is `✓`, `Partial` or
// `✗`. All three readings were in live use, so a reader could not tell an
// unbuilt iOS row from an unverified one by its symbol, and the Sync-and-
// backup block sat `✗` while the same `BackupService` sat `✓` two sections up
// (decisions § 707, § 739). Prose alone had already failed at this three
// times, which is why the rule now has a machine behind it.
//
// Four rules, each the mechanical form of one sentence in the document:
//
//   1. Exactly one `<!-- parity-ios-rule -->` block. That block holds the
//      Android → iOS derivation table, which this script READS rather than
//      restates — the rule has one home, and it is the document.
//   2. No prose outside that block states a rule about an iOS cell. This is
//      the check that catches the failure that happened: a fourth statement
//      appearing somewhere else and drifting from the block.
//   3. The derivation table covers every symbol the Legend defines, and uses
//      no symbol the Legend does not.
//   4. Every row's iOS cell is the derivation of its Android cell, unless the
//      row's Notes name the obstruction as `**iOS <symbol>:** <why>`.
//
// Structural checks on the same file (7 cells per row, legal symbols,
// `Partial` carries Notes) live in `scripts/check_parity_matrix.dart` and are
// deliberately not repeated here. That guard is not a backstop for this one:
// it runs AFTER this script in the `parity-matrix` job, so a defect the two
// share is reported here first or not at all. decisions § 774.
//
// Every row this script reads comes from `scripts/markdown_lines.mjs`, which
// applies GFM's own stateful table rule. Each of the three readers below used
// to find its own rows with `line.startsWith('|')`, and GFM makes the LEADING
// pipe optional — so a row written without one was invisible to all three at
// once, and `readRows` reset its header on it, dropping the whole rest of the
// table with it. decisions § 779.
//
// Run: `node scripts/check_parity_ios_column.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml — the one job that
//      is NOT gated on `needs.changes.outputs.code`, because a parity.md edit
//      is a docs-only diff and every code-gated job skips it (and the CI gate
//      counts a skip as a pass).
// Unit tests: `node --test scripts/check_parity_ios_column.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { foldedLines, markdownTables, tableLines, unclaimedRowLines } from './markdown_lines.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const MATRIX_PATH = join(REPO_ROOT, 'docs', 'product', 'parity.md');

export const OPEN_MARKER = '<!-- parity-ios-rule -->';
export const CLOSE_MARKER = '<!-- /parity-ios-rule -->';
const PLATFORMS = ['Android', 'iOS', 'Web', 'Wear OS', 'Apple Watch'];

/** @param {string} cell */
const unquote = (cell) => cell.replace(/^`|`$/g, '').trim();

/**
 * The Legend table's symbol column, in document order. The `🔸 in Notes` row
 * documents a Notes convention rather than a cell value, so it drops out.
 *
 * @param {string} text
 * @returns {string[]}
 */
export function readLegendSymbols(text) {
	/** @type {string[]} */
	const symbols = [];
	for (const table of markdownTables(text)) {
		if (table.header.cells[0] !== 'Symbol' || table.header.cells[1] !== 'Meaning') continue;
		for (const row of table.rows) {
			if (row.cells.length === 0) continue;
			const symbol = unquote(row.cells[0]);
			if (symbol.includes(' ')) continue;
			symbols.push(symbol);
		}
	}
	return symbols;
}

/**
 * Rule 1 + the derivation table it carries.
 *
 * @param {string} text
 * @returns {{ errors: string[], block: string | null, derivation: Map<string, string> | null }}
 */
export function readRuleBlock(text) {
	/** @type {string[]} */
	const errors = [];
	const opens = text.split(OPEN_MARKER).length - 1;
	const closes = text.split(CLOSE_MARKER).length - 1;
	// `CLOSE_MARKER` contains `OPEN_MARKER`'s text apart from the slash, so the
	// counts are independent only because the slash makes them distinct strings.
	if (opens !== 1 || closes !== 1) {
		errors.push(
			`expected exactly one \`${OPEN_MARKER}\` … \`${CLOSE_MARKER}\` block, ` +
				`found ${opens} opener(s) and ${closes} closer(s). The rule for the iOS ` +
				`column has one home; a second block is a second rule.`,
		);
		return { errors, block: null, derivation: null };
	}
	const start = text.indexOf(OPEN_MARKER);
	const end = text.indexOf(CLOSE_MARKER);
	if (end < start) {
		errors.push(`\`${CLOSE_MARKER}\` appears before \`${OPEN_MARKER}\`.`);
		return { errors, block: null, derivation: null };
	}
	const block = text.slice(start, end + CLOSE_MARKER.length);

	/** @type {Map<string, string>} */
	const derivation = new Map();
	for (const table of markdownTables(block)) {
		if (table.header.cells[0] !== 'Android cell' || table.header.cells[1] !== 'iOS cell') continue;
		for (const row of table.rows) {
			if (row.cells.length < 2) {
				errors.push(
					`the derivation table has a row that opens fewer than two columns, so it ` +
						`states no mapping: ${row.text.trim().slice(0, 140)}`,
				);
				continue;
			}
			const from = unquote(row.cells[0]);
			const to = unquote(row.cells[1]);
			if (derivation.has(from)) {
				errors.push(`the derivation table maps \`${from}\` twice.`);
				continue;
			}
			derivation.set(from, to);
		}
	}
	if (derivation.size === 0) {
		errors.push(
			`the rule block carries no derivation table. It needs one with the ` +
				`header \`| Android cell | iOS cell |\` — this script reads the mapping ` +
				`from there rather than hard-coding it, so the document stays the rule.`,
		);
		return { errors, block, derivation: null };
	}
	return { errors, block, derivation };
}

/**
 * Rule 3 — the derivation speaks about exactly the vocabulary the Legend
 * defines, so a symbol cannot be introduced or retired on one side only.
 *
 * @param {string[]} legend
 * @param {Map<string, string>} derivation
 * @returns {string[]}
 */
export function checkVocabularyCoverage(legend, derivation) {
	/** @type {string[]} */
	const errors = [];
	for (const symbol of legend) {
		if (!derivation.has(symbol)) {
			errors.push(
				`the Legend defines \`${symbol}\` but the derivation table does not say ` +
					`what an Android \`${symbol}\` derives to on iOS.`,
			);
		}
	}
	for (const [from, to] of derivation) {
		if (!legend.includes(from)) {
			errors.push(`the derivation table maps \`${from}\`, which the Legend does not define.`);
		}
		if (!legend.includes(to)) {
			errors.push(`the derivation table produces \`${to}\`, which the Legend does not define.`);
		}
	}
	return errors;
}

/**
 * Rule 2 — a passage of prose that names the iOS column AND a cell symbol is
 * stating this rule somewhere it does not live. Table rows are exempt: a
 * Notes cell may carry the `**iOS <symbol>:**` marker, which rule 4 reads. The
 * exemption is by LINE, not by leading pipe — a row written without one is
 * still a row, and grading its Notes as prose accuses the document of a fourth
 * statement it never made. decisions § 779.
 *
 * The unit is a folded markdown line, not a physical one. Markdown soft-wraps
 * a paragraph freely and the wrap changes nothing about what the document
 * says, so requiring `iOS` and the symbol on the same physical line meant the
 * wrapped form of the exact sentence this rule exists to catch walked past it
 * — and parity.md already carries 5 multi-line prose blocks outside the rule
 * block, so the habit is in the document. decisions § 774.
 *
 * @param {string} text
 * @returns {string[]}
 */
export function checkSingleStatement(text) {
	/** @type {string[]} */
	const errors = [];
	const legend = readLegendSymbols(text);
	if (legend.length === 0) return errors;
	const symbolPattern = new RegExp(
		`(\`)?(${legend.map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})\\1?`,
	);
	const inTable = tableLines(text);
	let inBlock = false;
	for (const { line: lineNumber, text: line } of foldedLines(text)) {
		if (line.includes(OPEN_MARKER)) inBlock = true;
		if (line.includes(CLOSE_MARKER)) {
			inBlock = false;
			continue;
		}
		if (inBlock || inTable.has(lineNumber)) continue;
		if (!/\biOS\b/.test(line)) continue;
		const hit = line.match(symbolPattern);
		if (!hit) continue;
		errors.push(
			`docs/product/parity.md:${lineNumber} — this passage names the iOS column and the ` +
				`symbol \`${hit[2]}\`, so it states a rule about what an iOS cell means. ` +
				`That rule lives in the \`${OPEN_MARKER}\` block and nowhere else; the ` +
				`three copies that disagreed are what decisions § 739 removed. Exempting ` +
				`a line that merely LINKS to the block was tried and dropped — the ` +
				`deleted column key would have both linked to it and contradicted it. ` +
				`Say it inside the block, or write a sentence here that names no cell ` +
				`symbol. Line was: ${line.trim().slice(0, 140)}`,
		);
	}
	return errors;
}

/**
 * @typedef {{ line: number, feature: string, android: string, ios: string, notes: string }} ParityRow
 */

/**
 * Every data row of the platform tables, with its line number.
 *
 * A row whose columns do not line up with its own header is reported rather
 * than skipped: the iOS and Notes cells cannot be located in it, so every
 * verdict below would be about the wrong column. That is not the 7-cell rule —
 * a table with a different column count would still read correctly here — and
 * the failing row is named by `check_parity_matrix.dart` too, from its own
 * rule, in the same job.
 *
 * @param {string} text
 * @returns {{ rows: ParityRow[], errors: string[] }}
 */
export function readRows(text) {
	/** @type {ParityRow[]} */
	const rows = [];
	/** @type {string[]} */
	const errors = [];
	for (const table of markdownTables(text)) {
		const header = table.header.cells;
		if (!PLATFORMS.every((p) => header.includes(p))) continue;
		for (const { line, text: raw, cells } of table.rows) {
			if (cells.length !== header.length) {
				errors.push(
					`docs/product/parity.md:${line} — this row opens ${cells.length} column(s) ` +
						`where the table's header opens ${header.length}, so its iOS and Notes ` +
						`cells cannot be located and the column cannot be checked here. Row was: ` +
						`${raw.trim().slice(0, 140)}`,
				);
				continue;
			}
			rows.push({
				line,
				feature: cells[0],
				android: cells[header.indexOf('Android')],
				ios: cells[header.indexOf('iOS')],
				notes: cells[cells.length - 1],
			});
		}
	}
	for (const { line, text: raw } of unclaimedRowLines(text)) {
		errors.push(
			`docs/product/parity.md:${line} — this line opens with a pipe but belongs to no ` +
				`table, so a reader sees raw pipes in a paragraph and this guard sees no row. ` +
				`A table needs a header and a delimiter row of the SAME width, and a blank line ` +
				`inside one ends it. Row was: ${raw.trim().slice(0, 140)}`,
		);
	}
	return { rows, errors };
}

/// The one cell value a marker can never buy — see `checkColumn`.
export const UNEARNABLE = '✓';

/** @param {string} symbol */
export const markerFor = (symbol) => `**iOS ${symbol}:**`;

/**
 * Rule 4 — the column is the derivation, or the row says what obstructs it.
 *
 * @param {ParityRow[]} rows
 * @param {Map<string, string>} derivation
 * @returns {{ errors: string[], marked: string[] }}
 */
export function checkColumn(rows, derivation) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const marked = [];
	for (const row of rows) {
		const expected = derivation.get(row.android);
		if (expected === undefined) {
			errors.push(
				`docs/product/parity.md:${row.line} — [${row.feature}] Android cell ` +
					`\`${row.android}\` has no entry in the derivation table, so this row's ` +
					`iOS cell cannot be checked.`,
			);
			continue;
		}
		if (row.ios === expected) {
			const stale = markerFor(row.ios);
			if (row.notes.includes(stale)) {
				errors.push(
					`docs/product/parity.md:${row.line} — [${row.feature}] carries a ` +
						`\`${stale}\` marker on a cell that is just the derivation of Android ` +
						`\`${row.android}\`. The marker is for a DEPARTURE; here it restates ` +
						`the rule per row, which is the habit § 739 removed. Delete it.`,
				);
			}
			continue;
		}
		if (row.ios === UNEARNABLE) {
			errors.push(
				`docs/product/parity.md:${row.line} — [${row.feature}] iOS is ` +
					`\`${UNEARNABLE}\`, which asserts someone ran this row on a Mac build, ` +
					`simulator or device. Nothing in this matrix has been. No Notes marker ` +
					`can grant it either — when the device run lands, the derivation table ` +
					`in the rule block is the ONE line that changes, and the column is swept ` +
					`again in one pass. Until then this cell is \`${expected}\`.`,
			);
			continue;
		}
		if (row.notes.includes(markerFor(row.ios))) {
			marked.push(`${row.feature} — iOS \`${row.ios}\` (derivation says \`${expected}\`)`);
			continue;
		}
		errors.push(
			`docs/product/parity.md:${row.line} — [${row.feature}] iOS is \`${row.ios}\` ` +
				`but Android is \`${row.android}\`, which the derivation table reads as ` +
				`\`${expected}\`. The Dart is byte-identical (decisions § 39), so a departure ` +
				`has to name what obstructs iOS — a \`Platform\` gate, a method channel with ` +
				`no iOS handler, a plugin that does not declare iOS, or a missing ` +
				`\`Info.plist\` key or entitlement. Either set the cell to \`${expected}\`, or ` +
				`add \`${markerFor(row.ios)} <why>\` to the row's Notes.`,
		);
	}
	return { errors, marked };
}

/**
 * @param {string} text
 * @returns {{ errors: string[], rows: number, marked: string[] }}
 */
export function audit(text) {
	/** @type {string[]} */
	const errors = [];
	const legend = readLegendSymbols(text);
	if (legend.length === 0) {
		errors.push('no Legend table found — expected a `| Symbol | Meaning |` table.');
	}
	const { errors: blockErrors, derivation } = readRuleBlock(text);
	errors.push(...blockErrors);
	errors.push(...checkSingleStatement(text));
	const { rows, errors: rowErrors } = readRows(text);
	errors.push(...rowErrors);
	if (rows.length === 0) errors.push('no platform-table rows parsed — did the table format change?');
	/** @type {string[]} */
	let marked = [];
	if (derivation) {
		errors.push(...checkVocabularyCoverage(legend, derivation));
		const column = checkColumn(rows, derivation);
		errors.push(...column.errors);
		marked = column.marked;
	}
	return { errors, rows: rows.length, marked };
}

if (import.meta.url === `file://${process.argv[1]}`) {
	const path = process.argv[2] ?? MATRIX_PATH;
	const { errors, rows, marked } = audit(readFileSync(path, 'utf8'));
	if (errors.length > 0) {
		console.error(`check_parity_ios_column: ${errors.length} issue(s) across ${rows} rows.\n`);
		for (const e of errors) console.error(`  ${e}`);
		process.exit(1);
	}
	console.log(`check_parity_ios_column: ${rows} rows, iOS column matches the derivation.`);
	if (marked.length > 0) {
		console.log(`${marked.length} marked departure(s):`);
		for (const m of marked) console.log(`  ${m}`);
	}
}

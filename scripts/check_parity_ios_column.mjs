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
// deliberately not repeated here.
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

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const MATRIX_PATH = join(REPO_ROOT, 'docs', 'product', 'parity.md');

export const OPEN_MARKER = '<!-- parity-ios-rule -->';
export const CLOSE_MARKER = '<!-- /parity-ios-rule -->';
const PLATFORMS = ['Android', 'iOS', 'Web', 'Wear OS', 'Apple Watch'];

// A markdown cell may carry a literal pipe as `\|`, which does not open a
// column. Park those before splitting, restore them after.
const PIPE = '\u0000';

export function splitRow(line) {
	return line
		.replaceAll('\\|', PIPE)
		.split('|')
		.slice(1, -1)
		.map((cell) => cell.replaceAll(PIPE, '\\|').trim());
}

const unquote = (cell) => cell.replace(/^`|`$/g, '').trim();

/// The Legend table's symbol column, in document order. The `🔸 in Notes` row
/// documents a Notes convention rather than a cell value, so it drops out.
export function readLegendSymbols(text) {
	const symbols = [];
	let inLegend = false;
	for (const line of text.split('\n')) {
		if (!line.startsWith('|')) {
			inLegend = false;
			continue;
		}
		const cells = splitRow(line);
		if (cells[0] === 'Symbol' && cells[1] === 'Meaning') {
			inLegend = true;
			continue;
		}
		if (!inLegend || /^:?-+:?$/.test(cells[0])) continue;
		const symbol = unquote(cells[0]);
		if (symbol.includes(' ')) continue;
		symbols.push(symbol);
	}
	return symbols;
}

/// Rule 1 + the derivation table it carries.
export function readRuleBlock(text) {
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

	const derivation = new Map();
	let inTable = false;
	for (const line of block.split('\n')) {
		if (!line.startsWith('|')) {
			inTable = false;
			continue;
		}
		const cells = splitRow(line);
		if (cells[0] === 'Android cell' && cells[1] === 'iOS cell') {
			inTable = true;
			continue;
		}
		if (!inTable || /^:?-+:?$/.test(cells[0])) continue;
		const from = unquote(cells[0]);
		const to = unquote(cells[1]);
		if (derivation.has(from)) {
			errors.push(`the derivation table maps \`${from}\` twice.`);
			continue;
		}
		derivation.set(from, to);
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

/// Rule 3 — the derivation speaks about exactly the vocabulary the Legend
/// defines, so a symbol cannot be introduced or retired on one side only.
export function checkVocabularyCoverage(legend, derivation) {
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

/// Rule 2 — a line of prose that names the iOS column AND a cell symbol is
/// stating this rule somewhere it does not live. Table rows are exempt: a
/// Notes cell may carry the `**iOS <symbol>:**` marker, which rule 4 reads.
export function checkSingleStatement(text) {
	const errors = [];
	const legend = readLegendSymbols(text);
	if (legend.length === 0) return errors;
	const symbolPattern = new RegExp(
		`(\`)?(${legend.map((s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})\\1?`,
	);
	const lines = text.split('\n');
	let inBlock = false;
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (line.includes(OPEN_MARKER)) inBlock = true;
		if (line.includes(CLOSE_MARKER)) {
			inBlock = false;
			continue;
		}
		if (inBlock || line.startsWith('|')) continue;
		if (!/\biOS\b/.test(line)) continue;
		const hit = line.match(symbolPattern);
		if (!hit) continue;
		errors.push(
			`docs/product/parity.md:${i + 1} — this line names the iOS column and the ` +
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

/// Every data row of the platform tables, with its line number.
export function readRows(text) {
	const lines = text.split('\n');
	const rows = [];
	let header = null;
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (!line.startsWith('|')) {
			header = null;
			continue;
		}
		const cells = splitRow(line);
		if (PLATFORMS.every((p) => cells.includes(p))) {
			header = cells;
			continue;
		}
		if (!header || /^:?-+:?$/.test(cells[0])) continue;
		rows.push({
			line: i + 1,
			feature: cells[0],
			android: cells[header.indexOf('Android')],
			ios: cells[header.indexOf('iOS')],
			notes: cells[cells.length - 1],
		});
	}
	return rows;
}

/// The one cell value a marker can never buy — see `checkColumn`.
export const UNEARNABLE = '✓';

export const markerFor = (symbol) => `**iOS ${symbol}:**`;

/// Rule 4 — the column is the derivation, or the row says what obstructs it.
export function checkColumn(rows, derivation) {
	const errors = [];
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

export function audit(text) {
	const errors = [];
	const legend = readLegendSymbols(text);
	if (legend.length === 0) {
		errors.push('no Legend table found — expected a `| Symbol | Meaning |` table.');
	}
	const { errors: blockErrors, derivation } = readRuleBlock(text);
	errors.push(...blockErrors);
	errors.push(...checkSingleStatement(text));
	const rows = readRows(text);
	if (rows.length === 0) errors.push('no platform-table rows parsed — did the table format change?');
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

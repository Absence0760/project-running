// The two structural questions this repo's registry guards ask of a committed
// Markdown file: where does one line end, and which lines are rows of a table.
// Both have a GFM answer, both were re-derived per guard as a regex, and both
// regexes read the document differently from the renderer a human is looking
// at.
//
// Why this exists as a module rather than as a regex inside each guard. Two
// registry guards read prose out of committed Markdown, and both graded one
// PHYSICAL line at a time — so a soft wrap, which changes nothing about what
// the document says, silently changed what they enforced.
// `check_parity_pair_registry.mjs` sliced the parity-pair bullet at its first
// newline: measured on the committed 71,208-character bullet, one wrap at the
// `gym_prs` entry hid 86 of its 99 pairs, and a pair appended on a
// continuation line was invisible with nothing reported.
// `check_parity_ios_column.mjs`'s rule 2 needed `iOS` and a cell symbol on the
// same line, so the wrapped form of the sentence it exists to catch walked
// past it — and `docs/product/parity.md` already carries 5 multi-line prose
// blocks outside the rule block, so the habit is in the document.
// decisions § 774.
//
// The table half arrived the same way and for the same reason. GFM makes the
// LEADING pipe optional exactly as it makes the trailing one optional, and a
// row written without it renders as an ordinary row — measured against
// `marked`, the `<tr>` is indistinguishable from its neighbours. Every reader
// of `docs/product/parity.md` detected a row as `line.startsWith('|')`, so such
// a row was not misgraded by one guard, it was invisible to all of them: no
// 7-cell check, no legal-symbol check, no iOS-derivation check. Worse in the
// iOS guard, whose row walk reset its header on any non-pipe line — one such
// row silently dropped the whole remainder of its table (measured: 337 rows to
// 329, still exit 0). GFM's own rule is stateful and this module implements it:
// a table opens on a header plus a delimiter row of matching width, and every
// line after it is a row until a blank line or another block. decisions § 779.
//
// Unit tests: `node --test scripts/markdown_lines.test.mjs`

/// A line that opens a new markdown block rather than continuing the previous
/// one: a list item, ordered item, heading, table row, quote, fence or HTML
/// comment.
const BLOCK_START = /^\s*(?:[-*+] |\d+[.)] |#{1,6} |>|\||```|~~~|<!--)/;

/// A markdown cell may carry a literal pipe as `\|`, which does not open a
/// column. Park those before splitting, restore them after.
const PARKED_PIPE = '\u0000';

const DELIMITER_CELL = /^:?-+:?$/;

/**
 * @typedef {{ line: number, text: string }} FoldedLine
 */

/**
 * @typedef {{ line: number, text: string, cells: string[] }} TableRow
 */

/**
 * @typedef {{ header: TableRow, delimiter: TableRow, rows: TableRow[] }} MarkdownTable
 */

/**
 * One table row's cells.
 *
 * GFM makes the leading and trailing pipes optional, so the empty ends are
 * dropped only where a pipe actually produced one. A flat `slice(1, -1)` ate
 * the LAST CELL of a row written without its trailing pipe — which in
 * `parity.md` is the Notes column, so the iOS guard read the Apple Watch cell
 * as the notes and demanded a marker that was already there. decisions § 774.
 *
 * @param {string} line
 * @returns {string[]}
 */
export function splitRow(line) {
	const parked = line.replaceAll('\\|', PARKED_PIPE).trim();
	const cells = parked.split('|');
	if (parked.startsWith('|')) cells.shift();
	if (parked.endsWith('|')) cells.pop();
	return cells.map((cell) => cell.replaceAll(PARKED_PIPE, '\\|').trim());
}

/**
 * @param {string} line
 * @returns {boolean}
 */
function isDelimiter(line) {
	if (!line.includes('|')) return false;
	const cells = splitRow(line);
	return cells.length > 0 && cells.every((cell) => DELIMITER_CELL.test(cell));
}

/**
 * Every GFM table in the document, each with the rows a renderer draws under
 * it.
 *
 * The width match between header and delimiter is GFM's own opening condition,
 * not a nicety: a delimiter of a different width means no table at all, and the
 * block renders as a paragraph of raw pipes. Two committed docs outside this
 * module's readers are in that state today, which is why a caller that must not
 * lose a table checks that every pipe-leading line landed in one.
 *
 * @param {string} text
 * @returns {MarkdownTable[]}
 */
export function markdownTables(text) {
	const lines = text.split('\n');
	/** @type {MarkdownTable[]} */
	const tables = [];
	/** @type {MarkdownTable | null} */
	let open = null;
	/** @type {string | null} */
	let fence = null;

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const edge = line.match(/^\s*(`{3,}|~{3,})/);
		if (edge) {
			const glyph = edge[1][0];
			if (fence === null) fence = glyph;
			else if (fence === glyph) fence = null;
			open = null;
			continue;
		}
		if (fence !== null) continue;

		if (open !== null) {
			// A table is broken by a blank line or the start of another block —
			// but not by a row, which is what a leading pipe makes the line look
			// like to `BLOCK_START`.
			if (line.trim() !== '' && (!BLOCK_START.test(line) || line.trimStart().startsWith('|'))) {
				open.rows.push({ line: i + 1, text: line, cells: splitRow(line) });
				continue;
			}
			open = null;
		}

		const next = lines[i + 1];
		if (line.trim() === '' || !line.includes('|') || next === undefined || !isDelimiter(next)) {
			continue;
		}
		const header = splitRow(line);
		if (header.length !== splitRow(next).length) continue;
		open = {
			header: { line: i + 1, text: line, cells: header },
			delimiter: { line: i + 2, text: next, cells: splitRow(next) },
			rows: [],
		};
		tables.push(open);
		i++;
	}
	return tables;
}

/**
 * The 1-based numbers of every line a table occupies — header, delimiter and
 * rows. A folded line must not swallow one: a row is its own row however it is
 * written, and gluing it to the row above deletes it.
 *
 * @param {string} text
 * @returns {Set<number>}
 */
export function tableLines(text) {
	/** @type {Set<number>} */
	const numbers = new Set();
	for (const table of markdownTables(text)) {
		numbers.add(table.header.line);
		numbers.add(table.delimiter.line);
		for (const row of table.rows) numbers.add(row.line);
	}
	return numbers;
}

/**
 * The document's lines with soft wraps folded back, each carrying the 1-based
 * number of the line it STARTS on — a guard that names a line has to name the
 * one a reader would open the file to.
 *
 * @param {string} text
 * @returns {FoldedLine[]}
 */
export function foldedLines(text) {
	const inTable = tableLines(text);
	/** @type {FoldedLine[]} */
	const out = [];
	text.split('\n').forEach((line, index) => {
		const previous = out.at(-1);
		if (
			previous !== undefined &&
			previous.text.trim() !== '' &&
			line.trim() !== '' &&
			!inTable.has(index + 1) &&
			!BLOCK_START.test(line)
		) {
			previous.text = `${previous.text} ${line.trim()}`;
			return;
		}
		out.push({ line: index + 1, text: line });
	});
	return out;
}

/**
 * @param {string} text
 * @returns {string}
 */
export function foldSoftWraps(text) {
	return foldedLines(text)
		.map((l) => l.text)
		.join('\n');
}

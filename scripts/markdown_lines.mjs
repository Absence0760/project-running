// Markdown's lazy continuation, applied: a line that neither is blank nor
// opens a new block belongs to the line above it, and the renderer shows the
// two as one sentence.
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
// Unit tests: `node --test scripts/markdown_lines.test.mjs`

/// A line that opens a new markdown block rather than continuing the previous
/// one: a list item, ordered item, heading, table row, quote, fence or HTML
/// comment.
const BLOCK_START = /^\s*(?:[-*+] |\d+[.)] |#{1,6} |>|\||```|~~~|<!--)/;

/**
 * @typedef {{ line: number, text: string }} FoldedLine
 */

/**
 * The document's lines with soft wraps folded back, each carrying the 1-based
 * number of the line it STARTS on — a guard that names a line has to name the
 * one a reader would open the file to.
 *
 * @param {string} text
 * @returns {FoldedLine[]}
 */
export function foldedLines(text) {
	/** @type {FoldedLine[]} */
	const out = [];
	text.split('\n').forEach((line, index) => {
		const previous = out.at(-1);
		if (
			previous !== undefined &&
			previous.text.trim() !== '' &&
			line.trim() !== '' &&
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

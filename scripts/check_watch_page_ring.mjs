#!/usr/bin/env node
// Guardrail: the page-cycle diagram in `docs/custom_watch/navigation.md` is the
// firmware's own `Page::next()` chain, edge for edge, by reading both.
//
// Why this exists: decisions.md § 793. The § 793 doc sweep found the diagram
// missing `BARO` — the § 376 storm-watch page — while the prose above it called
// the closing run a trio when the firmware walks four. That is not a cosmetic
// omission. The `Page` declaration order IS the bit order of the 64-bit
// `SET1` pages mask the phone pushes (`watch_settings.dart`'s `pages` field), so
// a reader deriving bit positions by counting round the drawn ring gets every
// page after the gap off by one, and hides a page the runner asked to see.
//
// The diagram is a mermaid flowchart with subgraphs and cluster edges, not a
// single line, so it is compared as a SET OF EDGES rather than as an order:
// every `A --> B` the firmware declares must be drawn, and every edge drawn
// must be one the firmware declares. Both directions matter — an omitted edge
// is the § 376 defect, and an invented one is a page cycle the wrist does not
// have. As of § 793 the two agree exactly: 45 edges, no extras.
//
// Node coverage falls out of the edge comparison and is checked anyway, because
// a page whose `next()` arm was never added would be absent from both rails and
// agree with itself.
//
// Run: `node scripts/check_watch_page_ring.mjs`
// CI:  the `watch-wire-vectors` job in .github/workflows/ci.yml, which is in
//      the `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_watch_page_ring.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripComments } from './comment_strip.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at
// mutated copies, which is how a guard is shown to fail.
export const PAGE_FILE =
	process.env.WATCH_PAGE_RS ?? join(REPO_ROOT, 'apps/custom_watch/core/src/page.rs');
export const NAV_FILE =
	process.env.WATCH_NAV_MD ?? join(REPO_ROOT, 'docs/custom_watch/navigation.md');

// The anchor that picks the page-cycle flowchart out of a file with several
// mermaid blocks. It is an edge the ring has carried since the summaries
// cluster existed; if it ever moves, this guard fails loudly rather than
// silently reading some other diagram.
export const RING_ANCHOR = 'RCAP --> STRK';

// mermaid's own tokens, which are not page codes.
const NOT_A_PAGE = new Set(['LR', 'TB', 'RL', 'BT', 'TD']);

/**
 * `Page::<Variant> => "CODE"` inside `fn code`, which is the panel label and
 * the identifier the diagram draws.
 * @param {string} src
 * @returns {Map<string, string>} variant -> code
 */
export function parsePageCodes(src) {
	const code = stripComments(src, 'rust');
	const at = code.search(/\bfn\s+code\s*\(/);
	if (at === -1) throw new Error('check_watch_page_ring: no `fn code` in page.rs');
	const body = code.slice(at, endOfArmBlock(code, at));
	const out = new Map();
	for (const m of body.matchAll(/Page::(\w+)\s*=>\s*"([A-Z0-9]{1,5})"/g)) {
		out.set(m[1], m[2]);
	}
	if (out.size === 0) throw new Error('check_watch_page_ring: `fn code` parsed empty');
	return out;
}

/**
 * `Page::<From> => Page::<To>` inside `fn next`, the cycle itself.
 * @param {string} src
 * @returns {Array<[string, string]>}
 */
export function parsePageNext(src) {
	const code = stripComments(src, 'rust');
	const at = code.search(/\bfn\s+next\s*\(/);
	if (at === -1) throw new Error('check_watch_page_ring: no `fn next` in page.rs');
	const body = code.slice(at, endOfArmBlock(code, at));
	const out = /** @type {Array<[string, string]>} */ ([]);
	for (const m of body.matchAll(/Page::(\w+)\s*=>\s*Page::(\w+)/g)) {
		out.push([m[1], m[2]]);
	}
	if (out.length === 0) throw new Error('check_watch_page_ring: `fn next` parsed empty');
	return out;
}

/**
 * The end of the `match` arms a `fn` opens — its outermost block.
 * @param {string} code comment-stripped rust
 * @param {number} from
 * @returns {number}
 */
function endOfArmBlock(code, from) {
	let i = code.indexOf('{', from);
	if (i === -1) throw new Error('check_watch_page_ring: no body after the fn');
	let depth = 0;
	while (i < code.length) {
		const c = code[i];
		if (c === '"') {
			i = endOfString(code, i);
			continue;
		}
		if (c === '{') depth++;
		else if (c === '}') {
			depth--;
			if (depth === 0) return i + 1;
		}
		i++;
	}
	throw new Error('check_watch_page_ring: unterminated fn body');
}

/** @param {string} code @param {number} at @returns {number} */
function endOfString(code, at) {
	let i = at + 1;
	while (i < code.length) {
		if (code[i] === '\\') {
			i += 2;
			continue;
		}
		if (code[i] === '"') return i + 1;
		i++;
	}
	throw new Error('check_watch_page_ring: unterminated string');
}

/**
 * Every `A --> B` in the page-cycle flowchart. A mermaid line may chain
 * (`A --> B --> C`), which is three nodes and two edges.
 * @param {string} md
 * @returns {Set<string>} "FROM>TO"
 */
export function parseRingEdges(md) {
	const at = md.indexOf(RING_ANCHOR);
	if (at === -1) {
		throw new Error(
			`check_watch_page_ring: the "${RING_ANCHOR}" anchor is gone from ` +
				'navigation.md, so this guard cannot tell which mermaid block is the ' +
				'page ring. Restore it or teach the parser the new anchor — a diagram ' +
				'nothing parses is a diagram nothing checks.',
		);
	}
	const start = md.lastIndexOf('```mermaid', at);
	const end = md.indexOf('```', at);
	if (start === -1 || end === -1) {
		throw new Error('check_watch_page_ring: the ring anchor is not inside a mermaid block');
	}
	/** @type {Set<string>} */
	const edges = new Set();
	for (const line of md.slice(start, end).split('\n')) {
		// `%%` opens a mermaid comment; a node named inside one is not drawn.
		if (line.trim().startsWith('%%')) continue;
		// codeql[js/bad-tag-filter]
		//
		// That marker does NOT suppress on its own — the alert is dismissed
		// through the code-scanning API, and this comment is here so the
		// reasoning travels with the code. CodeQL reads a `-->` literal as an
		// HTML-comment terminator and asks why `--!>` is not also matched.
		// Nothing here parses HTML: `-->` is mermaid's edge arrow, and the
		// input is a repo-committed `.md` diagram, not untrusted markup. A
		// pattern widened to `--!>` would split on a sequence mermaid never
		// emits.
		const nodes = line
			.trim()
			.split(/\s*-->\s*/)
			.filter((t) => /^[A-Z][A-Z0-9]{0,4}$/.test(t) && !NOT_A_PAGE.has(t));
		for (let i = 0; i + 1 < nodes.length; i++) edges.add(`${nodes[i]}>${nodes[i + 1]}`);
	}
	return edges;
}

/**
 * @param {string} pageSrc
 * @param {string} navMd
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(pageSrc, navMd) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	const codes = parsePageCodes(pageSrc);
	const next = parsePageNext(pageSrc);
	const drawn = parseRingEdges(navMd);

	/** @type {Set<string>} */
	const declared = new Set();
	for (const [from, to] of next) {
		const a = codes.get(from);
		const b = codes.get(to);
		if (a === undefined || b === undefined) {
			errors.push(
				`page.rs declares Page::${from} => Page::${to} in \`next\`, but ` +
					`${a === undefined ? from : to} has no \`code\` arm, so the ring cannot name it.`,
			);
			continue;
		}
		declared.add(`${a}>${b}`);
	}

	for (const edge of declared) {
		if (drawn.has(edge)) continue;
		const [a, b] = edge.split('>');
		errors.push(
			`navigation.md never draws ${a} --> ${b}, which page.rs's \`next\` declares. ` +
				'The declaration order is the bit order of the SET1 pages mask, so a ' +
				'reader counting round the drawn ring gets every page after the gap ' +
				'off by one.',
		);
	}
	for (const edge of drawn) {
		if (declared.has(edge)) continue;
		const [a, b] = edge.split('>');
		errors.push(
			`navigation.md draws ${a} --> ${b}, which is not a step page.rs's \`next\` ` +
				'takes. The wrist does not have that edge.',
		);
	}
	if (errors.length === 0) {
		ok.push(
			`the page ring agrees edge for edge: ${declared.size} edge(s) over ${codes.size} page(s)`,
		);
	}
	return { errors, ok };
}

const invokedDirectly =
	process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
	const { errors, ok } = check(
		readFileSync(PAGE_FILE, 'utf-8'),
		readFileSync(NAV_FILE, 'utf-8'),
	);
	for (const line of ok) console.log(`[OK] check_watch_page_ring: ${line}`);
	for (const line of errors) console.error(`::error::check_watch_page_ring: ${line}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_watch_page_ring: ${errors.length} disagreement(s) between page.rs and navigation.md. ` +
				'page.rs is the source of truth for its own cycle.',
		);
		process.exit(1);
	}
}

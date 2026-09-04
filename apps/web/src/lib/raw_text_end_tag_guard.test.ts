import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

import { stripComments } from './core/strip_comments';

/**
 * Guard-rail: an HTML end tag written into a regex must be spelled the way a
 * parser closes one -- `</name` followed by whitespace, `/` or `>`, then junk
 * up to the first `>`. `<\/name>` and `<\/name\s*>` are both wrong
 * (CodeQL js/bad-tag-filter), because `</script bar>` and `</script/>` close
 * the block in every browser and neither spelling sees them.
 *
 * The cost is not a missed strip. A stale `<script type="application/ld+json">`
 * block spelled `</script >` in the SPA shell made the share Lambdas' lazy
 * `[\s\S]*?` body run on to the NEXT `</script>` in the document -- the app
 * bundle's -- deleting `</head>`, the mount div and the bundle tag with it;
 * the splice that follows then found no `</head>` and returned the wreckage
 * with none of the per-entity meta the Lambda exists to add. Measured before
 * the fix (decisions § 1086).
 *
 * Scoped to the raw-text / RCDATA elements plus `head`, which is where the
 * damage lands: those bodies are matched lazily across the document, and
 * `</head>` is a splice point whose loss drops the whole injection. XML end
 * tags (`</trkpt>`, `</urlset>`) are deliberately out of scope -- XML's own
 * grammar allows only optional whitespace there, which `<\/name\s*>` states
 * exactly, and those regexes assert against our own generated documents.
 *
 * Test files are scanned too: two of the five instances this closed were in
 * guards, where an unseen `</script >` makes the guard scan markup it thinks
 * is code and under-enforce in silence.
 *
 * Invocation:
 *   npx tsx --test src/lib/raw_text_end_tag_guard.test.ts
 */

const libRoot = import.meta.dirname;
const webRoot = resolve(libRoot, '..', '..');
const srcRoot = resolve(webRoot, 'src');
const lambdaRoot = resolve(webRoot, 'lambda');

/// HTML elements whose end tag must be matched by the parser rule. The first
/// six hold raw text or RCDATA -- their content is scanned to the end tag, so
/// a missed close runs the match on into the rest of the document. `head` is
/// here for the other reason: every share shell locates its splice point with
/// `search(/<\/head.../)`, and a miss there is a page served with no meta.
const TAGS = ['script', 'style', 'title', 'textarea', 'iframe', 'noscript', 'head'] as const;

/// The parser rule, as it must appear immediately after `<\/name` in a regex
/// literal. Written as characters rather than as a regex so the guard cannot
/// accidentally accept a near-miss.
const PARSER_RULE = '(?=[\\s/>])[^>]*>';

/// Deliberate intolerant spellings, `path relative to apps/web` -> reason.
/// A declared exemption that no longer occurs fails as loudly as an
/// undeclared instance, so an entry cannot outlive its reason.
const EXEMPT: Record<string, string> = {};

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === 'dist' || entry.name === '.svelte-kit') {
				continue;
			}
			sourceFiles(full, out);
			continue;
		}
		if (!/\.(ts|svelte|mjs|js)$/.test(entry.name)) continue;
		out.push(full);
	}
	return out;
}

interface Occurrence {
	file: string;
	line: number;
	tag: string;
	ok: boolean;
}

/// `<\/` -- the escaped-slash spelling a regex literal must use -- followed by
/// one of the guarded tag names. A template literal writing `</script>` into
/// HTML carries no backslash, so only regex literals are read here.
const END_TAG = new RegExp(`<\\\\/(${TAGS.join('|')})`, 'gi');

function scan(): Occurrence[] {
	const found: Occurrence[] = [];
	for (const file of [...sourceFiles(srcRoot), ...sourceFiles(lambdaRoot)]) {
		const source = stripComments(readFileSync(file, 'utf-8'));
		for (const m of source.matchAll(END_TAG)) {
			const after = source.slice(m.index + m[0].length);
			found.push({
				file: relative(webRoot, file).split('\\').join('/'),
				line: source.slice(0, m.index).split('\n').length,
				tag: m[1].toLowerCase(),
				ok: after.startsWith(PARSER_RULE),
			});
		}
	}
	return found;
}

test('every raw-text / head end tag in a regex states the parser rule', () => {
	const found = scan();
	// Assert the population first: a scan that has stopped matching anything
	// satisfies the violation assertion below without reading a line.
	//
	// The floor moved 18 -> 14 when § 1114 collapsed the four SPA-shell head
	// injectors onto one strip pipeline: three of these regexes existed in
	// triplicate, which is exactly the duplication § 1086 had to fix the same
	// bug in three times. A population falling because copies were removed is
	// the intended outcome; this floor exists to catch a scan that has stopped
	// matching, not to require the tree keep a particular number of copies.
	assert.ok(
		found.length >= 14,
		`expected the web tree to still carry the known raw-text end-tag regexes, found ${found.length}`,
	);
	const bad = found
		.filter((o) => !o.ok && EXEMPT[o.file] === undefined)
		.map((o) => `${o.file}:${o.line} </${o.tag}`);
	assert.deepEqual(
		bad,
		[],
		'these end-tag regexes do not close the way a parser does; write ' +
			`<\\/name${PARSER_RULE} (js/bad-tag-filter):\n  ${bad.join('\n  ')}`,
	);
});

test('every declared exemption still names an intolerant spelling', () => {
	const found = scan();
	for (const [file, reason] of Object.entries(EXEMPT)) {
		assert.ok(
			found.some((o) => o.file === file && !o.ok),
			`${file} is exempted ("${reason}") but no longer carries an intolerant end-tag regex — drop the entry`,
		);
	}
});

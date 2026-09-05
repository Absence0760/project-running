// Unit tests for scripts/check_doc_links.mjs.
//
// The slug cases are not invented: each is a heading that lives in this repo,
// and the two starred ones are the ones an INDEPENDENT measurement had already
// written down as GitHub's real answer before this guard existed — `## The
// erase (§ 378)` slugging with two hyphens, and `## 33. Privacy zones live in
// user_settings...` keeping its underscore. A slugger that gets either wrong
// reports a clean tree as broken, which is how the first attempt at this
// measurement produced 30 false positives.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	adviseFragment,
	blankCode,
	check,
	headingSlugs,
	htmlAnchors,
	isRepoRelative,
	linksIn,
	slugFor,
	stripInlineMarkup,
} from './check_doc_links.mjs';

/** @param {string} heading @returns {string} */
const slugOf = (heading) => slugFor(stripInlineMarkup(heading));

test('slugFor emits one hyphen per space, so deleted punctuation leaves its spaces behind', () => {
	// The heading `docs/custom_watch/privacy.md` actually carries. `(`, `§` and
	// `)` are deleted; the two spaces that flanked `§` become two hyphens.
	assert.equal(slugOf('The erase (§ 378)'), 'the-erase--378');
	assert.equal(slugOf('Swift / SwiftUI, Wear OS'), 'swift--swiftui-wear-os');
	assert.equal(slugOf('two windows — and a throttle'), 'two-windows--and-a-throttle');
});

test('slugFor keeps an intraword underscore', () => {
	assert.equal(
		slugOf('39. mobile_android and mobile_ios share a byte-for-byte Dart codebase'),
		'39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase',
	);
	assert.equal(
		slugOf('33. Privacy zones live in user_settings; clipping is client-side'),
		'33-privacy-zones-live-in-user_settings-clipping-is-client-side',
	);
});

test('slugFor deletes non-ASCII punctuation but keeps a letter with a diacritic', () => {
	assert.equal(slugOf('TS↔Dart parity'), 'tsdart-parity');
	assert.equal(slugOf('Zürich, CH — Déjà vu'), 'zürich-ch--déjà-vu');
	// A non-breaking space is deleted like any other non-kept character; it does
	// NOT become a hyphen.
	assert.equal(slugOf('a b'), 'ab');
});

test('slugFor lowercases without trimming, so a trailing space is a trailing hyphen', () => {
	assert.equal(slugFor('Trailing '), 'trailing-');
});

test('stripInlineMarkup drops markup, keeps the text it wrapped', () => {
	assert.equal(stripInlineMarkup('A `code` and **bold** and _em_ and [link](x)'), 'A code and bold and em and link');
	assert.equal(stripInlineMarkup('`next_instance_start` is nullable'), 'next_instance_start is nullable');
});

test('headingSlugs suffixes a repeat the way GitHub does', () => {
	const slugs = headingSlugs('# Same\n\n## Same\n\n### Same\n');
	assert.deepEqual([...slugs], ['same', 'same-1', 'same-2']);
});

test('headingSlugs ignores a hash inside a fenced block', () => {
	const slugs = headingSlugs('# Real\n\n```\n# Not a heading\n```\n\n~~~\n## Nor this\n~~~\n');
	assert.deepEqual([...slugs], ['real']);
});

test('blankCode blanks a fenced block and an inline span, preserving offsets', () => {
	const md = 'a [x](./real.md) b\n```\n[y](./gone.md)\n```\n`[z](./gone.md)` end\n';
	const out = blankCode(md);
	assert.equal(out.length, md.length);
	assert.deepEqual(
		linksIn(md).map((l) => l.target),
		['./real.md'],
	);
});

test('linksIn reads inline links, reference definitions and angle-bracket targets', () => {
	const md = '[a](./one.md)\n[b](<./two three.md>)\n[c]: ./three.md\n[d](./four.md "Title")\n';
	assert.deepEqual(
		linksIn(md).map((l) => l.target),
		['./one.md', './two three.md', './four.md', './three.md'],
	);
});

test('linksIn reports the 1-based line of each link', () => {
	const md = 'one\ntwo [a](./x.md)\n\nfour [b](./y.md)\n';
	assert.deepEqual(linksIn(md), [
		{ target: './x.md', line: 2 },
		{ target: './y.md', line: 4 },
	]);
});

test('isRepoRelative refuses a URL, a protocol-relative host and a site-absolute route', () => {
	assert.equal(isRepoRelative('./a.md'), true);
	assert.equal(isRepoRelative('#frag'), true);
	assert.equal(isRepoRelative('https://example.com'), false);
	assert.equal(isRepoRelative('mailto:a@b.c'), false);
	assert.equal(isRepoRelative('//cdn.example.com/x'), false);
	assert.equal(isRepoRelative('/learn/pacing'), false);
});

test('htmlAnchors reads an explicit id or name', () => {
	assert.deepEqual([...htmlAnchors('<a id="alpha"></a>\n<a name="beta"></a>\n')], ['alpha', 'beta']);
});

// ---------------------------------------------------------------------------
// check()
// ---------------------------------------------------------------------------

/**
 * @param {Record<string, string>} files
 * @returns {{ files: string[], read: (p: string) => string, exists: (p: string) => boolean }}
 */
function tree(files) {
	return {
		files: Object.keys(files).filter((f) => f.endsWith('.md')),
		read: (p) => {
			const hit = files[p];
			if (hit === undefined) throw new Error(`no such fixture file: ${p}`);
			return hit;
		},
		exists: (p) => Object.prototype.hasOwnProperty.call(files, p),
	};
}

test('a link that resolves in file and in heading passes', () => {
	const t = tree({
		'a/one.md': '# One\n\nSee [two](../b/two.md#42-a-title) and [self](#one).\n',
		'b/two.md': '## 42. A title\n',
	});
	const { errors, ok } = check(t.files, t.read, t.exists, []);
	assert.deepEqual(errors, []);
	assert.match(ok[0], /^2 relative link\(s\) across 2 markdown file\(s\) resolve$/);
});

test('a target that is not in the repository fails, naming the resolved path', () => {
	const t = tree({ 'a/one.md': '[x](../b/gone.md)\n' });
	const { errors } = check(t.files, t.read, t.exists, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /a\/one\.md:1: `\.\.\/b\/gone\.md` names b\/gone\.md, which is not in the repository/);
});

test('a bare numeric fragment fails and the failure names the slug to write', () => {
	const t = tree({
		'a/one.md': 'See [§ 42](../b/two.md#42).\n',
		'b/two.md': '## 42. A reworded title\n',
	});
	const { errors } = check(t.files, t.read, t.exists, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /Write `#42-a-reworded-title`\./);
});

test('a fragment whose heading was reworded fails, and the advice derives the new slug', () => {
	const t = tree({
		'a/one.md': '[§ 42](#42-the-old-wording)\n## 42. The new wording\n',
	});
	const { errors } = check(t.files, t.read, t.exists, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /Write `#42-the-new-wording`\./);
});

test('a non-numeric dead fragment gets the generic advice, not a fabricated slug', () => {
	const t = tree({ 'a/one.md': '[x](#no-such-heading)\n# Something else\n' });
	const { errors } = check(t.files, t.read, t.exists, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /The heading was reworded; re-slug the link/);
});

test('a fragment on a non-markdown target is not checked, but the path still is', () => {
	const t = tree({ 'a/one.md': '[x](./code.ts#L12)\n[y](./gone.ts#L3)\n', 'a/code.ts': '' });
	const { errors } = check(t.files, t.read, t.exists, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /gone\.ts/);
});

test('a link inside a code fence or a code span is not a link', () => {
	const t = tree({ 'a/one.md': '```\n[x](./gone.md)\n```\n\nAnd `[y](./gone.md)` inline.\n' });
	assert.deepEqual(check(t.files, t.read, t.exists, []).errors, []);
});

test('a target that walks out of the repository fails', () => {
	const t = tree({ 'one.md': '[x](../outside.md)\n' });
	const { errors } = check(t.files, t.read, t.exists, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /leaves the repository/);
});

test('an exemption excuses its own link and nothing else', () => {
	const t = tree({ 'one.md': '[a](../../issues)\n[b](../../pulls)\n' });
	const { errors } = check(t.files, t.read, t.exists, [
		{ file: 'one.md', target: '../../issues', reason: 'github.com-relative' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`\.\.\/\.\.\/pulls`/);
});

test('an exemption that matches nothing is itself a failure', () => {
	const t = tree({ 'one.md': 'no links here\n' });
	const { errors } = check(t.files, t.read, t.exists, [
		{ file: 'one.md', target: '../../issues', reason: 'stale' },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /matches nothing\. Delete it/);
});

test('an explicit HTML anchor satisfies a fragment', () => {
	const t = tree({
		'a/one.md': '[x](../b/two.md#legacy)\n',
		'b/two.md': '<a id="legacy"></a>\n\n## Some heading\n',
	});
	assert.deepEqual(check(t.files, t.read, t.exists, []).errors, []);
});

test('adviseFragment refuses to invent a slug for a number no heading carries', () => {
	const read = () => '## 7. Only this one\n';
	assert.match(adviseFragment('99', 'x.md', read), /No heading numbered 99 exists/);
});

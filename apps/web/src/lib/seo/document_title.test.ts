// Where the document title comes from, and how many of them a built page
// carries.
//
// `src/app.html` used to spell a literal `<title>Threkir</title>` before
// `%sveltekit.head%`. Svelte's SSR renderer keeps exactly ONE title per
// document -- the deepest component's, dropping every ancestor's -- but that
// dedupe operates over the component tree only, so a literal in the template
// is invisible to it and lands beside the page's own. Measured on a
// production build before the fix: 15 of the 16 built HTML files carried two
// title elements, and per the HTML spec the document title is the FIRST, so
// every `/learn` page -- the only surfaces this app prerenders FOR indexing
// (decisions § 161) -- presented as "Threkir" to a crawler, to a social
// unfurler and in the tab until hydration.
//
// The default now comes from the root layout's `<svelte:head>`, where a page
// that sets its own replaces it and one that sets none still has one.
//
// The deliberate consequence, which this guard states so it cannot be
// rediscovered: adapter-static's SPA fallback renders no components, so it
// carries NO title in its raw HTML. That was `build/index.html` and cost the
// site root its title; § 1268 prerendered the landing page onto that filename
// and moved the fallback to `build/200.html`, so the untitled document is now
// only the deep-link body. `src/lib/share/spa_shell_head_signals.test.ts`
// measures that file's four head signals; this one counts titles across every
// built page, the landing page included.
//
// Invocation:
//   npx tsx --test src/lib/seo/document_title.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

const webRoot = resolve(import.meta.dirname, '..', '..', '..');
const APP_HTML = resolve(webRoot, 'src', 'app.html');
const ROOT_LAYOUT = resolve(webRoot, 'src', 'routes', '+layout.svelte');
const BUILD = resolve(webRoot, 'build');

/// An end tag closes at `</title` followed by whitespace, `/` or `>`, then
/// junk to the first `>` -- the parser rule `raw_text_end_tag_guard.test.ts`
/// requires and `js/bad-tag-filter` is about. Spelled here rather than
/// imported from `$lib/share/head_splice` because that module is the share
/// Lambdas' sanitiser: it may narrow to what a shell carries, and this guard
/// must keep counting what a browser would parse.
const TITLE = /<title(?=[\s/>])[^>]*>[\s\S]*?<\/title(?=[\s/>])[^>]*>/gi;

/// A comment ends at the FIRST `-->`, and everything between is inert. Counted
/// without this, a title inside one reads as a title the document has: writing
/// the SvelteKit head placeholder into a comment in `app.html` substituted the
/// whole head there, and the pages still measured as carrying one title each
/// because the match came out of the wreckage.
///
/// Comments are consumed by the SAME scan rather than stripped in a prior
/// pass: deleting them first can splice two halves of the remaining text into
/// a `<title>` the document never contained, and re-running the strip to a
/// fixpoint would delete comment-looking spans the original never had either.
/// One alternation, first-match-wins, is what the parser actually does.
const SCAN = new RegExp(`<!--[\\s\\S]*?-->|${TITLE.source}`, 'gi');

function titles(html: string): string[] {
	return [...html.matchAll(SCAN)].map((m) => m[0]).filter((m) => !m.startsWith('<!--'));
}

function htmlFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === '_app') continue;
			htmlFiles(full, out);
			continue;
		}
		if (entry.name.endsWith('.html')) out.push(full);
	}
	return out;
}

test('app.html declares no title, so nothing outruns the head dedupe', () => {
	assert.deepEqual(
		titles(readFileSync(APP_HTML, 'utf8')),
		[],
		'A <title> in the template is emitted before %sveltekit.head% and cannot be ' +
			'replaced by a page, only followed by one. The default belongs in the root ' +
			"layout's <svelte:head>, where Svelte's dedupe can drop it.",
	);
});

test('the root layout declares exactly one default title', () => {
	const layout = readFileSync(ROOT_LAYOUT, 'utf8');
	const found = titles(layout);
	assert.equal(
		found.length,
		1,
		'The root layout is the single source of the default document title; a second ' +
			'one here would be dropped silently by the dedupe rather than reported.',
	);
	const head = layout.slice(layout.indexOf('<svelte:head>'), layout.indexOf('</svelte:head>'));
	assert.ok(
		head.includes(found[0]),
		'The default title must sit inside <svelte:head> to reach the document head.',
	);
});

test('no built page carries more than one title', (t) => {
	if (!existsSync(BUILD)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	const offenders = htmlFiles(BUILD)
		.map((f) => ({ file: relative(webRoot, f), count: titles(readFileSync(f, 'utf8')).length }))
		.filter((r) => r.count > 1)
		.map((r) => `${r.file} (${r.count})`);
	assert.deepEqual(
		offenders,
		[],
		'A document may hold one title element; a browser and a crawler both read the ' +
			`first, so a second is either ignored or wrong:\n  ${offenders.join('\n  ')}`,
	);
});

test('every prerendered Learn page carries its own title, not the site name', (t) => {
	if (!existsSync(BUILD)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	const learn = htmlFiles(BUILD).filter((f) => /(^|\/)learn(\.html$|\/)/.test(relative(BUILD, f)));
	// The population assertion: a filter that has stopped matching satisfies
	// every claim below without reading a page.
	assert.ok(
		learn.length >= 13,
		`expected the Learn hub, its six category pages and the guides to be prerendered, found ${learn.length}`,
	);
	for (const file of learn) {
		const found = titles(readFileSync(file, 'utf8'));
		const where = relative(webRoot, file);
		assert.equal(found.length, 1, `${where} should carry exactly one title, found ${found.length}`);
		assert.notEqual(
			found[0],
			'<title>Threkir</title>',
			`${where} presents as the bare site name, which is what the duplicate title did to ` +
				'every Learn page before decisions § 1167.',
		);
	}
});

test('no built page leaks an unsubstituted SvelteKit template placeholder', (t) => {
	if (!existsSync(BUILD)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	// `%sveltekit.head%` is substituted at its FIRST occurrence in app.html, so
	// naming it anywhere earlier -- in a comment, say -- injects the head there
	// and leaves the literal standing at the real position, as raw text inside
	// <head>. The page still renders enough to look right and every head-shape
	// assertion above still passes; this is the one that does not.
	const offenders = htmlFiles(BUILD)
		.map((f) => ({ file: relative(webRoot, f), html: readFileSync(f, 'utf8') }))
		.filter((r) => r.html.includes('%sveltekit.'))
		.map((r) => r.file);
	assert.deepEqual(
		offenders,
		[],
		`these built pages carry an unsubstituted %sveltekit.* placeholder:\n  ${offenders.join('\n  ')}`,
	);
});

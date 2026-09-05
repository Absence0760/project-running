// The strip-then-splice pipeline the four share-Lambda head injectors compose.
// Their own suites pin each injector's composed output; these pin the two steps
// themselves, and above all the reason the strip takes a SIGNAL LIST rather
// than doing everything.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	countHeadSignals,
	spliceIntoHead,
	stripStaleHeadSignals,
	type HeadSignal,
} from './head_splice';
import { injectShareRecapMeta } from './share_recap_spa_shell';
import { buildShareRecapMeta } from './share_recap_meta';

const ALL: readonly HeadSignal[] = ['title', 'social', 'canonical', 'jsonLd'];

const SHELL = `<!DOCTYPE html>
<html>
<head>
<title>Threkir</title>
<meta name="description" content="The running app">
<meta property="og:title" content="Threkir">
<meta name="twitter:card" content="summary">
<link rel="canonical" href="https://threkir.com/stale">
<script type="application/ld+json">{"@type":"WebSite"}</script>
<link rel="manifest" href="/manifest.webmanifest">
</head>
<body>
<div id="svelte"></div>
<script type="module" src="/_app/immutable/entry/start.abc.js"></script>
</body>
</html>`;

test('stripStaleHeadSignals — removes only the signals named', () => {
	const out = stripStaleHeadSignals(SHELL, ['title', 'social']);
	assert.deepEqual(countHeadSignals(out), {
		title: 0,
		social: 0,
		canonical: 1,
		jsonLd: 1,
	});
});

test('stripStaleHeadSignals — naming all four leaves none of them', () => {
	const out = stripStaleHeadSignals(SHELL, ALL);
	assert.deepEqual(countHeadSignals(out), { title: 0, social: 0, canonical: 0, jsonLd: 0 });
	// The document is otherwise untouched: the strips must never take the mount
	// div or the bundle tag with them (decisions § 1086).
	assert.ok(out.includes('<div id="svelte">'));
	assert.ok(out.includes('start.abc.js'));
	assert.ok(out.includes('rel="manifest"'));
});

test('stripStaleHeadSignals — an empty signal list is a no-op', () => {
	assert.equal(stripStaleHeadSignals(SHELL, []), SHELL);
});

test('stripStaleHeadSignals — the order the caller names them in cannot change the bytes', () => {
	const forwards = stripStaleHeadSignals(SHELL, ['title', 'social', 'canonical', 'jsonLd']);
	const backwards = stripStaleHeadSignals(SHELL, ['jsonLd', 'canonical', 'social', 'title']);
	assert.equal(backwards, forwards);
});

test('stripStaleHeadSignals — strips the FIRST title only', () => {
	// A shell arriving with two titles is a defect to report (the SPA fallback
	// and every prerendered page carry app.html's `<title>Threkir</title>`), not
	// one to absorb silently: the injected head supplies the one that wins.
	const two = SHELL.replace('<title>Threkir</title>', '<title>a</title><title>b</title>');
	const out = stripStaleHeadSignals(two, ['title']);
	assert.equal(countHeadSignals(out).title, 1);
	assert.ok(out.includes('<title>b</title>'));
});

for (const close of ['</script >', '</script\t\n bar>', '</script/>']) {
	test(`stripStaleHeadSignals — a JSON-LD block closed with ${JSON.stringify(close)}`, () => {
		const shell = SHELL.replace(
			'<script type="application/ld+json">{"@type":"WebSite"}</script>',
			`<script type="application/ld+json">{"@type":"WebSite"}${close}`,
		);
		const out = stripStaleHeadSignals(shell, ALL);
		assert.equal(out.includes('"WebSite"'), false);
		assert.ok(out.includes('start.abc.js'), 'the bundle must survive the strip');
		assert.ok(out.includes('<div id="svelte">'), 'the mount div must survive the strip');
	});
}

test('stripStaleHeadSignals — overlapping JSON-LD opens leave no residual <script', () => {
	const shell = SHELL.replace(
		'<script type="application/ld+json">{"@type":"WebSite"}</script>',
		'<script type="application/ld+json" data-a><script type="application/ld+json">{"x":1}</script>',
	);
	const out = stripStaleHeadSignals(shell, ALL);
	const head = out.slice(0, out.indexOf('</head'));
	assert.equal(head.includes('<script'), false);
});

test('stripStaleHeadSignals — a nonce or reordered attribute is still a JSON-LD block', () => {
	const shell = SHELL.replace(
		'<script type="application/ld+json">',
		'<script nonce="abc123" type="application/ld+json" data-x="1">',
	);
	assert.equal(countHeadSignals(stripStaleHeadSignals(shell, ALL)).jsonLd, 0);
});

test('spliceIntoHead — inserts before </head>, including one spelled with junk', () => {
	for (const shell of [SHELL, SHELL.replace('</head>', '</head\n>')]) {
		const out = spliceIntoHead(shell, '<meta name="x" content="y">');
		assert.ok(out.indexOf('name="x"') < out.indexOf('</head'));
	}
});

test('spliceIntoHead — a document with no </head> comes back unchanged', () => {
	const broken = '<html><body>no head</body></html>';
	assert.equal(spliceIntoHead(broken, '<title>x</title>'), broken);
});

test('countHeadSignals — counts what the strips act on, so a full strip zeroes it', () => {
	const counts = countHeadSignals(SHELL);
	assert.deepEqual(counts, { title: 1, social: 3, canonical: 1, jsonLd: 1 });
	assert.deepEqual(countHeadSignals(stripStaleHeadSignals(SHELL, ALL)), {
		title: 0,
		social: 0,
		canonical: 0,
		jsonLd: 0,
	});
});

test('injectShareRecapMeta \u2014 replaces the shell canonical, keeps the JSON-LD it does not emit', () => {
	// Half of this is the whole reason head_splice takes a signal list: a recap
	// head emits no JSON-LD, so a do-everything pipeline would strip the shell's
	// own WebSite node off every recap share page and put nothing back.
	//
	// The other half is the same rule read the other way. The recap head HAS
	// emitted a self-referential canonical since \u00a7 1090, so it must strip the
	// shell's -- and for a while it did not, which this case pinned as correct.
	// Nothing shipped broken only because the shell carries no canonical today
	// (spa_shell_head_signals.test.ts), a state that ends the day the landing
	// page prerenders at that filename.
	const out = injectShareRecapMeta(
		SHELL,
		buildShareRecapMeta({
			id: 'rec-1',
			recap: {
				id: 'rec-1',
				periodKind: 'year',
				periodKey: '2026',
				snapshot: { year: 2026 },
				displayName: 'Sam Runner',
			},
			siteUrl: 'https://threkir.com',
		}),
	);
	// Every canonical href, read out and compared: asking whether the recap's
	// URL appears anywhere also passes when it appears only as the og:url the
	// head just spliced in, and asking for the FIRST one also passes when a
	// second is standing behind it -- the outcome this case exists to rule out.
	const canonicals = [...out.matchAll(/<link\s[^>]*rel="canonical"[^>]*href="([^"]*)"/gi)].map(
		(m) => m[1],
	);
	assert.deepEqual(canonicals, ['https://threkir.com/recap/share/rec-1']);
	assert.ok(out.includes('"WebSite"'), 'the shell JSON-LD must survive');
});

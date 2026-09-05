import { test } from 'node:test';
import assert from 'node:assert/strict';
import { injectEntityHead, notFoundShell } from './entity_spa_shell';
import { countHeadSignals } from './head_splice';

const SHELL = `<!DOCTYPE html>
<html>
<head>
<title>Threkir</title>
<meta name="description" content="The running app">
<meta property="og:title" content="Threkir">
<meta property="og:image" content="/apple-touch-icon.png">
<link rel="canonical" href="https://threkir.com/stale">
<script type="application/ld+json">{"@type":"WebSite"}</script>
<link rel="manifest" href="/manifest.webmanifest">
</head>
<body>
<div id="svelte"></div>
<script type="module" src="/_app/immutable/entry/start.abc.js"></script>
</body>
</html>`;

const TAGS = [
	'<title>My Event — Threkir</title>',
	'<meta name="description" content="An event">',
	'<link rel="canonical" href="https://threkir.com/share/event/e-1">',
	'<meta property="og:title" content="My Event — Threkir">',
	'<script type="application/ld+json">{"@type":"SportsEvent"}</script>',
].join('\n\t');

test('injectEntityHead — replaces the SPA-shell title with the entity title', () => {
	const out = injectEntityHead(SHELL, TAGS);
	const titles = out.match(/<title(?=[\s/>])[^>]*>[^<]*<\/title(?=[\s/>])[^>]*>/g) ?? [];
	assert.equal(titles.length, 1);
	assert.ok(titles[0].includes('My Event'));
});

test('injectEntityHead — strips the stale canonical + JSON-LD, keeps the new ones', () => {
	const out = injectEntityHead(SHELL, TAGS);
	assert.equal(out.includes('threkir.com/stale'), false);
	const canonicals = out.match(/<link\s+rel="canonical"[^>]*>/g) ?? [];
	assert.equal(canonicals.length, 1);
	assert.ok(canonicals[0].includes('/share/event/e-1'));
	// Only the new SportsEvent JSON-LD survives (the stale WebSite is gone).
	assert.equal(out.includes('"WebSite"'), false);
	assert.ok(out.includes('"SportsEvent"'));
});

test('injectEntityHead — strips the stale og:image so unfurls do not duplicate', () => {
	const out = injectEntityHead(SHELL, TAGS);
	assert.equal(out.includes('/apple-touch-icon.png'), false);
});

test('injectEntityHead — preserves the hydrating SPA bundle script', () => {
	const out = injectEntityHead(SHELL, TAGS);
	assert.ok(out.includes('start.abc.js'));
	assert.ok(out.includes('<div id="svelte">'));
});

test('injectEntityHead — inserts the tags before </head>', () => {
	const out = injectEntityHead(SHELL, TAGS);
	const headClose = out.indexOf('</head>');
	const ogTitle = out.indexOf('og:title');
	assert.ok(ogTitle > -1 && ogTitle < headClose);
});

test('injectEntityHead — malformed shell with no </head> returns unmodified', () => {
	const broken = '<html><body>no head</body></html>';
	assert.equal(injectEntityHead(broken, TAGS), broken);
});

test('notFoundShell — the 404 body is the app shell, not a bespoke sentence', () => {
	// The five handlers each wrote their own unstyled English paragraph here.
	// None was ever read: the distribution replaces every 4xx body with the SPA
	// shell (decisions § 1022), so the reader got the designed `.notfound-card`
	// and the handler's own noindex went in the bin with the body. Returning the
	// shell makes the two agree, which is what lets the mapping go.
	const out = notFoundShell(SHELL, 'Run not found — Threkir');
	assert.ok(out.includes('<div id="svelte">'), 'the shell must still hydrate');
	assert.ok(out.includes('start.abc.js'), 'the SPA bundle must still load');
	assert.match(out, /name="robots" content="noindex"/);
	assert.ok(out.includes('<title>Run not found — Threkir</title>'));
	// Nothing about the entity may survive onto a page that says it is gone.
	assert.equal(out.includes('og:title'), false);
	assert.equal(out.includes('/apple-touch-icon.png'), false);
	assert.equal(out.includes('threkir.com/stale'), false);
	assert.equal(out.includes('"WebSite"'), false);
	// Exactly one title, so no crawler picks the stale one.
	assert.equal((out.match(/<title>/g) ?? []).length, 1);
});

test('notFoundShell — strips three signals it deliberately does not replace', () => {
	// § 1190 settled that an injector strips exactly what its own head emits, so
	// that a strip can never delete one of the shell's nodes and put nothing
	// back. THIS PATH IS THE ONE DELIBERATE EXCEPTION, and the exception is the
	// point of the surface: a page whose whole message is that the entity is gone
	// must not describe it, so the description, the social meta, the canonical
	// and the JSON-LD are removed with no replacement offered. A canonical here
	// would point a crawler at the missing thing as though it were the page's
	// home; a JSON-LD node would be structured data about an entity that no
	// longer exists.
	//
	// The cases above assert the SHELL's values are gone, which stays true if
	// something new is put in their place -- so a later tidy-up bringing this
	// path back in line with the § 1190 rule would pass every one of them. This
	// counts what the document actually carries instead, with the same patterns
	// the strips act on: the title the 404 supplies, the robots meta, and
	// nothing else.
	const out = notFoundShell(SHELL, 'Run not found — Threkir');
	assert.deepEqual(countHeadSignals(out), { title: 1, social: 0, canonical: 0, jsonLd: 0 });
	assert.equal((out.match(/name="robots"/g) ?? []).length, 1, 'exactly one robots directive');
});

test('notFoundShell — a title carrying markup cannot break out of the tag', () => {
	const out = notFoundShell(SHELL, 'Run </title><script>x()</script>');
	assert.equal(out.includes('<script>x()'), false);
	assert.equal((out.match(/<title>/g) ?? []).length, 1);
});

test('notFoundShell — an unusable shell still answers a noindex document', () => {
	// A 404 is the whole purpose of this branch: it tells a crawler the entity
	// is gone. Returning the shell unchanged (what injectEntityHead does with no
	// `</head>`) would carry no noindex, and throwing would reach the Lambda's
	// outer envelope and answer 503 — a retry signal for a link that will never
	// resolve, which is the defect § 1004 closed on the malformed-key path.
	for (const broken of ['<html><body>no head</body></html>', '', undefined]) {
		const out = notFoundShell(broken as unknown as string, 'Not found — Threkir');
		assert.match(out, /name="robots" content="noindex"/, String(broken));
		assert.ok(out.includes('<title>Not found — Threkir</title>'), String(broken));
	}
});

/// An end tag closes at `</script` + whitespace, `/` or `>`, whatever follows
/// to the first `>`. Before § 1086 the strip demanded `</script>` exactly, so
/// each of these left the stale block standing AND ran the lazy body on to the
/// bundle's own `</script>` — taking `</head>`, the mount div and the bundle
/// tag with it, after which the splice found no head and returned a shell with
/// none of the entity's meta on it.
const CLOSINGS = ['</script >', '</script\t\n bar>', '</script/>'];

for (const close of CLOSINGS) {
	test(`injectEntityHead — strips a JSON-LD block closed with ${JSON.stringify(close)}`, () => {
		const shell = SHELL.replace(
			'<script type="application/ld+json">{"@type":"WebSite"}</script>',
			`<script type="application/ld+json">{"@type":"WebSite"}${close}`,
		);
		const out = injectEntityHead(shell, TAGS);
		assert.equal(out.includes('"WebSite"'), false, 'stale JSON-LD must be gone');
		assert.ok(out.includes('start.abc.js'), 'the SPA bundle must survive the strip');
		assert.ok(out.includes('<div id="svelte">'), 'the mount div must survive the strip');
		assert.ok(out.includes('"SportsEvent"'), 'the entity tags must still be spliced in');
	});
}

test('injectEntityHead — splices before a `</head >` spelled with trailing junk', () => {
	const shell = SHELL.replace('</head>', '</head\n>');
	const out = injectEntityHead(shell, TAGS);
	assert.ok(out.includes('"SportsEvent"'), 'the entity tags must still be spliced in');
	assert.ok(out.indexOf('"SportsEvent"') < out.indexOf('</head'), 'and inside the head');
});

test('injectEntityHead — strips a JSON-LD block carrying extra attributes', () => {
	// A CSP nonce or a reordered attribute is still a JSON-LD block; matching
	// one exact attribute spelling would leave a second WebPage node standing.
	const shell = SHELL.replace(
		'<script type="application/ld+json">',
		'<script nonce="abc123" type="application/ld+json" data-x="1">',
	);
	const out = injectEntityHead(shell, TAGS);
	assert.equal(out.includes('"WebSite"'), false);
	assert.ok(out.includes('start.abc.js'));
});

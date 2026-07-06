import { test } from 'node:test';
import assert from 'node:assert/strict';
import { injectEntityHead } from './entity_spa_shell';

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
	const titles = out.match(/<title>[^<]*<\/title>/g) ?? [];
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

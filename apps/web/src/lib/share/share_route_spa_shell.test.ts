// Pure tests for the SPA-shell head injector used by the share-route
// Lambda. Web SEO parity with share-run (share_run_spa_shell.test.ts).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { injectShareRouteMeta } from './share_route_spa_shell';
import { buildShareRouteHead } from './share_route_meta';

function head(siteUrl = 'https://threkir.com', id = 'rt-1') {
	return buildShareRouteHead({
		id,
		route: {
			name: 'Riverside Loop',
			distance_m: 8000,
			surface: 'trail',
			elevation_m: 120,
		},
		siteUrl,
	});
}

const SHELL = `<!DOCTYPE html>
<html>
<head>
<title>Threkir</title>
<meta name="description" content="The running app">
<meta property="og:title" content="Threkir">
<meta property="og:image" content="/apple-touch-icon.png">
<link rel="canonical" href="https://threkir.com/">
<script type="application/ld+json">{"@type":"WebSite"}</script>
<link rel="manifest" href="/manifest.webmanifest">
</head>
<body>
<div id="svelte"></div>
<script type="module" src="/_app/immutable/entry/start.abc.js"></script>
</body>
</html>`;

test('injectShareRouteMeta — replaces the SPA-shell <title>', () => {
	const out = injectShareRouteMeta(SHELL, head());
	const titleMatches = out.match(/<title>[^<]+<\/title>/g) ?? [];
	assert.equal(titleMatches.length, 1);
	assert.ok(titleMatches[0].includes('Riverside Loop'));
});

test('injectShareRouteMeta — strips stale og:* / twitter:* tags', () => {
	const out = injectShareRouteMeta(SHELL, head());
	// SPA shell's og:image (favicon path) must be gone — duplicate
	// og:image tags break Slack / Twitter unfurls.
	assert.equal(out.includes('/apple-touch-icon.png'), false);
});

test('injectShareRouteMeta — strips the stale canonical link', () => {
	const out = injectShareRouteMeta(SHELL, head());
	const canonicalMatches = out.match(/<link\s+rel="canonical"[^>]*>/g) ?? [];
	// Exactly one canonical (the per-route one), not the shell's root.
	assert.equal(canonicalMatches.length, 1);
	assert.ok(canonicalMatches[0].includes('/share/route/rt-1'));
});

test('injectShareRouteMeta — strips the stale JSON-LD block', () => {
	const out = injectShareRouteMeta(SHELL, head());
	// The shell's WebSite node is gone; only the per-route WebPage
	// node survives (a second LD+JSON block confuses rich-result parsers).
	assert.equal(out.includes('"@type":"WebSite"'), false);
	const ldMatches = out.match(/application\/ld\+json/g) ?? [];
	assert.equal(ldMatches.length, 1);
	assert.ok(out.includes('WebPage'));
});

test('injectShareRouteMeta — strips spliced JSON-LD blocks, no residual <script', () => {
	// A single global replace scans the original once, so deleting one
	// ld+json block can splice surrounding text into a brand-new
	// `<script type="application/ld+json">…</script>` that a one-pass
	// strip would leave behind. The strip repeats until stable so the
	// spliced residual is also removed (js/incomplete-multi-character-sanitization).
	const spliced =
		'<sc<script type="application/ld+json">{"a":1}</script>' +
		'ript type="application/ld+json">{"b":2}</script>';
	const shell = SHELL.replace(
		'<script type="application/ld+json">{"@type":"WebSite"}</script>',
		spliced,
	);
	const out = injectShareRouteMeta(shell, head());
	// Only the per-route WebPage block remains; the spliced residual is gone.
	const ldMatches = out.match(/<script\s+type="application\/ld\+json">/g) ?? [];
	assert.equal(ldMatches.length, 1);
	assert.equal(out.includes('"a":1'), false);
	assert.equal(out.includes('"b":2'), false);
});

test('injectShareRouteMeta — inserts a full set of meta tags', () => {
	const out = injectShareRouteMeta(SHELL, head());
	assert.ok(out.includes('og:title'));
	assert.ok(out.includes('og:description'));
	assert.ok(out.includes('og:type'));
	assert.ok(out.includes('og:url'));
	assert.ok(out.includes('og:image'));
	assert.ok(out.includes('twitter:card'));
	assert.ok(out.includes('twitter:title'));
	assert.ok(out.includes('twitter:image'));
});

test('injectShareRouteMeta — preserves the SPA bundle <script> tag', () => {
	const out = injectShareRouteMeta(SHELL, head());
	assert.ok(out.includes('start.abc.js'));
	assert.ok(out.includes('<div id="svelte">'));
});

test('injectShareRouteMeta — inserts tags before </head>', () => {
	const out = injectShareRouteMeta(SHELL, head());
	const headCloseIdx = out.indexOf('</head>');
	const ogTitleIdx = out.indexOf('og:title');
	assert.ok(ogTitleIdx > -1 && ogTitleIdx < headCloseIdx);
});

test('injectShareRouteMeta — malformed shell with no </head> returns unmodified', () => {
	const broken = '<html><body>no head</body></html>';
	const out = injectShareRouteMeta(broken, head());
	assert.equal(out, broken);
});

test('buildShareRouteHead — title + description follow the route meta', () => {
	const h = head();
	assert.equal(h.title, 'Riverside Loop — Threkir');
	assert.ok(h.description.includes('8.0 km'));
	assert.ok(h.description.includes('trail'));
});

test('buildShareRouteHead — null route degrades to the generic head', () => {
	const h = buildShareRouteHead({ id: 'rt-x', route: null, siteUrl: 'https://threkir.com' });
	assert.equal(h.title, 'Route — Threkir');
	assert.equal(h.canonical, 'https://threkir.com/share/route/rt-x');
	assert.equal(h.ogImageUrl, 'https://threkir.com/og/route/rt-x.png');
	// JSON-LD still renders (a generic "Route" WebPage), never throws.
	assert.ok(h.jsonLd.includes('WebPage'));
});

test('injectShareRouteMeta — escapes HTML in the route name', () => {
	const evil = buildShareRouteHead({
		id: 'rt-1',
		route: {
			name: 'Loop "<script>alert(1)</script>"',
			distance_m: 5000,
			surface: 'road',
			elevation_m: null,
		},
		siteUrl: 'https://threkir.com',
	});
	const out = injectShareRouteMeta(SHELL, evil);
	// No live <script> from the name reaches the meta-tag output. (The
	// JSON-LD block legitimately contains a <script> wrapper, so assert
	// specifically that the alert payload is neutralised.)
	assert.equal(out.includes('<script>alert'), false);
	assert.ok(out.includes('&lt;script&gt;') || out.includes('\\u003cscript'));
});

test('buildShareRouteHead — uses per-env site URL for canonical + og:image', () => {
	const h = head('https://preview.threkir.com', 'rt-preview');
	assert.equal(h.canonical, 'https://preview.threkir.com/share/route/rt-preview');
	assert.equal(h.ogImageUrl, 'https://preview.threkir.com/og/route/rt-preview.png');
	const out = injectShareRouteMeta(SHELL, h);
	assert.ok(out.includes(`<link rel="canonical" href="${h.canonical}">`));
	assert.ok(out.includes(`<meta property="og:url" content="${h.canonical}">`));
	assert.ok(out.includes(`<meta property="og:image" content="${h.ogImageUrl}">`));
});

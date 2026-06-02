// Pure tests for the SPA-shell head injector used by the share-run
// Lambda. Persona-hunt finding Casual #4.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { injectShareRunMeta } from './share_run_spa_shell';
import { buildShareRunMeta } from './share_run_meta';

function meta() {
	return buildShareRunMeta({
		id: 'r-1',
		run: {
			id: 'r-1',
			user_id: 'u-1',
			distance_m: 10_000,
			duration_s: 3000,
			started_at: '2026-04-15T07:00:00Z',
			source: 'app',
			metadata: null,
		},
		displayName: 'Jane Runner',
		siteUrl: 'https://threkir.com',
	});
}

const SHELL = `<!DOCTYPE html>
<html>
<head>
<title>Threkir</title>
<meta name="description" content="The running app">
<meta property="og:title" content="Threkir">
<meta property="og:image" content="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">
</head>
<body>
<div id="svelte"></div>
<script type="module" src="/_app/immutable/entry/start.abc.js"></script>
</body>
</html>`;

test('injectShareRunMeta — replaces the SPA-shell <title>', () => {
	const out = injectShareRunMeta(SHELL, meta());
	// Original site-wide title gone; per-run title present.
	const titleMatches = out.match(/<title>[^<]+<\/title>/g) ?? [];
	assert.equal(titleMatches.length, 1);
	assert.ok(titleMatches[0].includes('10.0 km run'));
});

test('injectShareRunMeta — strips stale og:* / twitter:* tags', () => {
	const out = injectShareRunMeta(SHELL, meta());
	// SPA shell's og:image (favicon path) must be gone — duplicate
	// og:image tags break Slack / Twitter unfurls (different crawlers
	// pick different ones).
	assert.equal(out.includes('/apple-touch-icon.png'), false);
});

test('injectShareRunMeta — inserts a full set of meta tags', () => {
	const out = injectShareRunMeta(SHELL, meta());
	assert.ok(out.includes('og:title'));
	assert.ok(out.includes('og:description'));
	assert.ok(out.includes('og:image'));
	assert.ok(out.includes('og:url'));
	assert.ok(out.includes('twitter:card'));
	assert.ok(out.includes('twitter:title'));
	assert.ok(out.includes('twitter:image'));
});

test('injectShareRunMeta — preserves the SPA bundle <script> tag', () => {
	const out = injectShareRunMeta(SHELL, meta());
	// The hydrating script is what makes the page actually load — must
	// survive the head rewrite.
	assert.ok(out.includes('start.abc.js'));
	assert.ok(out.includes('<div id="svelte">'));
});

test('injectShareRunMeta — inserts tags before </head>', () => {
	const out = injectShareRunMeta(SHELL, meta());
	const headCloseIdx = out.indexOf('</head>');
	const ogTitleIdx = out.indexOf('og:title');
	assert.ok(ogTitleIdx > -1 && ogTitleIdx < headCloseIdx);
});

test('injectShareRunMeta — malformed shell with no </head> returns unmodified', () => {
	const broken = '<html><body>no head</body></html>';
	const out = injectShareRunMeta(broken, meta());
	assert.equal(out, broken);
});

test('buildShareRunMeta — surfaces runs.metadata.title over the distance formula', () => {
	const out = buildShareRunMeta({
		id: 'r-1',
		run: {
			id: 'r-1',
			user_id: 'u-1',
			distance_m: 10_000,
			duration_s: 3000,
			started_at: '2026-04-15T07:00:00Z',
			source: 'app',
			metadata: { title: 'Sunrise long run' },
		},
		displayName: 'Jane Runner',
		siteUrl: 'https://threkir.com',
	});
	assert.equal(out.title, 'Sunrise long run — Threkir');
});

test('buildShareRunMeta — ignores a non-string metadata.title', () => {
	const out = buildShareRunMeta({
		id: 'r-1',
		run: {
			id: 'r-1',
			user_id: 'u-1',
			distance_m: 10_000,
			duration_s: 3000,
			started_at: '2026-04-15T07:00:00Z',
			source: 'app',
			metadata: { title: 42 },
		},
		displayName: 'Jane Runner',
		siteUrl: 'https://threkir.com',
	});
	assert.ok(out.title.includes('10.0 km run'));
});

test('injectShareRunMeta — escapes HTML in display name', () => {
	const evilMeta = buildShareRunMeta({
		id: 'r-1',
		run: {
			id: 'r-1',
			user_id: 'u-1',
			distance_m: 5000,
			duration_s: 1500,
			started_at: '2026-04-15T07:00:00Z',
			source: 'app',
			metadata: null,
		},
		displayName: 'Jane "<script>alert(1)</script>"',
		siteUrl: 'https://threkir.com',
	});
	const out = injectShareRunMeta(SHELL, evilMeta);
	// No live <script> from the display name reaches the output.
	const scriptCount = (out.match(/<script>alert/g) ?? []).length;
	assert.equal(scriptCount, 0);
	// The escaped form is present (proves the value WAS injected,
	// just safely).
	assert.ok(out.includes('&lt;script&gt;') || out.includes('&quot;'));
});

test('injectShareRunMeta — uses per-env site URL for og:url + og:image', () => {
	const previewMeta = buildShareRunMeta({
		id: 'r-preview',
		run: {
			id: 'r-preview',
			user_id: 'u-1',
			distance_m: 5000,
			duration_s: 1500,
			started_at: '2026-04-15T07:00:00Z',
			source: 'app',
			metadata: null,
		},
		displayName: null,
		siteUrl: 'https://preview.threkir.com',
	});
	const out = injectShareRunMeta(SHELL, previewMeta);
	// The per-env origin flows through to the builder output verbatim...
	assert.equal(previewMeta.ogUrl, 'https://preview.threkir.com/share/run/r-preview');
	assert.equal(previewMeta.ogImageUrl, 'https://preview.threkir.com/og/run/r-preview.png');
	// ...and the injected shell carries those exact og tags. Match the full
	// `content="..."` attribute built from the meta (not a bare host
	// substring) so this stays an injection assertion, not a URL-prefix check
	// that CodeQL reads as an incomplete-sanitization guard.
	assert.ok(out.includes(`<meta property="og:url" content="${previewMeta.ogUrl}">`));
	assert.ok(out.includes(`<meta property="og:image" content="${previewMeta.ogImageUrl}">`));
});

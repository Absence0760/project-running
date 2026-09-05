// Pure tests for the SPA-shell head injector used by the share-run
// Lambda. Persona-hunt finding Casual #4.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { injectShareRunMeta } from './share_run_spa_shell';
import { buildShareRunMeta } from './share_run_meta';
import { buildShareBadgeMeta } from './share_badge_meta';

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
			concluded_at: null,
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
	const titleMatches = out.match(/<title(?=[\s/>])[^>]*>[^<]+<\/title(?=[\s/>])[^>]*>/g) ?? [];
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
			concluded_at: null,
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
			concluded_at: null,
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
			concluded_at: null,
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
			concluded_at: null,
		},
		displayName: null,
		siteUrl: 'https://preview.threkir.com',
	});
	const out = injectShareRunMeta(SHELL, previewMeta);
	// The per-env origin flows through to the builder output verbatim...
	assert.equal(previewMeta.canonical, 'https://preview.threkir.com/share/run/r-preview');
	assert.equal(previewMeta.ogImageUrl, 'https://preview.threkir.com/og/run/r-preview.png');
	// ...and the injected shell carries those exact og tags. Match the full
	// `content="..."` attribute built from the meta (not a bare host
	// substring) so this stays an injection assertion, not a URL-prefix check
	// that CodeQL reads as an incomplete-sanitization guard.
	assert.ok(out.includes(`<meta property="og:url" content="${previewMeta.canonical}">`));
	assert.ok(out.includes(`<link rel="canonical" href="${previewMeta.canonical}">`));
	assert.ok(out.includes(`<meta property="og:image" content="${previewMeta.ogImageUrl}">`));
});

/// The run shell's own SHELL above carries no JSON-LD; the deployed one does
/// (the root layout's WebSite node), which is what the strip exists for.
const SHELL_WITH_JSON_LD = SHELL.replace(
	'<link rel="manifest"',
	'<script type="application/ld+json">{"@type":"WebSite"}</script>\n<link rel="manifest"',
);

/// An end tag closes at `</script` + whitespace, `/` or `>`, whatever follows
/// to the first `>`. Before § 1086 the strip demanded `</script>` exactly, so
/// each of these left the stale block standing AND ran the lazy body on to the
/// bundle's own `</script>` — taking `</head>`, the mount div and the bundle
/// tag with it, after which the splice found no head and returned a shell with
/// none of the run's meta on it.
for (const close of ['</script >', '</script\t\n bar>', '</script/>']) {
	test(`injectShareRunMeta — strips a JSON-LD block closed with ${JSON.stringify(close)}`, () => {
		const shell = SHELL_WITH_JSON_LD.replace(
			'<script type="application/ld+json">{"@type":"WebSite"}</script>',
			`<script type="application/ld+json">{"@type":"WebSite"}${close}`,
		);
		const out = injectShareRunMeta(shell, meta());
		assert.equal(out.includes('"WebSite"'), false, 'stale JSON-LD must be gone');
		assert.ok(out.includes('start.abc.js'), 'the SPA bundle must survive the strip');
		assert.ok(out.includes('<div id="svelte">'), 'the mount div must survive the strip');
		assert.ok(out.includes('10.0 km run'), 'the run tags must still be spliced in');
	});
}

test('injectShareRunMeta — splices before a `</head >` spelled with trailing junk', () => {
	const out = injectShareRunMeta(SHELL_WITH_JSON_LD.replace('</head>', '</head\n>'), meta());
	assert.ok(out.includes('10.0 km run'));
	assert.ok(out.indexOf('10.0 km run') < out.indexOf('</head'));
});

test('injectShareRunMeta — strips a JSON-LD block carrying extra attributes', () => {
	const shell = SHELL_WITH_JSON_LD.replace(
		'<script type="application/ld+json">',
		'<script nonce="abc123" type="application/ld+json" data-x="1">',
	);
	const out = injectShareRunMeta(shell, meta());
	assert.equal(out.includes('"WebSite"'), false);
	assert.ok(out.includes('start.abc.js'));
});

test('injectShareRunMeta — a head with no JSON-LD leaves the shell\'s node alone', () => {
	// The badge share page reuses this injector with `jsonLd` unset. A strip
	// list fixed at the module level took the shell's own WebSite node off every
	// badge page and spliced nothing in its place -- the exact loss head_splice
	// takes a signal list to avoid, applied at the wrong granularity.
	const badge = buildShareBadgeMeta({
		id: 'b-1',
		badge: {
			id: 'b-1',
			user_id: 'u-1',
			badge_key: 'distance_total',
			tier: 'gold',
			value_num: 1000,
			earned_at: '2026-04-15T07:00:00Z',
		},
		displayName: 'Jane Runner',
		siteUrl: 'https://threkir.com',
	});
	assert.equal(badge.jsonLd, undefined, 'the badge head is the one that emits none');
	const out = injectShareRunMeta(SHELL_WITH_JSON_LD, badge);
	assert.ok(out.includes('"WebSite"'), "the shell's own JSON-LD must survive");
	assert.equal(
		(out.match(/type="application\/ld\+json"/g) ?? []).length,
		1,
		'and must not be joined by a second block',
	);
	// The signals the badge head DOES emit are still replaced, not doubled.
	const canonicals = [...out.matchAll(/<link\s[^>]*rel="canonical"[^>]*href="([^"]*)"/gi)].map(
		(m) => m[1],
	);
	assert.deepEqual(canonicals, ['https://threkir.com/share/badge/b-1']);
});

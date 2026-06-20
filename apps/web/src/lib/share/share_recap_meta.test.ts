import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildShareRecapMeta } from './share_recap_meta';
import { injectShareRecapMeta } from './share_recap_spa_shell';
import type { SharedRecap } from './share_recap_lookup';

function recap(over: Partial<SharedRecap> = {}): SharedRecap {
	return {
		id: 'rec-1',
		periodKind: 'year',
		periodKey: '2026',
		snapshot: { year: 2026, totalDistanceM: 1234000, runCount: 142 },
		displayName: 'Sam Runner',
		...over,
	};
}

test('buildShareRecapMeta: year title + og urls', () => {
	const meta = buildShareRecapMeta({ id: 'rec-1', recap: recap(), siteUrl: 'https://threkir.com' });
	assert.equal(meta.title, "Sam Runner's 2026 in running — Threkir");
	assert.equal(meta.ogUrl, 'https://threkir.com/recap/share/rec-1');
	assert.equal(meta.ogImageUrl, 'https://threkir.com/og/recap/rec-1.png');
});

test('buildShareRecapMeta: month title uses the month label', () => {
	const meta = buildShareRecapMeta({
		id: 'rec-2',
		recap: recap({ id: 'rec-2', periodKind: 'month', periodKey: '2026-03' }),
		siteUrl: 'https://threkir.com',
	});
	assert.ok(meta.title.includes('March 2026 in running'));
});

test('buildShareRecapMeta: anon snapshot drops the possessive name', () => {
	const meta = buildShareRecapMeta({
		id: 'rec-1',
		recap: recap({ displayName: null }),
		siteUrl: 'https://threkir.com',
	});
	assert.equal(meta.title, '2026 in running — Threkir');
});

test('buildShareRecapMeta: missing recap → generic branded meta', () => {
	const meta = buildShareRecapMeta({ id: 'x', recap: null, siteUrl: 'https://threkir.com' });
	assert.ok(meta.title.includes('Threkir'));
	assert.equal(meta.ogImageUrl, 'https://threkir.com/og/recap/x.png');
});

test('injectShareRecapMeta: replaces title + appends OG tags before </head>', () => {
	const shell =
		'<!doctype html><html><head><title>Threkir</title>' +
		'<meta property="og:image" content="/favicon.png"></head><body></body></html>';
	const meta = buildShareRecapMeta({ id: 'rec-1', recap: recap(), siteUrl: 'https://threkir.com' });
	const out = injectShareRecapMeta(shell, meta);
	// Old default title + default og:image stripped.
	assert.ok(!out.includes('<title>Threkir</title>'));
	assert.ok(!out.includes('content="/favicon.png"'));
	// New tags present, before </head>. The apostrophe is HTML-escaped in the
	// attribute/title output.
	assert.ok(out.includes('Sam Runner&#39;s 2026 in running'));
	assert.ok(out.includes('/og/recap/rec-1.png'));
	assert.ok(out.indexOf('og:image') < out.indexOf('</head>'));
});

test('injectShareRecapMeta: escapes a hostile display name', () => {
	const shell = '<html><head><title>x</title></head><body></body></html>';
	const meta = buildShareRecapMeta({
		id: 'rec-1',
		recap: recap({ displayName: '"><script>alert(1)</script>' }),
		siteUrl: 'https://threkir.com',
	});
	const out = injectShareRecapMeta(shell, meta);
	assert.ok(!out.includes('<script>alert(1)</script>'));
});

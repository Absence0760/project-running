import { test } from 'node:test';
import assert from 'node:assert/strict';

import { renderShareRunHeadTags, type ShareRunMeta } from './share_run_meta';
import { renderShareEventHeadTags, type ShareEventHead } from './share_event_meta';
import { renderShareClubHeadTags, type ShareClubHead } from './share_club_meta';
import { renderShareProfileHeadTags, type ShareProfileHead } from './share_profile_meta';
import { renderShareRaceHeadTags, type ShareRaceHead } from './share_race_meta';
import { renderShareRouteHeadTags, type ShareRouteHead } from './share_route_meta';
import { renderShareRecapHeadTags, type ShareRecapMeta } from './share_recap_meta';

// The render*HeadTags functions are the XSS boundary of the entity-SSR
// Lambda: they interpolate broadcaster-controlled strings (a display name,
// club name, route title, avatar URL, …) straight into raw `<head>` HTML.
// Every value must be attribute-escaped so a hostile field can't break out
// of its `content="…"` / `href="…"` attribute or terminate the <title>.
// These guards fail the build if a future edit drops an escapeHtml wrapper.

// A payload that, unescaped, would (a) close a content="" attribute and open
// an element, (b) terminate the <title>, and (c) inject a bare <script>.
const INJ = `"></title><img src=x onerror=alert(1)><script>alert(2)</script>`;

function assertSafe(out: string, label: string) {
	// No injected element start survives — the only tags the renderers emit
	// are <title>, <meta, <link, and a single <script type="application/ld+json">.
	assert.ok(!out.includes('<img'), `${label}: an injected <img start survived escaping`);
	assert.ok(!out.includes('<script>'), `${label}: a bare <script> survived escaping`);
	assert.ok(
		!out.includes('onerror=alert(1)>'), // the '>' that closes the tag must be escaped
		`${label}: an event-handler tag closed unescaped`,
	);
	// The <title> is opened + closed exactly once; an injected </title> is
	// escaped to &lt;/title&gt; rather than terminating the real element.
	assert.equal(out.split('<title>').length, 2, `${label}: <title> opened more than once`);
	assert.equal(out.split('</title>').length, 2, `${label}: <title> closed more than once`);
	// Positive proof the dangerous characters were encoded, not stripped.
	assert.ok(out.includes('&lt;img'), `${label}: '<' was not encoded to &lt;`);
	assert.ok(out.includes('&quot;'), `${label}: '"' was not encoded to &quot;`);
}

const withJsonLd = {
	title: INJ,
	description: INJ,
	canonical: INJ,
	ogImageUrl: INJ,
	// jsonLd is inserted raw by contract (build*JsonLd escapes it for the
	// script context upstream); keep it benign so it can't muddy the checks.
	jsonLd: '{"@context":"https://schema.org"}',
};

const cases: Array<{ name: string; out: () => string }> = [
	{ name: 'run', out: () => renderShareRunHeadTags(withJsonLd as ShareRunMeta) },
	{ name: 'event', out: () => renderShareEventHeadTags(withJsonLd as ShareEventHead) },
	{ name: 'club', out: () => renderShareClubHeadTags(withJsonLd as ShareClubHead) },
	{ name: 'profile', out: () => renderShareProfileHeadTags(withJsonLd as ShareProfileHead) },
	{ name: 'race', out: () => renderShareRaceHeadTags(withJsonLd as ShareRaceHead) },
	{ name: 'route', out: () => renderShareRouteHeadTags(withJsonLd as ShareRouteHead) },
	{
		name: 'recap',
		out: () =>
			renderShareRecapHeadTags({
				title: INJ,
				description: INJ,
				ogUrl: INJ,
				ogImageUrl: INJ,
			} as ShareRecapMeta),
	},
];

for (const c of cases) {
	test(`renderShare${c.name}HeadTags — hostile fields cannot break out of the head markup`, () => {
		assertSafe(c.out(), c.name);
	});
}

// The run renderer's jsonLd is optional; when omitted it must simply drop the
// script line rather than emit `undefined`.
test('renderShareRunHeadTags — omits the JSON-LD script when jsonLd is unset', () => {
	const out = renderShareRunHeadTags({
		title: 'A run',
		description: 'desc',
		canonical: 'https://threkir.com/share/run/r-1',
		ogImageUrl: 'https://threkir.com/og/run/r-1.png',
	});
	assert.ok(!out.includes('application/ld+json'), 'no JSON-LD script expected');
	assert.ok(!out.includes('undefined'), 'must not emit the literal "undefined"');
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { renderShareRunHeadTags, type ShareRunMeta } from './share_run_meta';
import { renderShareEventHeadTags, type ShareEventHead } from './share_event_meta';
import { renderShareClubHeadTags, type ShareClubHead } from './share_club_meta';
import { renderShareProfileHeadTags, type ShareProfileHead } from './share_profile_meta';
import { renderShareRaceHeadTags, type ShareRaceHead } from './share_race_meta';
import { renderShareRouteHeadTags, type ShareRouteHead } from './share_route_meta';
import { renderShareRecapHeadTags, type ShareRecapMeta } from './share_recap_meta';
import { renderShareSessionHeadTags, type ShareSessionHead } from './share_session_meta';
import { renderShareWorkoutHeadTags, type ShareWorkoutHead } from './share_workout_meta';

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

// Keyed on the EXPORTED NAME rather than on a nickname, so the census below
// is a set comparison against the directory and not a mapping someone has to
// keep in their head.
const cases: Array<{ name: string; out: () => string }> = [
	{ name: 'renderShareRunHeadTags', out: () => renderShareRunHeadTags(withJsonLd as ShareRunMeta) },
	{ name: 'renderShareEventHeadTags', out: () => renderShareEventHeadTags(withJsonLd as ShareEventHead) },
	{ name: 'renderShareClubHeadTags', out: () => renderShareClubHeadTags(withJsonLd as ShareClubHead) },
	{ name: 'renderShareProfileHeadTags', out: () => renderShareProfileHeadTags(withJsonLd as ShareProfileHead) },
	{ name: 'renderShareRaceHeadTags', out: () => renderShareRaceHeadTags(withJsonLd as ShareRaceHead) },
	{ name: 'renderShareRouteHeadTags', out: () => renderShareRouteHeadTags(withJsonLd as ShareRouteHead) },
	{ name: 'renderShareSessionHeadTags', out: () => renderShareSessionHeadTags(withJsonLd as ShareSessionHead) },
	{ name: 'renderShareWorkoutHeadTags', out: () => renderShareWorkoutHeadTags(withJsonLd as ShareWorkoutHead) },
	{
		name: 'renderShareRecapHeadTags',
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
	test(`${c.name} — hostile fields cannot break out of the head markup`, () => {
		assertSafe(c.out(), c.name);
	});
}

/// The census. Until this existed the `cases` array above was enumerated by
/// `import`, so a tenth renderer was escaped by nobody's assertion and nothing
/// said so — the shape § 1476 built the JSON-LD census to close and § 1531 the
/// clipping census to close, one property over on the same head.
///
/// The scan reads the DECLARATION rather than the `function` keyword: an
/// `export const renderShareXHeadTags = (…) =>` is the same renderer spelled
/// differently, and a census that missed it would fail in the silent direction.
/// Generics and `async` are tolerated for the same reason.
const RENDERER_DECL =
	/^export\s+(?:async\s+)?(?:function\s+(renderShare\w+HeadTags)\s*[<(]|(?:const|let|var)\s+(renderShare\w+HeadTags)\s*[:=])/gm;

test('every renderShare*HeadTags renderer is censused above', () => {
	const dir = dirname(fileURLToPath(import.meta.url));
	const declared = new Set<string>();
	for (const file of readdirSync(dir)) {
		if (!file.endsWith('.ts') || file.endsWith('.test.ts')) continue;
		const src = readFileSync(join(dir, file), 'utf-8');
		for (const m of src.matchAll(RENDERER_DECL)) declared.add(m[1] ?? m[2]);
	}
	const censused = new Set(cases.map((c) => c.name));
	assert.ok(declared.size > 0, 'the scan found no renderShare*HeadTags renderers at all');
	for (const name of declared) {
		assert.ok(
			censused.has(name),
			`${name} is exported but not censused in share_head_escaping.test.ts`,
		);
	}
	for (const name of censused) {
		assert.ok(declared.has(name), `${name} is censused but no longer exported`);
	}
});

/// There are TEN `buildShare*` entity builders and nine renderers, and the
/// difference is not a gap: `buildShareBadgeMeta` returns a `ShareRunMeta` and
/// is rendered by `renderShareRunHeadTags`, so the badge entity's head is
/// covered by the run row above rather than by one of its own. That is an
/// inheritance the census cannot see, so it is asserted rather than described —
/// a badge builder that grew its own shape would break this and be told to
/// bring a renderer and a row.
test('the badge entity inherits the run renderer rather than owning one', () => {
	const dir = dirname(fileURLToPath(import.meta.url));
	const src = readFileSync(join(dir, 'share_badge_meta.ts'), 'utf-8');
	assert.match(
		src,
		/export function buildShareBadgeMeta\([^)]*\): ShareRunMeta \{/,
		'buildShareBadgeMeta no longer returns ShareRunMeta — it now needs its own renderer and its own row above',
	);
});

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

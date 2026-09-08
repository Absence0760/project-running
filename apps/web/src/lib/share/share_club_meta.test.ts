import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildClubShareTitle,
	buildClubShareDescription,
	buildClubShareCanonical,
	buildClubJsonLd,
	buildShareClubHead,
	renderShareClubHeadTags,
} from './share_club_meta';
import type { SharedClub } from './share_club_lookup';

function c(over: Partial<SharedClub> = {}): SharedClub {
	return {
		id: 'c-1',
		slug: 'hampstead-runners',
		name: 'Hampstead Runners',
		description: 'A friendly London running club.',
		avatar_url: 'https://cdn/club.png',
		location_label: 'London, UK',
		...over,
	};
}

test('buildClubShareTitle — name + site suffix, generic fallback', () => {
	assert.equal(buildClubShareTitle(c()), 'Hampstead Runners — Threkir');
	assert.equal(buildClubShareTitle(null), 'Club — Threkir');
});

test('buildClubShareDescription — prefers the club description', () => {
	assert.equal(buildClubShareDescription(c()), 'A friendly London running club.');
});

test('buildClubShareDescription — falls back to location when no description', () => {
	assert.equal(
		buildClubShareDescription(c({ description: null })),
		'A running club in London, UK on Threkir.'
	);
	assert.equal(
		buildClubShareDescription(c({ description: null, location_label: null })),
		'A running club on Threkir.'
	);
	assert.equal(buildClubShareDescription(null), 'A running club on Threkir.');
});

test('buildClubShareCanonical — absolute share/club URL keyed by slug', () => {
	assert.equal(
		buildClubShareCanonical('https://threkir.com/', 'hampstead-runners'),
		'https://threkir.com/share/club/hampstead-runners'
	);
	assert.equal(buildClubShareCanonical(null, 'x'), '/share/club/x');
});

test('buildClubJsonLd — SportsOrganization with sport, logo, coarse areaServed', () => {
	const obj = JSON.parse(
		buildClubJsonLd(c(), { slug: 'hampstead-runners', base: 'https://threkir.com' })
	);
	assert.equal(obj['@type'], 'SportsOrganization');
	assert.equal(obj.name, 'Hampstead Runners');
	assert.equal(obj.url, 'https://threkir.com/share/club/hampstead-runners');
	assert.equal(obj.sport, 'Running');
	assert.equal(obj.logo, 'https://cdn/club.png');
	assert.equal(obj.areaServed, 'London, UK');
});

test('buildClubJsonLd — no avatar/location omits logo + areaServed', () => {
	const obj = JSON.parse(
		buildClubJsonLd(c({ avatar_url: null, location_label: null }), {
			slug: 'x',
			base: 'https://threkir.com',
		})
	);
	assert.equal('logo' in obj, false);
	assert.equal('areaServed' in obj, false);
});

test('buildClubJsonLd — escapes angle brackets so a name cannot break out of the script tag', () => {
	const json = buildClubJsonLd(c({ name: '</script><b>x</b>' }), {
		slug: 'x',
		base: 'https://threkir.com',
	});
	assert.ok(!json.includes('<'));
	assert.ok(!json.includes('>'));
	assert.equal(JSON.parse(json).name, '</script><b>x</b>');
});

// The description column holds 2,000 characters and the og:description budget
// is 160, so this cut is routine — and it used to land between the halves of a
// surrogate pair, which has no UTF-8 encoding: the crawler was served U+FFFD.
// The budget counts grapheme clusters (§ 1528), so the 159th character is the
// emoji whole rather than the first of its two code units.
test('buildShareClubHead — a description cut mid-emoji reaches the crawler intact', () => {
	const description = `${'a'.repeat(158)}\u{1F3C3} and the rest of what the club wrote`;
	const head = buildShareClubHead({
		slug: 'hampstead-runners',
		club: c({ description }),
		siteUrl: 'https://threkir.com',
	});
	const tags = renderShareClubHeadTags(head);
	assert.equal(Buffer.from(tags, 'utf8').toString('utf8'), tags);
	assert.doesNotMatch(head.description, /[\uD800-\uDBFF](?![\uDC00-\uDFFF])/);
	assert.ok(head.description.endsWith('\u{1F3C3}…'));
});

// A ZWJ sequence is eleven code units and one character. The code-unit budget
// cut inside it and served a fragment — well-formed text rendering as a woman
// and a dangling joiner, which is not what the club wrote.
test('buildShareClubHead — a description cut mid-ZWJ-sequence keeps the cluster whole', () => {
	const family = '\u{1F469}\u200D\u{1F469}\u200D\u{1F467}';
	const description = `${'a'.repeat(158)}${family} and the rest of what the club wrote`;
	const head = buildShareClubHead({
		slug: 'hampstead-runners',
		club: c({ description }),
		siteUrl: 'https://threkir.com',
	});
	assert.ok(head.description.endsWith(`${family}…`));
	const seg = new Intl.Segmenter('en', { granularity: 'grapheme' });
	assert.equal([...seg.segment(head.description)].length, 160);
});

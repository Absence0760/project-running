// Mirror suite for the `club_slug` TS↔Dart parity pair. Every case here has a
// twin in `apps/mobile_android/test/club_slug_test.dart`; the two must answer
// identically, which is the whole reason the module exists (decisions § 1279).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { clubSlug, CLUB_SLUG_FALLBACK, CLUB_SLUG_MAX_LEN } from './club_slug';

test('lower-cases and hyphenates a plain name', () => {
	assert.equal(clubSlug('Brighton Road Runners'), 'brighton-road-runners');
});

test('U+0130 folds to a bare i, so `İzmir` is `izmir` on both runtimes', () => {
	// The one code point reachable in Latin text where the two runtimes'
	// `toLowerCase` disagree (decisions § 1251). JS emits `i` + U+0307, which
	// the strip below used to turn into a separator: `i-zmir` on the web
	// against `izmir` on the phone, for the same club name.
	assert.equal(clubSlug('İzmir'), 'izmir');
	assert.equal(clubSlug('İzmir Koşu Kulübü'), 'izmir-kosu-kulubu');
});

test('a stripped diacritic leaves its base letter rather than a separator', () => {
	// The reason the fold is the right instrument and not merely a parity
	// patch: `z-rich-runners` is a worse URL than `zurich-runners`.
	assert.equal(clubSlug('Zürich Runners'), 'zurich-runners');
	assert.equal(clubSlug('Café des Coureurs'), 'cafe-des-coureurs');
});

test('a letter with no canonical decomposition still strips', () => {
	// The fold deliberately does not transliterate `ß` / `ø` / `đ` — inventing
	// an equivalence Unicode does not have is out of scope for it (§ 856).
	assert.equal(clubSlug('Straße Läufer'), 'stra-e-laufer');
});

test('a run of separators collapses to one hyphen', () => {
	assert.equal(clubSlug('Run   Club --- 2026'), 'run-club-2026');
});

test('leading and trailing separators are stripped', () => {
	assert.equal(clubSlug('  ...Trail Club!!!  '), 'trail-club');
});

test('digits survive', () => {
	assert.equal(clubSlug('5k Every Day'), '5k-every-day');
});

test('a name with no character that survives the fold yields the empty string', () => {
	// Both callers act on empty: the web substitutes a literal `club`, the
	// phone refuses the save and blames the name field.
	assert.equal(clubSlug('!!!'), '');
	assert.equal(clubSlug(''), '');
	assert.equal(clubSlug('   '), '');
});

test('a script the fold does not romanise yields the empty string', () => {
	// Folding is accent + case only, so a name written entirely outside
	// [a-z0-9] has no slug. Empty is the signal to substitute the fallback,
	// NOT to refuse the club — see the next case.
	assert.equal(clubSlug('Ελλάδα'), '');
	assert.equal(clubSlug('Бегуны'), '');
	assert.equal(clubSlug('東京ランナーズ'), '');
});

test('the fallback slug is one shared literal, not one per client', () => {
	// It reaches `clubs.slug` and becomes a public URL, so two hand-written
	// copies is the same class of defect as two hand-written derivations. A
	// club named entirely in a non-Latin script gets it, and the create
	// paths' collision retry distinguishes the second such club.
	assert.equal(CLUB_SLUG_FALLBACK, 'club');
	assert.equal(clubSlug('Бегуны Москвы') || CLUB_SLUG_FALLBACK, 'club');
});

test('the slug is capped at CLUB_SLUG_MAX_LEN', () => {
	// The phone had no cap at all before this module, so a long name produced
	// a 48-character URL from one client and an unbounded one from the other.
	const slug = clubSlug('a'.repeat(200));
	assert.equal(slug.length, CLUB_SLUG_MAX_LEN);
	assert.equal(slug, 'a'.repeat(CLUB_SLUG_MAX_LEN));
});

test('the cap never leaves a trailing hyphen', () => {
	// The cut can land on a separator, and a slug ending in a hyphen is the
	// one shape the edge strip exists to prevent.
	const name = `${'a'.repeat(CLUB_SLUG_MAX_LEN - 1)} bravo`;
	assert.equal(clubSlug(name), 'a'.repeat(CLUB_SLUG_MAX_LEN - 1));
});

test('the cap counts folded characters, not input characters', () => {
	// `Ü` is one input character and one folded character; a cap applied
	// before the fold would count the combining mark NFD produces.
	assert.equal(clubSlug('Ü'.repeat(60)), 'u'.repeat(CLUB_SLUG_MAX_LEN));
});

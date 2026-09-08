import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { planSlug, PLAN_SLUG_FALLBACK } from './plan_slug';

test('planSlug — an ASCII name kebabs', () => {
	assert.equal(planSlug('Richmond Half 2026'), 'richmond-half-2026');
	assert.equal(planSlug('  Spring   Build  '), 'spring-build');
	assert.equal(planSlug('-- Race day! --'), 'race-day');
});

test('planSlug — the dotted capital I folds to i, not to a separator', () => {
	// § 1398: `toLowerCase` maps U+0130 to `i` plus a combining dot, and the
	// strip then reads that dot as a word break.
	assert.equal(planSlug('İstanbul Marathon'), 'istanbul-marathon');
	assert.equal('İstanbul Marathon'.toLowerCase().replace(/[^a-z0-9]+/g, '-'), 'i-stanbul-marathon');
});

test('planSlug — a diacritic leaves its base letter rather than a hyphen', () => {
	assert.equal(planSlug('Champs-Élysées 10K'), 'champs-elysees-10k');
	assert.equal(planSlug('Zürich Build'), 'zurich-build');
	assert.equal(planSlug('Sōbetsu 50'), 'sobetsu-50');
});

test('planSlug — a letter with no decomposition strips rather than transliterating', () => {
	// Refusing an equivalence Unicode does not have is the same call `clubSlug`
	// makes; `ss` for `ß` and `o` for `ø` would be inventions.
	assert.equal(planSlug('Straße 10K'), 'stra-e-10k');
	assert.equal(planSlug('Trondheim Fjørd'), 'trondheim-fj-rd');
});

test('planSlug — nothing usable falls back rather than emitting hyphens', () => {
	assert.equal(planSlug(''), PLAN_SLUG_FALLBACK);
	assert.equal(planSlug('   '), PLAN_SLUG_FALLBACK);
	assert.equal(planSlug(null), PLAN_SLUG_FALLBACK);
	assert.equal(planSlug(undefined), PLAN_SLUG_FALLBACK);
	assert.equal(planSlug('!!! ---'), PLAN_SLUG_FALLBACK);
	// A name written entirely in a script the strip removes is the same case:
	// a filename of hyphens names nothing, so the fallback is the honest answer.
	assert.equal(planSlug('Марафон'), PLAN_SLUG_FALLBACK);
	assert.equal(planSlug('東京マラソン'), PLAN_SLUG_FALLBACK);
});

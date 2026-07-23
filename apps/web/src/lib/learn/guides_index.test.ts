import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	listGuides,
	listGuideSlugs,
	getGuide,
	isEnglishFallback,
	localizedGuideMeta,
	guidesByCategory,
	nonEmptyCategories,
	type GuideIndexEntry,
} from './guides_index';
import { CATEGORIES } from './categories';

// A dummy component stands in for the compiled `.md` body — the index
// operations only pass it through, never invoke it.
const C = (() => {}) as unknown as GuideIndexEntry['component'];

// Use two real category ids so nonEmptyCategories / guidesByCategory
// resolve against the actual catalogue.
const catA = CATEGORIES[0].id;
const catB = CATEGORIES[1].id;

function entry(over: Partial<GuideIndexEntry> = {}): GuideIndexEntry {
	return {
		slug: 'guide',
		locale: 'en',
		title: 'A guide',
		description: 'desc',
		category: catA,
		order: 1,
		updated: '2026-01-01',
		component: C,
		...over,
	};
}

const entries: GuideIndexEntry[] = [
	entry({ slug: 'beta', order: 2, title: 'Beta', category: catA }),
	entry({ slug: 'alpha', order: 1, title: 'Alpha', category: catA }),
	// Same order as alpha — title breaks the tie (Apex < Alpha? no: 'Alpha' < 'Apex').
	entry({ slug: 'apex', order: 1, title: 'Apex', category: catB }),
	// German variant of alpha (localized title/description).
	entry({ slug: 'alpha', locale: 'de', title: 'Alpha DE', description: 'desc DE', category: catA }),
];

// ---------------- listGuides / listGuideSlugs ----------------

test('listGuides — English only, ordered by order then title', () => {
	const got = listGuides(entries).map((e) => e.slug);
	// order 1: alpha (Alpha) < apex (Apex); order 2: beta. The de variant is excluded.
	assert.deepEqual(got, ['alpha', 'apex', 'beta']);
});

test('listGuides — never includes a localized (non-English) entry', () => {
	assert.ok(listGuides(entries).every((e) => e.locale === 'en'));
});

test('listGuideSlugs — slugs in the same English order', () => {
	assert.deepEqual(listGuideSlugs(entries), ['alpha', 'apex', 'beta']);
});

// ---------------- getGuide ----------------

test('getGuide — returns the localized entry when present', () => {
	const g = getGuide(entries, 'alpha', 'de');
	assert.equal(g?.locale, 'de');
	assert.equal(g?.title, 'Alpha DE');
});

test('getGuide — falls back to English when the locale file is absent', () => {
	const g = getGuide(entries, 'beta', 'de');
	assert.equal(g?.locale, 'en');
	assert.equal(g?.title, 'Beta');
});

test('getGuide — defaults to English locale', () => {
	assert.equal(getGuide(entries, 'alpha')?.locale, 'en');
});

test('getGuide — null for an unknown slug', () => {
	assert.equal(getGuide(entries, 'nope', 'de'), null);
});

// ---------------- isEnglishFallback ----------------

test('isEnglishFallback — false when viewing the default locale', () => {
	assert.equal(isEnglishFallback(entries, 'beta', 'en'), false);
});

test('isEnglishFallback — false when a localized file exists', () => {
	assert.equal(isEnglishFallback(entries, 'alpha', 'de'), false);
});

test('isEnglishFallback — true when a locale is requested but only English exists', () => {
	assert.equal(isEnglishFallback(entries, 'beta', 'de'), true);
});

// ---------------- localizedGuideMeta ----------------

test('localizedGuideMeta — uses the localized title/description, English category', () => {
	const m = localizedGuideMeta(entries, 'alpha', 'de');
	assert.equal(m?.title, 'Alpha DE');
	assert.equal(m?.description, 'desc DE');
	// Category always resolves off the English entry (the card's section).
	assert.equal(m?.category, catA);
});

test('localizedGuideMeta — falls back to English fields when no localized file', () => {
	const m = localizedGuideMeta(entries, 'beta', 'de');
	assert.equal(m?.title, 'Beta');
	assert.equal(m?.description, 'desc');
});

test('localizedGuideMeta — English request never reads a localized entry', () => {
	const m = localizedGuideMeta(entries, 'alpha', 'en');
	assert.equal(m?.title, 'Alpha');
	assert.equal(m?.description, 'desc');
});

test('localizedGuideMeta — null for an unknown slug', () => {
	assert.equal(localizedGuideMeta(entries, 'nope', 'de'), null);
});

// ---------------- guidesByCategory / nonEmptyCategories ----------------

test('guidesByCategory — English entries in that category, ordered', () => {
	assert.deepEqual(guidesByCategory(entries, catA).map((e) => e.slug), ['alpha', 'beta']);
	assert.deepEqual(guidesByCategory(entries, catB).map((e) => e.slug), ['apex']);
});

test('guidesByCategory — empty for a category with no guides', () => {
	const empty = CATEGORIES.find((c) => c.id !== catA && c.id !== catB);
	if (empty) assert.deepEqual(guidesByCategory(entries, empty.id), []);
});

test('nonEmptyCategories — only categories with ≥1 guide, in catalogue order', () => {
	const ids = nonEmptyCategories(entries).map((c) => c.id);
	assert.deepEqual(new Set(ids), new Set([catA, catB]));
	// Returned in ascending catalogue order.
	const orders = nonEmptyCategories(entries).map((c) => c.order);
	assert.deepEqual(orders, [...orders].sort((a, b) => a - b));
});

test('nonEmptyCategories — empty index yields no sections', () => {
	assert.deepEqual(nonEmptyCategories([]), []);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildGuideDescription,
	buildGuideJsonLd,
	buildGuideTitle,
	buildLearnCanonical,
	normaliseSiteUrl,
} from './learn_meta';

// ---------------- normaliseSiteUrl ----------------

test('normaliseSiteUrl — strips trailing slashes; tolerates nullish', () => {
	assert.equal(normaliseSiteUrl('https://threkir.com/'), 'https://threkir.com');
	assert.equal(normaliseSiteUrl('https://threkir.com///'), 'https://threkir.com');
	assert.equal(normaliseSiteUrl('https://threkir.com'), 'https://threkir.com');
	assert.equal(normaliseSiteUrl(null), '');
	assert.equal(normaliseSiteUrl(undefined), '');
});

// ---------------- buildLearnCanonical ----------------

test('buildLearnCanonical — joins base + path single-slashed', () => {
	assert.equal(
		buildLearnCanonical('https://threkir.com/', '/learn/road-running-101'),
		'https://threkir.com/learn/road-running-101',
	);
	assert.equal(buildLearnCanonical('https://threkir.com', '/learn'), 'https://threkir.com/learn');
});

test('buildLearnCanonical — normalises a path missing its leading slash', () => {
	assert.equal(buildLearnCanonical('https://threkir.com', 'learn'), 'https://threkir.com/learn');
});

test('buildLearnCanonical — yields a root-relative path when base is empty', () => {
	assert.equal(buildLearnCanonical('', '/learn/foo'), '/learn/foo');
});

// ---------------- buildGuideTitle / Description ----------------

test('buildGuideTitle — appends the site name; falls back when empty', () => {
	assert.equal(buildGuideTitle('Road running 101'), 'Road running 101 — Threkir');
	assert.equal(buildGuideTitle(''), 'Learn — Threkir');
	assert.equal(buildGuideTitle(null), 'Learn — Threkir');
});

test('buildGuideDescription — passes through; falls back when empty', () => {
	assert.equal(buildGuideDescription('A guide.'), 'A guide.');
	assert.equal(buildGuideDescription(''), 'Beginner running guides on Threkir.');
});

// ---------------- buildGuideJsonLd ----------------

function jsonLdInput(over: Partial<Parameters<typeof buildGuideJsonLd>[0]> = {}) {
	return {
		title: 'Road running 101',
		description: 'A beginner guide.',
		slug: 'road-running-101',
		updated: '2026-06-15',
		categoryId: 'getting-started',
		categoryLabel: 'Getting started',
		base: 'https://threkir.com',
		...over,
	};
}

test('buildGuideJsonLd — emits valid Article JSON with the expected wire shape', () => {
	const raw = buildGuideJsonLd(jsonLdInput());
	// Reverse the escape so JSON.parse sees the real characters.
	const json = raw.replace(/\\u003c/g, '<').replace(/\\u003e/g, '>').replace(/\\u0026/g, '&');
	const obj = JSON.parse(json);
	assert.equal(obj['@type'], 'Article');
	assert.equal(obj.headline, 'Road running 101');
	assert.equal(obj.description, 'A beginner guide.');
	assert.equal(obj.datePublished, '2026-06-15');
	assert.equal(obj.dateModified, '2026-06-15');
	assert.equal(obj.author.name, 'Threkir');
	assert.equal(obj.publisher.name, 'Threkir');
	assert.equal(obj.mainEntityOfPage, 'https://threkir.com/learn/road-running-101');
	assert.equal(obj.url, 'https://threkir.com/learn/road-running-101');
});

test('buildGuideJsonLd — breadcrumb is Home → Learn → category → article', () => {
	const raw = buildGuideJsonLd(jsonLdInput());
	const json = raw.replace(/\\u003c/g, '<').replace(/\\u003e/g, '>').replace(/\\u0026/g, '&');
	const obj = JSON.parse(json);
	const items = obj.breadcrumb.itemListElement;
	assert.equal(items.length, 4);
	assert.deepEqual(
		items.map((i: { name: string }) => i.name),
		['Threkir', 'Learn', 'Getting started', 'Road running 101'],
	);
	assert.equal(items[1].item, 'https://threkir.com/learn');
	assert.equal(items[2].item, 'https://threkir.com/learn/category/getting-started');
});

test('buildGuideJsonLd — escapes <, >, & so it cannot break out of the script tag', () => {
	const raw = buildGuideJsonLd(jsonLdInput({ title: 'Shoes </script><b> & laces' }));
	assert.ok(!raw.includes('</script>'), 'must not contain a literal closing script tag');
	assert.ok(!raw.includes('<b>'), 'must not contain raw angle brackets');
	assert.ok(raw.includes('\\u003c'), 'must escape < as \\u003c');
	assert.ok(raw.includes('\\u0026'), 'must escape & as \\u0026');
	// Still valid JSON once unescaped.
	const json = raw.replace(/\\u003c/g, '<').replace(/\\u003e/g, '>').replace(/\\u0026/g, '&');
	assert.doesNotThrow(() => JSON.parse(json));
});

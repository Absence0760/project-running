import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildGuideDescription,
	buildGuideJsonLd,
	buildGuideTitle,
	buildLearnCanonical,
	buildLearnCollectionJsonLd,
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

// ---------------- buildLearnCollectionJsonLd ----------------

const HUB_GUIDES = [
	{ slug: 'couch-to-5k', title: 'Couch to 5K: your first month' },
	{ slug: 'road-running-101', title: 'Road running 101' },
];

function parseCollection(json: string): Record<string, any> {
	// Round-trips the escape the builder applies, the way a browser's JSON-LD
	// reader does: the payload is valid JSON either way, so a test that read
	// the raw string would pass on a payload no consumer could parse.
	return JSON.parse(json.replace(/\\u003c/g, '<').replace(/\\u003e/g, '>').replace(/\\u0026/g, '&'));
}

test('buildLearnCollectionJsonLd — the hub is a CollectionPage, never an Article', () => {
	const node = parseCollection(
		buildLearnCollectionJsonLd({
			title: 'Learn to run — Threkir',
			description: 'Guides for new runners.',
			category: null,
			guides: HUB_GUIDES,
			base: 'https://threkir.com',
		}),
	);
	assert.equal(node['@context'], 'https://schema.org');
	assert.equal(node['@type'], 'CollectionPage');
	assert.equal(node.name, 'Learn to run — Threkir');
	assert.equal(node.description, 'Guides for new runners.');
	assert.equal(node.url, 'https://threkir.com/learn');
	assert.deepEqual(node.publisher, { '@type': 'Organization', name: 'Threkir' });
});

test('buildLearnCollectionJsonLd — the hub breadcrumb ends on itself, with no item', () => {
	const node = parseCollection(
		buildLearnCollectionJsonLd({
			title: 'Learn',
			description: 'd',
			category: null,
			guides: HUB_GUIDES,
			base: 'https://threkir.com',
		}),
	);
	assert.equal(node.breadcrumb['@type'], 'BreadcrumbList');
	assert.deepEqual(node.breadcrumb.itemListElement, [
		{ '@type': 'ListItem', position: 1, name: 'Threkir', item: 'https://threkir.com/' },
		{ '@type': 'ListItem', position: 2, name: 'Learn' },
	]);
});

test('buildLearnCollectionJsonLd — a category adds the Learn rung and names itself last', () => {
	const node = parseCollection(
		buildLearnCollectionJsonLd({
			title: 'Racing — Threkir',
			description: 'd',
			category: { id: 'racing', label: 'Racing' },
			guides: HUB_GUIDES,
			base: 'https://threkir.com/',
		}),
	);
	assert.equal(node.url, 'https://threkir.com/learn/category/racing');
	assert.deepEqual(node.breadcrumb.itemListElement, [
		{ '@type': 'ListItem', position: 1, name: 'Threkir', item: 'https://threkir.com/' },
		{ '@type': 'ListItem', position: 2, name: 'Learn', item: 'https://threkir.com/learn' },
		{ '@type': 'ListItem', position: 3, name: 'Racing' },
	]);
});

test('buildLearnCollectionJsonLd — the ItemList carries the guides in the order given', () => {
	const node = parseCollection(
		buildLearnCollectionJsonLd({
			title: 't',
			description: 'd',
			category: null,
			guides: HUB_GUIDES,
			base: 'https://threkir.com',
		}),
	);
	assert.equal(node.mainEntity['@type'], 'ItemList');
	assert.equal(node.mainEntity.numberOfItems, 2);
	assert.deepEqual(node.mainEntity.itemListElement, [
		{
			'@type': 'ListItem',
			position: 1,
			name: 'Couch to 5K: your first month',
			url: 'https://threkir.com/learn/couch-to-5k',
		},
		{
			'@type': 'ListItem',
			position: 2,
			name: 'Road running 101',
			url: 'https://threkir.com/learn/road-running-101',
		},
	]);
});

test('buildLearnCollectionJsonLd — a page listing nothing omits the ItemList rather than claiming an empty one', () => {
	const node = parseCollection(
		buildLearnCollectionJsonLd({
			title: 't',
			description: 'd',
			category: { id: 'trail', label: 'Trail' },
			guides: [],
			base: 'https://threkir.com',
		}),
	);
	assert.equal('mainEntity' in node, false);
	// The breadcrumb is still a claim the page can make about itself.
	assert.equal(node.breadcrumb.itemListElement.length, 3);
});

test('buildLearnCollectionJsonLd — an empty base yields root-relative URLs, not "undefined/"', () => {
	const node = parseCollection(
		buildLearnCollectionJsonLd({
			title: 't',
			description: 'd',
			category: null,
			guides: HUB_GUIDES,
			base: null,
		}),
	);
	assert.equal(node.url, '/learn');
	assert.equal(node.breadcrumb.itemListElement[0].item, '/');
	assert.equal(node.mainEntity.itemListElement[0].url, '/learn/couch-to-5k');
});

test('buildLearnCollectionJsonLd — escapes the characters that would break out of the script block', () => {
	const raw = buildLearnCollectionJsonLd({
		title: '</script><img src=x onerror=alert(1)>',
		description: 'a & b',
		category: null,
		guides: [{ slug: 's', title: '<b>' }],
		base: 'https://threkir.com',
	});
	assert.equal(raw.includes('<'), false);
	assert.equal(raw.includes('>'), false);
	assert.equal(raw.includes('&'), false);
	// And it is still the payload it claims to be once a reader unescapes it.
	assert.equal(parseCollection(raw).name, '</script><img src=x onerror=alert(1)>');
});

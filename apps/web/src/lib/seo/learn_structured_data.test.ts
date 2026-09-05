// What structured data each prerendered Learn page actually carries, read off
// the build rather than off the source that intends it.
//
// docs/features/seo.md claimed `Article` + `BreadcrumbList` for all three
// Learn routes for as long as the surface has existed. Measured 2026-09-04 on
// a production build, the hub and all six category pages carried NO
// `application/ld+json` block at all -- only the seven guide pages did. A
// render map is a claim about the artifact, so the artifact is what states it
// here (decisions § 1168).
//
// The type per route is the load-bearing half: a hub that declared itself an
// `Article` would be structured data describing a page that does not exist,
// which is worse for indexing than none.
//
// Invocation:
//   npx tsx --test src/lib/seo/learn_structured_data.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

const webRoot = resolve(import.meta.dirname, '..', '..', '..');
const BUILD = resolve(webRoot, 'build');
const SEO_DOC = resolve(webRoot, '..', '..', 'docs', 'features', 'seo.md');

/// One statement of what each kind of Learn page declares itself to be. The
/// artifact cases below assert the build agrees with it; the doc case asserts
/// the render map in seo.md does. Changing what a page emits therefore fails
/// until both the artifact and the doc have followed.
const DECLARED_TYPE = { hub: 'CollectionPage', category: 'CollectionPage', guide: 'Article' } as const;

/// The same parser-rule end tag `raw_text_end_tag_guard.test.ts` requires: a
/// block spelled `</script >` closes in every browser, and a regex that does
/// not see it reads the rest of the document as JSON-LD.
const LD_BLOCK =
	/<script(?=[\s/>])[^>]*\stype="application\/ld\+json"[^>]*>([\s\S]*?)<\/script(?=[\s/>])[^>]*>/gi;

/// A comment ends at the FIRST `-->` and everything inside is inert, so a
/// block found in one is not a block the page emits. Consumed by the SAME
/// scan rather than stripped in a prior pass: deleting them first can splice
/// two halves of the remaining text into a block the document never carried.
const SCAN = new RegExp(`<!--[\\s\\S]*?-->|${LD_BLOCK.source}`, 'gi');

/// The builders escape `<`, `>` and `&` so a payload cannot break out of the
/// script element; a JSON reader sees through that, and so must this.
function payloads(html: string): unknown[] {
	return [...html.matchAll(SCAN)]
		.filter((m) => !m[0].startsWith('<!--'))
		.map(([, body]) =>
		JSON.parse(
			body.replace(/\\u003c/g, '<').replace(/\\u003e/g, '>').replace(/\\u0026/g, '&'),
		),
	);
}

function htmlFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === '_app') continue;
			htmlFiles(full, out);
			continue;
		}
		if (entry.name.endsWith('.html')) out.push(full);
	}
	return out;
}

/// `learn.html` is the hub, `learn/category/<id>.html` a category index, and
/// everything else under `learn/` a guide.
function learnPages(): { file: string; rel: string; kind: 'hub' | 'category' | 'guide' }[] {
	return htmlFiles(BUILD)
		.map((file) => ({ file, rel: relative(BUILD, file).split('\\').join('/') }))
		.filter((p) => p.rel === 'learn.html' || p.rel.startsWith('learn/'))
		.map((p) => ({
			...p,
			kind:
				p.rel === 'learn.html'
					? ('hub' as const)
					: p.rel.startsWith('learn/category/')
						? ('category' as const)
						: ('guide' as const),
		}));
}

test('every prerendered Learn page carries exactly one JSON-LD block, of the type it is', (t) => {
	if (!existsSync(BUILD)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	const pages = learnPages();
	// The population first: a filter that has stopped matching satisfies every
	// claim below without reading a page.
	const kinds = { hub: 0, category: 0, guide: 0 };
	for (const p of pages) kinds[p.kind] += 1;
	assert.deepEqual(
		{ hub: kinds.hub, category: kinds.category, guides: kinds.guide >= 7 },
		{ hub: 1, category: 6, guides: true },
		`expected the hub, six category pages and at least seven guides to be prerendered, found ${JSON.stringify(kinds)}`,
	);

	for (const page of pages) {
		const found = payloads(readFileSync(page.file, 'utf8'));
		assert.equal(
			found.length,
			1,
			`${page.rel} should carry exactly one JSON-LD block, found ${found.length}`,
		);
		const node = found[0] as Record<string, unknown>;
		assert.equal(node['@context'], 'https://schema.org', `${page.rel} JSON-LD lacks the context`);
		assert.equal(
			node['@type'],
			DECLARED_TYPE[page.kind],
			`${page.rel} is a ${page.kind} page and must not declare itself a ${String(node['@type'])}`,
		);
	}
});

test('every prerendered Learn page carries a breadcrumb trail that ends on itself', (t) => {
	if (!existsSync(BUILD)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	const expectedRungs = { hub: 2, category: 3, guide: 4 };
	for (const page of learnPages()) {
		const node = payloads(readFileSync(page.file, 'utf8'))[0] as Record<string, any>;
		const crumb = node.breadcrumb;
		assert.equal(crumb?.['@type'], 'BreadcrumbList', `${page.rel} emits no BreadcrumbList`);
		const rungs = crumb.itemListElement as Record<string, unknown>[];
		assert.equal(
			rungs.length,
			expectedRungs[page.kind],
			`${page.rel} is a ${page.kind} page and should carry ${expectedRungs[page.kind]} breadcrumb rungs`,
		);
		rungs.forEach((rung, i) => {
			assert.equal(rung['@type'], 'ListItem', `${page.rel} breadcrumb rung ${i + 1} is not a ListItem`);
			assert.equal(rung.position, i + 1, `${page.rel} breadcrumb positions must be 1..n in order`);
			assert.ok(rung.name, `${page.rel} breadcrumb rung ${i + 1} has no name`);
		});
		// The last rung is the page being viewed, so it links nowhere: a
		// self-referential `item` is what Google's own guidance rules out.
		assert.equal(
			'item' in rungs[rungs.length - 1],
			false,
			`${page.rel} names itself as a linked breadcrumb rung`,
		);
	}
});

test('a Learn index lists the guides it shows, and never an empty collection', (t) => {
	if (!existsSync(BUILD)) {
		t.skip('no apps/web/build -- run `npm run build --workspace=apps/web` to check the artifact');
		return;
	}
	for (const page of learnPages().filter((p) => p.kind !== 'guide')) {
		const node = payloads(readFileSync(page.file, 'utf8'))[0] as Record<string, any>;
		const list = node.mainEntity;
		assert.equal(list?.['@type'], 'ItemList', `${page.rel} emits no ItemList of the guides it lists`);
		const items = list.itemListElement as Record<string, unknown>[];
		assert.ok(items.length > 0, `${page.rel} claims a collection with nothing in it`);
		assert.equal(list.numberOfItems, items.length, `${page.rel} miscounts its own ItemList`);
		items.forEach((item, i) => {
			assert.equal(item.position, i + 1, `${page.rel} ItemList positions must be 1..n in order`);
			assert.match(
				String(item.url),
				/\/learn\/[a-z0-9-]+$/,
				`${page.rel} ItemList entry ${i + 1} does not point at a guide`,
			);
		});
	}
});

/// The render map is a claim about the code and the artifact, and the Learn
/// rows have now been corrected three times in three rounds: the structured-data
/// cell over-claimed `Article` for the two index routes for as long as the
/// surface existed, was corrected to "none emitted", and then under-claimed that
/// once § 1168 gave both routes a builder; the mode cell then turned out to name
/// `entries()` for `/learn`, which is a static route and has none. Re-measuring
/// by hand is what keeps failing, so all three cells are DERIVED here from the
/// route's own files. The merged `/learn`, `/learn/category/[category]` row is
/// split for the same reason — one row describing two routes whose modes differ
/// cannot state either one exactly (§ 1193).
///
/// Deliberately no build: the artifact cases above self-skip without one and
/// `test-web` never builds, so a check folded into them would bind nowhere,
/// which is the condition these cells drifted under. Reading route source and a
/// committed markdown file needs no artifact.
const LEARN_ROUTES = [
	{ surface: '`/learn`', dir: 'learn', kind: 'hub' },
	{ surface: '`/learn/category/[category]`', dir: 'learn/category/[category]', kind: 'category' },
	{ surface: '`/learn/[slug]`', dir: 'learn/[slug]', kind: 'guide' },
] as const;

test('seo.md states, for every cell of every Learn row, what the route actually does', () => {
	const cells = readFileSync(SEO_DOC, 'utf8')
		.split('\n')
		.filter((line) => line.startsWith('|'))
		.map((line) => line.split('|').map((c) => c.trim()));

	for (const route of LEARN_ROUTES) {
		const found = cells.filter((row) => row[1] === route.surface);
		assert.equal(found.length, 1, `expected exactly one render-map row for ${route.surface}`);
		const [, , mode, headOwner, structured] = found[0];

		const loader = readFileSync(resolve(webRoot, 'src', 'routes', route.dir, '+page.ts'), 'utf8');
		const page = readFileSync(resolve(webRoot, 'src', 'routes', route.dir, '+page.svelte'), 'utf8');

		// Mode: prerendering and enumeration are separate facts, and the row that
		// merged the two index routes could state only one of them for both.
		assert.equal(
			mode.includes('prerendered'),
			/export const prerender\s*=\s*true/.test(loader),
			`${route.surface}: the mode cell disagrees with its own +page.ts about prerendering; it reads: ${mode}`,
		);
		assert.equal(
			mode.includes('entries()'),
			/export const entries\b/.test(loader),
			`${route.surface}: only a route with a dynamic segment to enumerate has entries(); the cell reads: ${mode}`,
		);

		// Head owner: who writes the head, and which JSON-LD builder it calls.
		assert.equal(
			headOwner.includes('<svelte:head>'),
			page.includes('<svelte:head>'),
			`${route.surface}: the head-owner cell disagrees with the page; it reads: ${headOwner}`,
		);
		for (const builder of ['buildLearnCollectionJsonLd', 'buildGuideJsonLd']) {
			assert.equal(
				headOwner.includes(builder),
				page.includes(builder),
				`${route.surface}: the head-owner cell must name the builder the page calls, and only that one; it reads: ${headOwner}`,
			);
		}

		// Structured data, against the same expectation the artifact cases assert.
		const owed = [DECLARED_TYPE[route.kind], 'BreadcrumbList'];
		if (route.kind !== 'guide') owed.push('ItemList');
		for (const name of owed) {
			assert.ok(
				structured.includes(name),
				`${route.surface}: the structured-data cell must name ${name}; it reads: ${structured}`,
			);
		}
		// Under-claiming reads as a dash, which the loop above already rejects;
		// over-claiming reads as the wrong type name beside the right one.
		const otherType = route.kind === 'guide' ? DECLARED_TYPE.hub : DECLARED_TYPE.guide;
		assert.equal(
			structured.includes(otherType),
			false,
			`${route.surface}: a ${route.kind} page is not a ${otherType}; the cell reads: ${structured}`,
		);
	}
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { CATEGORIES, CTA_TARGETS, getCtaTarget, isKnownCategory } from './categories';

const here = dirname(fileURLToPath(import.meta.url));
const routesDir = join(here, '..', '..', 'routes');

// A CTA target is a hardcoded string, so nothing at the type level notices
// when the page it names is renamed, moved, or — as happened with `racing`
// pointing at `/social?tab=clubs` long after `/races` shipped — superseded by
// a better destination. Resolving each route against the actual SvelteKit
// route tree turns that into a CI failure.
test('every CTA target resolves to a real page route', () => {
	for (const target of CTA_TARGETS) {
		const path = target.route.split('?')[0];
		assert.ok(path.startsWith('/'), `${target.feature}: route must be absolute`);
		assert.ok(
			existsSync(join(routesDir, path, '+page.svelte')),
			`${target.feature}: no page at '${path}'`,
		);
	}
});

test('the racing CTA points at the race calendar', () => {
	assert.equal(getCtaTarget('racing')?.route, '/races');
});

test('CTA features and category ids are unique', () => {
	const features = CTA_TARGETS.map((t) => t.feature);
	assert.equal(new Set(features).size, features.length, 'duplicate cta feature');
	const ids = CATEGORIES.map((c) => c.id);
	assert.equal(new Set(ids).size, ids.length, 'duplicate category id');
	for (const id of ids) assert.ok(isKnownCategory(id));
});

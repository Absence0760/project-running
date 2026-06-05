// Coverage for the request-time route og:image renderer. The contract
// that matters for unfurls: a route that can't be loaded (private,
// deleted, never existed, or no Supabase config at all) still renders a
// valid PNG — the generic branded card — so the caller can return HTTP
// 200 and a social unfurl never breaks with a 404 image. Web SEO parity
// with the share-run og path.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { renderRouteOgPng } from './og_route_png';

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47]); // \x89PNG

test('renderRouteOgPng — null config renders the generic branded card (valid PNG)', async () => {
	// No Supabase config → lookupSharedRoute short-circuits to a missing
	// route → the title-only "generic branded card" is rendered. This is
	// the private/deleted/never-existed path the og endpoint serves at 200.
	const png = await renderRouteOgPng('does-not-exist', null);
	assert.ok(Buffer.isBuffer(png));
	assert.ok(png.length > 0);
	// Real PNG bytes, not a JSON error body or the 1x1 transparent
	// last-ditch fallback being mistaken for a broken render.
	assert.ok(png.subarray(0, 4).equals(PNG_MAGIC), 'response starts with the PNG signature');
});

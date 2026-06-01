// Source-level guard on the share-run Lambda + og:image Cache-Control
// headers. Persona-hunt Round 3 finding Privacy #3 — pre-fix the
// 1-hour TTL pinned a public→private visibility flip to a 1h
// propagation window on the OG unfurl. The fix shortens both the
// Lambda's response header AND the prerendered og:image PNG's
// response header to 5 min with a 60 s stale-while-revalidate. A
// regression that bumps either back to 3600 (or anything longer than
// ~10 min) would reintroduce the privacy hole.
//
// This is a grep-style guard, not a runtime test, because actually
// driving the Lambda + the prerendered route handler from tsx would
// require a Supabase fake + the Svelte runtime. The lower-cost
// approach is to assert on the source text.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const __dirname = new URL('.', import.meta.url).pathname;

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('share-run Lambda Cache-Control caps the public→private flip window at ~5 min', () => {
	const src = read(
		__dirname,
		'..',
		'..',
		'lambda',
		'share-run',
		'src',
		'index.ts',
	);
	// Both the success (200) AND not-found (404) paths must use the
	// short TTL. A regression that left the 404 on the old 1h TTL
	// would mean a brand-new run flipping public couldn't un-404
	// until the hour was up — the inverse of the privacy hole.
	assert.match(
		src,
		/max-age=300/,
		'Lambda response Cache-Control must use max-age=300 so a ' +
			'public→private flip propagates within ~5 min, not the ' +
			'previous hour. See persona-hunt Round 3 finding Privacy #3.',
	);
	assert.match(
		src,
		/stale-while-revalidate=60/,
		'Lambda response should use stale-while-revalidate=60 to keep ' +
			'invocation cost bounded under a crawler storm without ' +
			'extending the stale-image window.',
	);
	// Hard negative: the old 1h TTL must not creep back in via a
	// half-revert.
	assert.doesNotMatch(
		src,
		/max-age=3600/,
		'A `max-age=3600` would re-pin a public→private visibility ' +
			'flip to a 1h propagation window — the bug the short TTL fixes.',
	);
});

test('og/run/[id].png request-time handler uses the same 5-min TTL', () => {
	const src = read(
		__dirname,
		'..',
		'routes',
		'og',
		'run',
		'[id].png',
		'+server.ts',
	);
	assert.match(
		src,
		/max-age=300, s-maxage=300, stale-while-revalidate=60/,
		'og/run/[id].png must use the same 5-min TTL as the share-run ' +
			'Lambda — the Cache-Control header CloudFront caches against.',
	);
	assert.doesNotMatch(
		src,
		/max-age=3600/,
		'The 1h TTL on the og.png was the actual privacy hole — a run ' +
			'flipped private would still surface its previous unfurl ' +
			'image for up to an hour. Persona-hunt Round 3 finding ' +
			'Privacy #3.',
	);
});

test('og/run/[id].png is request-time (prerender = false), not build-time', () => {
	const src = read(
		__dirname,
		'..',
		'routes',
		'og',
		'run',
		'[id].png',
		'+server.ts',
	);
	// Under adapter-static a prerendered route only exists for ids
	// known at build time, so a run created after the last build would
	// 404 and its social unfurl would show a broken image. The fix
	// pins this endpoint to request-time rendering. Persona-hunt
	// round-5 finding very-social.
	assert.match(
		src,
		/export const prerender = false/,
		'og/run/[id].png must render at request time so runs created ' +
			'after the last build still get an og:image. A `prerender = ' +
			'true` here regresses to the build-time-only 404.',
	);
});

test('share-run Lambda serves the og:image PNG path with a 200 fallback', () => {
	const src = read(
		__dirname,
		'..',
		'..',
		'lambda',
		'share-run',
		'src',
		'index.ts',
	);
	// The Lambda owns /og/run/<id>.png in prod (CloudFront routes it
	// here). It must match the path and render via the shared helper.
	assert.match(
		src,
		/\\\/og\\\/run\\\//,
		'The share-run Lambda must match /og/run/<id>.png — CloudFront ' +
			'routes that path to it. Persona-hunt round-5 very-social.',
	);
	assert.match(
		src,
		/renderRunOgPng/,
		'The Lambda must render the PNG via the shared renderRunOgPng ' +
			'helper so dev + prod produce the same card + fallback.',
	);
	// The PNG handler returns 200 even for a missing run — the renderer
	// falls back to a generic branded card. A 404 here would break the
	// unfurl image, which is the exact bug being fixed.
	assert.match(
		src,
		/statusCode: 200,\s*headers: \{\s*'content-type': 'image\/png'/,
		'The PNG path must return HTTP 200 (generic fallback card for ' +
			'private / deleted runs), never a 404 — a broken unfurl ' +
			'image is the bug. Persona-hunt round-5 very-social.',
	);
});

test('CloudFront routes /og/run/* to the share-run Lambda', () => {
	const tf = read(
		__dirname,
		'..',
		'..',
		'..',
		'..',
		'infra',
		'modules',
		'web-stack',
		'main.tf',
	);
	// Without this behaviour the PNG falls through to the S3 default
	// origin, which only has build-time-prerendered files — the
	// original 404. Persona-hunt round-5 very-social.
	assert.match(
		tf,
		/path_pattern\s*=\s*"\/og\/run\/\*"[\s\S]*?target_origin_id\s*=\s*"lambda-share-run"/,
		'CloudFront must route /og/run/* to the share-run Lambda so ' +
			'runs created after the last build get a request-time ' +
			'og:image. Persona-hunt round-5 very-social.',
	);
});

test('og/route/[id].png matches the og/run/[id].png TTL', () => {
	const src = read(
		__dirname,
		'..',
		'routes',
		'og',
		'route',
		'[id].png',
		'+server.ts',
	);
	// Routes carry the same `is_public` flag as runs and the same
	// privacy contract applies. Drift between the two would mean a
	// route flipped private kept its unfurl visible for an hour
	// while a run flipped private propagated in five minutes —
	// confusing for the same user toggling either kind of share.
	assert.match(src, /max-age=300, s-maxage=300, stale-while-revalidate=60/);
	assert.doesNotMatch(src, /max-age=3600/);
});

test('CloudFront cache policy for /share/run/* matches the origin TTL', () => {
	const tf = read(
		__dirname,
		'..',
		'..',
		'..',
		'..',
		'infra',
		'modules',
		'web-stack',
		'main.tf',
	);
	// CloudFront's default_ttl + max_ttl on the share_run cache
	// policy clamps how long the edge holds the response. A 3600
	// here would mean a 1h stale window even when the Lambda's
	// Cache-Control said 300 (max_ttl is the ceiling).
	assert.match(
		tf,
		/resource "aws_cloudfront_cache_policy" "share_run"[\s\S]*?default_ttl = 300/,
		'CloudFront cache policy for /share/run/* must default_ttl = 300 ' +
			'so the edge honours the Lambda\'s 5-min TTL. A 3600 here ' +
			'would silently override the origin.',
	);
	assert.match(
		tf,
		/resource "aws_cloudfront_cache_policy" "share_run"[\s\S]*?max_ttl     = 300/,
		'CloudFront cache policy max_ttl must also be 300; max_ttl ' +
			'caps the TTL regardless of what the origin Cache-Control ' +
			'says, so a higher max_ttl alone wouldn\'t cause the bug — ' +
			'but a lower max_ttl is what enforces the 5-min ceiling ' +
			'if the Lambda ever drifted.',
	);
});

// The four share Lambdas' own wrapper layers, plus the routing contract
// between them and the CloudFront behaviours that feed them.
//
// share-run, share-route, share-recap and share-badge each own two paths — an
// SPA-shell HTML page and an og:image PNG — matched by two regexes at the top
// of the handler. Nothing had ever executed any of the four. The older
// `share_run_cache_control.test.ts` says driving them "would require a
// Supabase fake"; it does not: with the Supabase env absent every lookup
// misses, the HTML path takes its not-found branch and the PNG path renders
// its generic branded card, and neither touches the network.
//
// The routing test is the one nothing else can state. A cache behaviour's
// `path_pattern` in Terraform and the `PATH_RE` in the Lambda it targets are
// two independent spellings of one route, and a path CloudFront sends to a
// Lambda whose regex does not match it answers the JSON 404 — which the
// distribution's own 404-to-index.html fallback then renders as the SPA shell
// at 200. A page appears, so nobody notices; that is the same shape as the
// mixed-case www host that served the whole site for a year.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// The SPA shell is substituted into each bundle by its build.mjs. Set before
// the handlers are imported so the HTML 200 path has something to inject into.
(globalThis as Record<string, unknown>).__SPA_SHELL_HTML__ =
	'<!DOCTYPE html><html><head><title>Threkir</title></head><body></body></html>';

// Deliberately absent, not pointed at a fake: an unset pair is the state a
// first apply leaves behind, every lookup then misses, and no case here can
// reach the network by accident.
delete process.env.PUBLIC_SUPABASE_URL;
delete process.env.PUBLIC_SUPABASE_ANON_KEY;

const { handler: shareRun } = await import('../../../lambda/share-run/src/index.js');
const { handler: shareRoute } = await import('../../../lambda/share-route/src/index.js');
const { handler: shareRecap } = await import('../../../lambda/share-recap/src/index.js');
const { handler: shareBadge } = await import('../../../lambda/share-badge/src/index.js');
const { handler: shareEntity } = await import('../../../lambda/share-entity/src/index.js');

interface FunctionUrlResponse {
	statusCode: number;
	headers?: Record<string, string>;
	body?: string;
	isBase64Encoded?: boolean;
}

type Handler = (event: unknown) => Promise<unknown>;

/// Keyed by the CloudFront origin id each Lambda backs, so the routing test
/// below can look one up from the Terraform rather than from a second list.
const BY_ORIGIN: Record<string, { dir: string; handler: Handler }> = {
	'lambda-share-run': { dir: 'share-run', handler: shareRun as Handler },
	'lambda-share-route': { dir: 'share-route', handler: shareRoute as Handler },
	'lambda-share-recap': { dir: 'share-recap', handler: shareRecap as Handler },
	'lambda-share-badge': { dir: 'share-badge', handler: shareBadge as Handler },
	'lambda-share-entity': { dir: 'share-entity', handler: shareEntity as Handler },
};

async function invoke(handler: Handler, rawPath: unknown): Promise<FunctionUrlResponse> {
	const realError = console.error;
	console.error = () => {};
	try {
		return (await handler({
			rawPath,
			requestContext: { http: { method: 'GET' } },
			headers: {},
		})) as FunctionUrlResponse;
	} finally {
		console.error = realError;
	}
}

/// A path the Lambda answered for itself, as opposed to the JSON 404 it
/// returns for anything its own regexes did not match.
function routed(out: FunctionUrlResponse): boolean {
	return !String(out.headers?.['content-type'] ?? '').startsWith('application/json');
}

const CACHE_CONTROL = 'public, max-age=300, s-maxage=300, stale-while-revalidate=60';

// ───────────────────── CloudFront routing ↔ Lambda regexes ─────────────────────

/// Every `ordered_cache_behavior` whose target origin is one of the share
/// Lambdas, as `{pattern, origin}`. Read out of the module rather than listed,
/// so a behaviour added there is one this test immediately asks about.
function shareBehaviours(): Array<{ pattern: string; origin: string }> {
	const tf = readFileSync(
		resolve(import.meta.dirname, '../../../../../infra/modules/web-stack/main.tf'),
		'utf-8',
	);
	const out: Array<{ pattern: string; origin: string }> = [];
	for (const m of tf.matchAll(
		/path_pattern\s*=\s*"([^"]+)"\s*\n\s*target_origin_id\s*=\s*"([^"]+)"/g,
	)) {
		if (m[2].startsWith('lambda-share-')) out.push({ pattern: m[1], origin: m[2] });
	}
	return out;
}

test('every share behaviour CloudFront declares is one its Lambda actually routes', async () => {
	const behaviours = shareBehaviours();
	assert.ok(
		behaviours.length >= 12,
		`read only ${behaviours.length} share behaviours from main.tf — parser broken?`,
	);
	const unrouted: string[] = [];
	for (const { pattern, origin } of behaviours) {
		const target = BY_ORIGIN[origin];
		assert.ok(target, `${origin} has no handler in this test — add it`);
		// The two shapes a `*` stands for on these behaviours: a bare entity id
		// and an og:image filename. Requiring one of them to route means the
		// test states no naming rule of its own.
		const candidates = ['5f1c7e2a', '5f1c7e2a.png'].map((leaf) =>
			pattern.replace(/\*$/, leaf),
		);
		const results = await Promise.all(candidates.map((p) => invoke(target.handler, p)));
		if (!results.some(routed)) unrouted.push(`${pattern} -> ${origin}`);
	}
	assert.deepEqual(
		unrouted.sort(),
		[],
		"CloudFront routes this path to a Lambda whose own regexes do not match it. The Lambda " +
			"answers its JSON 404, the distribution's 404-to-/index.html fallback turns that into " +
			'the SPA shell at 200, and the surface renders while the page it was meant to serve ' +
			'never existed.',
	);
});

// ───────────────────────── the four sibling wrappers ─────────────────────────

const SIBLINGS = [
	{ dir: 'share-run', handler: shareRun as Handler, html: '/share/run/5f1c7e2a', png: '/og/run/5f1c7e2a.png' },
	{ dir: 'share-route', handler: shareRoute as Handler, html: '/share/route/5f1c7e2a', png: '/og/route/5f1c7e2a.png' },
	{ dir: 'share-recap', handler: shareRecap as Handler, html: '/recap/share/5f1c7e2a', png: '/og/recap/5f1c7e2a.png' },
	{ dir: 'share-badge', handler: shareBadge as Handler, html: '/share/badge/5f1c7e2a', png: '/og/badge/5f1c7e2a.png' },
];

// The whole reason these render at request time rather than at build time is
// that a public->private flip must stale fast (persona-hunt Round 3, Privacy
// #3: a 1h TTL kept an un-shared run unfurling for an hour). The four have to
// agree, and one drifting is invisible from any single file.
test('all four share Lambdas send the same 5-minute Cache-Control on both paths', async () => {
	for (const { dir, handler, html, png } of SIBLINGS) {
		for (const path of [html, png]) {
			const out = await invoke(handler, path);
			assert.equal(out.headers?.['cache-control'], CACHE_CONTROL, `${dir} ${path}`);
		}
	}
});

// A crawler must be told the entity is gone rather than shown the site's
// generic card. The HTML branch answers a branded noindex page; the PNG branch
// deliberately does NOT 404, because a social unfurl whose image 404s renders
// as a broken card (round-5 very-social).
test('an entity that cannot be loaded is a noindex HTML 404 and a 200 PNG', async () => {
	for (const { dir, handler, html, png } of SIBLINGS) {
		const page = await invoke(handler, html);
		assert.equal(page.statusCode, 404, `${dir} HTML`);
		assert.match(String(page.headers?.['content-type']), /^text\/html/, `${dir} HTML`);
		assert.match(String(page.body), /name="robots" content="noindex"/, `${dir} HTML`);

		const image = await invoke(handler, png);
		assert.equal(image.statusCode, 200, `${dir} PNG must never 404 — an unfurl would break`);
		assert.equal(image.headers?.['content-type'], 'image/png', dir);
		assert.equal(image.isBase64Encoded, true, `${dir}: a Function URL binary body must be base64`);
		assert.equal(
			Buffer.from(String(image.body), 'base64').subarray(0, 8).toString('hex'),
			'89504e470d0a1a0a',
			`${dir}: the body is not a PNG`,
		);
	}
});

test('a path outside a share Lambda\'s own two routes is its JSON 404', async () => {
	for (const { dir, handler } of SIBLINGS) {
		for (const path of ['/', '/share/run/a/b', '/og/run/no-extension', '/anything']) {
			const out = await invoke(handler, path);
			if (routed(out)) continue;
			assert.equal(out.statusCode, 404, `${dir} ${path}`);
			assert.deepEqual(JSON.parse(String(out.body)), { error: 'not found' }, `${dir} ${path}`);
		}
	}
});

// The outer envelope. Anything unexpected becomes a generic 503 and a tagged
// operator log line, never the Node runtime's default error body — which would
// put the throw's message and stack on the wire.
test('an unexpected throw is a generic 503 on every share Lambda', async () => {
	for (const { dir, handler } of SIBLINGS) {
		const out = await invoke(handler, 42);
		assert.equal(out.statusCode, 503, dir);
		assert.equal(out.headers?.['content-type'], 'application/json', dir);
		assert.deepEqual(JSON.parse(String(out.body)), { error: 'temporarily unavailable' }, dir);
	}
});

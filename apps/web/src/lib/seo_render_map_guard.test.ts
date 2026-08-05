import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

/**
 * Guard-rail: `docs/features/seo.md`'s two tables must describe the routes
 * that exist.
 *
 * That doc is the single source of truth for the per-surface render mode and
 * the in-app -> share canonical folds, and it drifts silently because nothing
 * about a route breaks when the doc stops matching it. Both failure modes have
 * happened: round 8 found `/events/{id}` and `/notifications` named in the
 * crawl contract as routes that did not exist, and round 11 found the
 * canonical-consolidation section asserting in prose that `/runs/[id]` folded
 * onto `/share/run/[id]` while that page had no `<svelte:head>` at all — a
 * claim made in the doc AND in the share page's own comment, performed nowhere.
 *
 * Three checks, so neither direction of drift survives:
 *
 *  1. Every path named in either table resolves to a real route.
 *  2. Every canonical-consolidation row's in-app page actually emits a
 *     `<link rel="canonical">` built from a `build<X>ShareCanonical`.
 *  3. Every in-app page that emits such a canonical has a row. Without this
 *     third check the table could go stale by omission — a new fold would be
 *     invisible to the doc, which is how `/share/session` + `/share/workout`
 *     came to exist unlisted.
 *
 * Deliberately NOT checked: the `Mode` and `<head> owner` columns. Whether a
 * surface is prerendered or Lambda-SSR is not decidable from the route file
 * alone (it depends on the CloudFront behaviours + the Lambda dispatcher), and
 * a guard that guessed would either be wrong or force the doc to describe the
 * code rather than the contract.
 */

const __dirname = resolve(new URL('.', import.meta.url).pathname);
const routesRoot = resolve(__dirname, '../routes');
const repoRoot = resolve(__dirname, '../../../..');
const doc = readFileSync(resolve(repoRoot, 'docs/features/seo.md'), 'utf-8');

/// A route path as written in the doc (`/share/run/[id]`, `/og/run/[id].png`,
/// `/sitemap.xml`) maps onto a directory under `src/routes` holding a
/// `+page.svelte` or a `+server.ts`. A trailing `/*` means "the subtree",
/// satisfied by the parent existing.
function routeExists(path: string): boolean {
	const trimmed = path.replace(/\/\*$/, '');
	const dir = resolve(routesRoot, `.${trimmed}`);
	if (!existsSync(dir)) return false;
	return ['+page.svelte', '+server.ts'].some((f) => existsSync(resolve(dir, f)));
}

/// Backticked absolute paths inside one markdown table cell. Anything that is
/// not a route reference (a module name like `share_run_meta`, a JSON-LD type)
/// has no leading slash and is skipped by construction.
function pathsIn(cell: string): string[] {
	return [...cell.matchAll(/`(\/[^`]*)`/g)].map((m) => m[1]);
}

/// Body rows of the markdown table that follows `heading`, as arrays of cells.
/// Collection starts only after the `|---|` separator, so the header row is
/// never mistaken for data, and stops at the first non-table line after it.
function tableRows(heading: string): string[][] {
	const start = doc.indexOf(heading);
	assert.notEqual(start, -1, `seo.md has no "${heading}" section`);
	const rows: string[][] = [];
	let inBody = false;
	for (const line of doc.slice(start).split('\n').slice(1)) {
		const trimmed = line.trim();
		if (/^\|[\s|:-]+\|$/.test(trimmed)) {
			inBody = true;
			continue;
		}
		if (!trimmed.startsWith('|')) {
			if (inBody) break;
			continue;
		}
		if (!inBody) continue;
		rows.push(
			trimmed
				.replace(/^\|/, '')
				.replace(/\|$/, '')
				.split('|')
				.map((c) => c.trim()),
		);
	}
	assert.ok(rows.length > 0, `no table rows found under "${heading}"`);
	return rows;
}

const RENDER_MAP = '## Per-surface render map';
const CANONICAL = '## Canonical consolidation';

/// Paths the doc names that are not SvelteKit routes at all.
const NOT_ROUTES = new Set([
	// A static file served straight off S3, not a route directory.
	'/robots.txt',
]);

test('every path in the render map resolves to a real route', () => {
	const missing: string[] = [];
	for (const row of tableRows(RENDER_MAP)) {
		for (const path of pathsIn(row[0])) {
			if (NOT_ROUTES.has(path)) continue;
			if (path === '/') continue;
			if (!routeExists(path)) missing.push(path);
		}
	}
	assert.deepEqual(
		missing,
		[],
		`seo.md's render map names surfaces that are not routes: ${missing.join(', ')}. ` +
			'Either the route was renamed/deleted or the row was written for a surface ' +
			'that was never built (round 8 found two of the latter).',
	);
});

/// `/runs/[id]` -> `src/routes/runs/[id]/+page.svelte`.
function pageFor(path: string): string {
	return resolve(routesRoot, `.${path}`, '+page.svelte');
}

const canonicalRows = tableRows(CANONICAL).map(([inApp, twin]) => ({
	inApp: pathsIn(inApp)[0],
	twin: pathsIn(twin)[0],
}));

test('the canonical-consolidation table has a well-formed row per fold', () => {
	assert.ok(canonicalRows.length >= 5, 'the canonical table lost rows');
	for (const { inApp, twin } of canonicalRows) {
		assert.ok(inApp, 'a canonical row has no in-app path');
		assert.ok(twin, `the canonical row for ${inApp} has no share twin`);
		assert.ok(routeExists(inApp), `${inApp} is not a route`);
		assert.ok(routeExists(twin), `${inApp}'s canonical target ${twin} is not a route`);
	}
});

test('every documented in-app page emits a canonical to its share twin', () => {
	for (const { inApp, twin } of canonicalRows) {
		const page = pageFor(inApp);
		assert.ok(existsSync(page), `${inApp} has no +page.svelte`);
		const source = readFileSync(page, 'utf-8');
		assert.match(
			source,
			/<link\s+rel="canonical"/,
			`seo.md says ${inApp} canonicals onto ${twin}, but its +page.svelte emits no ` +
				'<link rel="canonical">. A fold asserted in the doc and performed nowhere is ' +
				'exactly what this guard exists to catch.',
		);
		assert.match(
			source,
			/build\w*ShareCanonical\(/,
			`${inApp} hand-rolls its canonical URL instead of using a build<X>ShareCanonical ` +
				'builder, so the doc and the share page can disagree about the target path.',
		);
	}
});

/// Every `+page.svelte` under `src/routes`, excluding the `/share/*` and
/// `/recap/share/*` pages themselves — those build their OWN canonical (they
/// are the fold target), which is not an in-app fold and owes no table row.
function inAppPages(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			inAppPages(full, out);
		} else if (entry.name === '+page.svelte') {
			const route = `/${relative(routesRoot, dir).split('\\').join('/')}`;
			if (route.startsWith('/share/') || route.startsWith('/recap/share')) continue;
			out.push(route);
		}
	}
	return out;
}

test('no in-app page folds onto a share twin without a table row', () => {
	const documented = new Set(canonicalRows.map((r) => r.inApp));
	const undocumented: string[] = [];
	for (const route of inAppPages(routesRoot)) {
		const source = readFileSync(pageFor(route), 'utf-8');
		if (!/build\w*ShareCanonical\(/.test(source)) continue;
		if (!documented.has(route)) undocumented.push(route);
	}
	assert.deepEqual(
		undocumented,
		[],
		`these pages emit a share canonical but have no row in seo.md's canonical-` +
			`consolidation table: ${undocumented.join(', ')}. Add the row — the table is ` +
			'the contract, and a fold missing from it is a fold nobody will maintain.',
	);
});

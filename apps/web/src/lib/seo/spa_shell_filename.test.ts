// One filename, named in three trees, and what happens when they disagree.
//
// adapter-static writes the prerendered pages first and then generates the SPA
// fallback -- to whatever name `svelte.config.js` gives it, over whatever is
// already at that path. So while the fallback was called `index.html`, the
// prerendered landing page was written to `build/index.html` and then replaced
// by a component-less shell: `/` shipped with no title, no canonical, no
// description and no JSON-LD, which is the whole of decisions § 1268. The
// separation only holds while every consumer of the shell reads the SAME new
// name:
//
//   - `svelte.config.js`               -- writes it
//   - `lambda/*/build.mjs`             -- embeds it in each share Lambda
//   - `infra/modules/web-stack/main.tf` -- CloudFront's 403 -> shell mapping,
//                                          the body of every deep link
//
// A rail left behind does not fail a build. A Lambda still reading
// `build/index.html` embeds the LANDING page as its shell -- whose asset URLs
// are relative (`./_app/...`, resolved against the request path) and whose
// hydration payload names route `/` -- and CloudFront still mapping 403 there
// serves that same page for every deep link. Both are silent in CI and visible
// only in production, which is why the agreement is asserted here rather than
// left to review.
//
// Invocation:
//   npx tsx --test src/lib/seo/spa_shell_filename.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';

const webRoot = resolve(import.meta.dirname, '..', '..', '..');
const repoRoot = resolve(webRoot, '..', '..');
const SVELTE_CONFIG = resolve(webRoot, 'svelte.config.js');
const LAMBDA_DIR = resolve(webRoot, 'lambda');
const WEB_STACK_TF = resolve(repoRoot, 'infra', 'modules', 'web-stack', 'main.tf');
const ROOT_PAGE = resolve(webRoot, 'src', 'routes', '+page.ts');

/// The adapter's `fallback` option, read out of the config that sets it. Every
/// other rail is compared against this one rather than against a literal, so
/// renaming the shell stays a one-line change and the guard reports the rails
/// that did not follow.
function fallbackName(): string {
	const source = readFileSync(SVELTE_CONFIG, 'utf8');
	const found = [...source.matchAll(/\bfallback:\s*["']([^"']+)["']/g)].map((m) => m[1]);
	assert.equal(
		found.length,
		1,
		`svelte.config.js should set the adapter fallback exactly once, found ${found.length}`,
	);
	return found[0];
}

/// Every share Lambda that embeds a file out of `build/` at bundle time,
/// discovered rather than listed: a sixth Lambda added tomorrow is covered the
/// day it names one, which a hard-coded roster would not be.
function lambdaShellRails(): { lambda: string; name: string }[] {
	const rails: { lambda: string; name: string }[] = [];
	const walk = (dir: string) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			if (entry.name === 'node_modules' || entry.name === 'dist') continue;
			const full = resolve(dir, entry.name);
			if (entry.isDirectory()) {
				walk(full);
				continue;
			}
			if (entry.name !== 'build.mjs') continue;
			const source = readFileSync(full, 'utf8');
			for (const m of source.matchAll(
				/resolve\(\s*webRoot\s*,\s*['"]build['"]\s*,\s*['"]([^'"]+)['"]/g,
			)) {
				rails.push({ lambda: relative(LAMBDA_DIR, full), name: m[1] });
			}
		}
	};
	walk(LAMBDA_DIR);
	return rails;
}

/// The `response_page_path` of the 403 -> shell mapping. Parsed off the block
/// rather than off the file, so an unrelated `custom_error_response` added
/// later cannot be mistaken for it.
function cloudFront403ShellPath(): string {
	const tf = readFileSync(WEB_STACK_TF, 'utf8');
	const blocks = [...tf.matchAll(/custom_error_response\s*\{([\s\S]*?)\n\s*\}/g)]
		.map((m) => m[1])
		.filter((body) => /\berror_code\s*=\s*403\b/.test(body));
	assert.equal(
		blocks.length,
		1,
		`infra/modules/web-stack/main.tf should map 403 exactly once, found ${blocks.length}`,
	);
	const path = /\bresponse_page_path\s*=\s*"([^"]+)"/.exec(blocks[0]);
	assert.ok(path, 'the 403 custom_error_response declares no response_page_path');
	return path[1];
}

test('the landing page is prerendered, so the fallback may not share its filename', () => {
	const page = readFileSync(ROOT_PAGE, 'utf8');
	assert.match(
		page,
		/^export const prerender = true;$/m,
		'`/` must prerender or `build/index.html` is the component-less shell and the site ' +
			'root ships with none of the head docs/features/seo.md promises it.',
	);
	assert.notEqual(
		fallbackName(),
		'index.html',
		'adapter-static generates the fallback after writing the prerendered pages and to ' +
			'this name, so naming it index.html overwrites the prerendered landing page with ' +
			'the shell -- the exact defect decisions § 1268 closed.',
	);
});

test('every share Lambda embeds the file the adapter actually writes the shell to', () => {
	const expected = fallbackName();
	const rails = lambdaShellRails();
	assert.ok(
		rails.length >= 5,
		`expected the five share Lambdas to embed a build/ shell, found ${rails.length} ` +
			'-- a filter that has stopped matching satisfies the claim below without reading one',
	);
	const wrong = rails.filter((r) => r.name !== expected).map((r) => `${r.lambda} -> ${r.name}`);
	assert.deepEqual(
		wrong,
		[],
		`these Lambdas embed a different file than the adapter writes the shell to (${expected}). ` +
			'Embedding the prerendered landing page instead ships relative asset URLs and a ' +
			`hydration payload for route "/" to every share URL:\n  ${wrong.join('\n  ')}`,
	);
});

test("CloudFront's 403 mapping serves the shell, not the prerendered landing page", () => {
	assert.equal(
		cloudFront403ShellPath(),
		`/${fallbackName()}`,
		'Every deep link is a missing S3 key answered 403 and rewritten to this path. ' +
			'Pointing it at the prerendered landing page serves that page for /runs/<id> ' +
			'and every other client route -- with its asset URLs resolved against the deep ' +
			"link's own directory, so nothing loads at all.",
	);
});

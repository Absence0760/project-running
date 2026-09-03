import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');
const WEB_ROOT = join(E2E_ROOT, '..');
const REPO_ROOT = join(WEB_ROOT, '..', '..');

const CONFIG = 'tsconfig.tests-e2e.json';
const SCRIPT = 'check:e2e-types';

/**
 * Extensions TypeScript can compile. A file carrying one of these is a file
 * `tsc` should be reading — anything here that no `include` pattern matches is
 * coverage the Playwright tree silently lost.
 */
const COMPILABLE = new Set(['.ts', '.mts', '.cts', '.tsx', '.js', '.mjs', '.cjs', '.jsx']);

/** `include` entries, which must all be of the form `tests-e2e/**\/*.<ext>`. */
function includedExtensions(): Set<string> {
	// Comments are legal in a tsconfig and this one carries them, so blank them
	// before parsing rather than reaching for a JSON5 dependency. Through the
	// shared stripper: JSONC takes block comments and trailing ones too, which
	// the line-only strip this replaced would have handed to `JSON.parse`.
	const raw = stripComments(readFileSync(join(WEB_ROOT, CONFIG), 'utf8'));
	const parsed = JSON.parse(raw) as { extends?: string; include?: string[] };
	assert.equal(
		parsed.extends,
		'./tsconfig.json',
		`${CONFIG} must extend the app's own tsconfig — its strictness is where the checking comes from.`
	);
	const include = parsed.include ?? [];
	assert.ok(include.length > 0, `${CONFIG} declares no include, so it checks nothing.`);

	const exts = new Set<string>();
	for (const pattern of include) {
		const match = /^tests-e2e\/\*\*\/\*(\.[a-z]+)$/.exec(pattern);
		assert.ok(
			match,
			`${CONFIG} include entry ${JSON.stringify(pattern)} is not of the form ` +
				'"tests-e2e/**/*.<ext>", which is the only shape this guard can verify.'
		);
		exts.add(match[1]);
	}
	return exts;
}

function walk(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) walk(full, out);
		else out.push(full);
	}
	return out;
}

test('every compilable file under tests-e2e is inside the typecheck', () => {
	const covered = includedExtensions();
	const missed = walk(E2E_ROOT)
		.filter((f) => COMPILABLE.has(extname(f)) && !covered.has(extname(f)))
		.map((f) => f.slice(E2E_ROOT.length + 1));

	assert.deepEqual(
		missed,
		[],
		`These files carry a compilable extension no ${CONFIG} include pattern matches, so ` +
			'nothing typechecks them. Add the extension to the include list (and fix whatever ' +
			`it surfaces) rather than leaving it outside: ${missed.join(', ')}`
	);
});

test('the typecheck is reachable as an npm script and runs in CI', () => {
	const pkg = JSON.parse(readFileSync(join(WEB_ROOT, 'package.json'), 'utf8')) as {
		scripts?: Record<string, string>;
	};
	const script = pkg.scripts?.[SCRIPT];
	assert.ok(script, `apps/web/package.json must declare a "${SCRIPT}" script.`);
	assert.match(
		script,
		new RegExp(CONFIG.replace('.', '\\.')),
		`"${SCRIPT}" must point at ${CONFIG}.`
	);
	// `svelte-kit sync` first: the config chain bottoms out in the generated
	// .svelte-kit/tsconfig.json, which a clean checkout does not have.
	assert.match(script, /svelte-kit sync/, `"${SCRIPT}" must sync SvelteKit before running tsc.`);

	const ci = readFileSync(join(REPO_ROOT, '.github', 'workflows', 'ci.yml'), 'utf8');
	assert.ok(
		ci.includes(SCRIPT),
		`.github/workflows/ci.yml must run "${SCRIPT}" — a typecheck nothing in CI runs is ` +
			'exactly the gap this config was added to close.'
	);
});

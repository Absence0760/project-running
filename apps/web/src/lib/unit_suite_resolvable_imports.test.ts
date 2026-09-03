// `npm run test:unit` is raw `tsx --test` over `src/**/*.test.ts`. tsx resolves
// path aliases from tsconfig, and `apps/web/tsconfig.json` gets `$lib` / `$app`
// only by extending `./.svelte-kit/tsconfig.json`, which `svelte-kit sync`
// generates and CI never runs before this job. So an aliased import in a unit
// test passes in a worktree where some earlier `svelte-check` happened to
// generate that file, and fails in CI with ERR_MODULE_NOT_FOUND. Relative
// imports resolve either way.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';

import { stripComments } from './core/strip_comments';

const SRC = new URL('.', import.meta.url).pathname;

function unitTestFiles(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) out.push(...unitTestFiles(full));
		else if (entry.name.endsWith('.test.ts')) out.push(full);
	}
	return out;
}

test('no unit test imports through a SvelteKit path alias', () => {
	const offenders: string[] = [];
	for (const file of unitTestFiles(SRC)) {
		const source = stripComments(readFileSync(file, 'utf-8'));
		// Anchored at column 0 with no leading whitespace, because only a real
		// module specifier counts: `map_surface_basemap_guard.test.ts` carries an
		// aliased import inside a quoted fixture line it asserts about, and that
		// line is indented. Prettier keeps every import statement flush-left,
		// including the closing `} from '...'` of a multi-line one, so a genuine
		// import cannot hide from this.
		const aliased = source.match(
			/^(?:import\b|export\b|\}).*['"]\$(?:lib|app|env)\//gm
		);
		if (aliased) offenders.push(`${relative(SRC, file)} (${aliased.length})`);
	}
	assert.deepEqual(
		offenders,
		[],
		`These unit tests import through a SvelteKit alias, which resolves only ` +
			`after \`svelte-kit sync\` has written .svelte-kit/tsconfig.json. CI does ` +
			`not run it before \`npm run test:unit\`, so each fails there with ` +
			`ERR_MODULE_NOT_FOUND while passing locally. Use a relative import:\n  ` +
			offenders.join('\n  ')
	);
});

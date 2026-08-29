import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	INDIRECT,
	checkDeadDependencies,
	declaredDeps,
	emptyUsage,
	invokedCommands,
	isScannable,
	packageOf,
	readBy,
	scanSource,
	tsconfigTypes,
	workspaceDirs,
} from './check_dead_dependencies.mjs';

const REPO_ROOT = join(import.meta.dirname, '..');

/** @param {Partial<import('./check_dead_dependencies.mjs').Usage>} parts */
const usageOf = (parts) => ({ ...emptyUsage(), ...parts });

/** @param {string[]} names */
const specifiers = (names) => usageOf({ specifiers: new Set(names) });

test('packageOf keeps both segments of a scope and drops the subpath', () => {
	assert.equal(packageOf('maplibre-gl'), 'maplibre-gl');
	assert.equal(packageOf('maplibre-gl/dist/maplibre-gl.css'), 'maplibre-gl');
	assert.equal(packageOf('@sveltejs/kit'), '@sveltejs/kit');
	assert.equal(packageOf('@sveltejs/kit/vite'), '@sveltejs/kit');
});

test('packageOf ignores what is not a package', () => {
	assert.equal(packageOf('./local'), null);
	assert.equal(packageOf('../up'), null);
	assert.equal(packageOf('/abs'), null);
	assert.equal(packageOf('$lib/types'), null);
	assert.equal(packageOf('node:fs'), null);
	assert.equal(packageOf('@scope'), null);
	assert.equal(packageOf(''), null);
});

// Every fixture below names a package this repo does NOT declare. `scripts/`
// is inside the scanned trees, so a fixture quoting a real one would answer
// for the build: the first draft of this suite used the real names and the
// mutation proof then reported three deleted packages as live.
test('scanSource reads every import form a bundler resolves', () => {
	const found = scanSource(
		[
			"import { thing } from '@fixture/scoped/sub';",
			"import 'fixture-side-effect/dist/x.css';",
			"const { lazy } = await import('fixture-dynamic');",
			"const req = require('fixture-require');",
			"@import 'fixture-css';",
			"export { x } from 'fixture-reexport';",
		].join('\n'),
	);
	assert.deepEqual(
		[...found.specifiers].sort(),
		[
			'@fixture/scoped',
			'fixture-css',
			'fixture-dynamic',
			'fixture-reexport',
			'fixture-require',
			'fixture-side-effect',
		],
	);
});

test('scanSource records the module scheme separately from the package', () => {
	const found = scanSource("import { readFileSync } from 'node:fs';");
	assert.deepEqual([...found.schemes], ['node']);
	assert.equal(found.specifiers.size, 0);
});

test('scanSource finds a package reached by node_modules path, not by import', () => {
	const found = scanSource(
		"export const UPSTREAM = join(REPO_ROOT, 'node_modules', 'fixture-by-path');",
	);
	assert.ok(found.nodeModulePaths.has('fixture-by-path'));
	const slashed = scanSource("readFileSync('node_modules/@fixture/by-path/font.woff2')");
	assert.ok(slashed.nodeModulePaths.has('@fixture/by-path'));
});

// The whole reason `docs/` is not scanned. A guard that read an ADR's prose as
// a claim about the build would have called all three of the § 786 deletions
// live — each was named in a doc that described it as how something worked.
test('a package merely NAMED in prose is not a use', () => {
	const found = scanSource(
		'`fixture-named` is configured in vite.config.ts and nothing imports it. ' +
			'The styling is fixture-css plus custom CSS.',
	);
	assert.equal(found.specifiers.size, 0);
});

// Disabling a plugin by commenting it out is the state this guard exists to
// find, so a commented import must not count as one — nor must a comment
// quoting an import, which is how the guard's own header would answer for it.
test('an import inside a comment is not a use', () => {
	for (const line of [
		"// import Icons from 'fixture-commented/vite';",
		"\t/// import Icons from 'fixture-commented/vite';",
		" * import { toPng } from 'fixture-commented';",
		"/* const x = require('fixture-commented'); */",
		"\tconst real = 1; // await import('fixture-commented')",
	]) {
		assert.equal(scanSource(line).specifiers.size, 0, line);
	}
	assert.equal(
		scanSource("// node_modules/fixture-commented is read by the generator").nodeModulePaths
			.size,
		0,
	);
});

test('a URL in a live line is not read as a line comment', () => {
	const found = scanSource("import x from 'fixture-url'; // https://example.com/a");
	assert.deepEqual([...found.specifiers], ['fixture-url']);
});

test('isScannable takes code anywhere and markdown only where mdsvex compiles it', () => {
	assert.equal(isScannable('apps/web/src/lib/x.ts'), true);
	assert.equal(isScannable('apps/web/src/app.css'), true);
	assert.equal(isScannable('apps/web/src/lib/C.svelte'), true);
	assert.equal(isScannable('apps/web/src/lib/learn/guides/a.md'), true);
	assert.equal(isScannable('apps/web/CLAUDE.md'), false);
	assert.equal(isScannable('apps/web/package.json'), false);
	assert.equal(isScannable('LICENSE'), false);
});

test('tsconfigTypes reads a types array out of a config carrying comments', () => {
	const types = tsconfigTypes('{\n\t// why\n\t"compilerOptions": { "types": ["node", "geojson"] }\n}');
	assert.deepEqual([...types].sort(), ['geojson', 'node']);
	assert.equal(tsconfigTypes('{ "compilerOptions": {} }').size, 0);
});

test('invokedCommands takes the command word, not a flag or a path fragment', () => {
	const words = invokedCommands(['"check": "svelte-kit sync && svelte-check --tsconfig ./x"']);
	assert.ok(words.has('svelte-check'));
	assert.ok(words.has('svelte-kit'));
	assert.ok(!words.has('tsconfig'));
});

test('readBy resolves a @types package through the module it types', () => {
	assert.equal(readBy('@types/geojson', specifiers(['geojson'])), 'types for `geojson`, which is imported');
	assert.ok(readBy('@types/node', usageOf({ schemes: new Set(['node']) })));
	assert.ok(readBy('@types/node', usageOf({ tsTypes: new Set(['node']) })));
	assert.equal(readBy('@types/node', emptyUsage()), null);
});

test('readBy separates a package read by path from one that is read by nothing', () => {
	assert.equal(
		readBy('material-symbols', usageOf({ nodeModulePaths: new Set(['material-symbols']) })),
		'read out of node_modules by path',
	);
	assert.equal(readBy('material-symbols', emptyUsage()), null);
});

/// Every INDIRECT entry satisfied, counted off the table rather than written
/// down, so adding a fifth entry does not fail every fixture below on the
/// stale-entry complaint it is not about.
/** @param {{ dir: string, deps: string[] }[]} manifests */
function withIndirect(manifests) {
	const byDir = new Map(manifests.map((m) => [m.dir, [...m.deps]]));
	for (const key of INDIRECT.keys()) {
		const [dir, dep] = key.split(':');
		if (!dir || !dep) continue;
		const deps = byDir.get(dir);
		if (deps) deps.push(dep);
		else byDir.set(dir, [dep]);
	}
	// A hoist pin needs a member declaring the package for it to pin.
	for (const [key, entry] of INDIRECT) {
		if (!entry.hoistPin) continue;
		const dep = key.split(':')[1];
		if (!dep) continue;
		for (const [dir, deps] of byDir) {
			if (dir !== '.' && !deps.includes(dep)) deps.push(dep);
		}
	}
	return [...byDir].map(([dir, deps]) => ({ dir, deps }));
}

const indirectBins = new Set(
	[...INDIRECT.values()].flatMap((e) => (e.bin ? [e.bin] : [])),
);

/// Everything the hoist-pinned packages need to read as used, so a fixture is
/// only ever failing on what it declares itself.
const indirectUsage = () =>
	usageOf({
		specifiers: new Set(
			[...INDIRECT].flatMap(([key, e]) => (e.hoistPin ? [key.split(':')[1] ?? ''] : [])),
		),
	});

/** @param {Partial<Parameters<typeof checkDeadDependencies>[0]>} over */
function run(over) {
	const manifests = withIndirect(over.manifests ?? [{ dir: '.', deps: [] }]);
	const usage = over.usage ?? emptyUsage();
	for (const s of indirectUsage().specifiers) usage.specifiers.add(s);
	return checkDeadDependencies({
		manifests,
		usage,
		outside: over.outside ?? emptyUsage(),
		commands: new Set([...indirectBins, ...(over.commands ?? [])]),
	});
}

test('a declared package nothing reads is reported, by name and by manifest', () => {
	const { errors } = run({
		manifests: [
			{ dir: '.', deps: [] },
			{ dir: 'apps/web', deps: ['unplugin-icons'] },
		],
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0] ?? '', /apps\/web:unplugin-icons/);
	assert.match(errors[0] ?? '', /apps\/web\/package\.json/);
});

test('a package something imports passes', () => {
	const { errors, ok } = run({
		manifests: [
			{ dir: '.', deps: [] },
			{ dir: 'apps/web', deps: ['marked'] },
		],
		usage: specifiers(['marked']),
	});
	assert.deepEqual(errors, []);
	assert.ok(ok.includes('apps/web:marked -> imported'), ok.join('\n'));
});

test('an INDIRECT binary entry passes while the binary is still invoked', () => {
	const { errors, ok } = run({ manifests: [{ dir: '.', deps: [] }] });
	assert.deepEqual(errors, []);
	assert.ok(ok.some((line) => line.startsWith('apps/web:tsx -> ')));
});

// An allowlist that cannot go stale is the difference between this and a
// suppression file: when the last caller of `tsx` goes, so does the reason.
test('an INDIRECT binary entry fails once nothing runs the binary', () => {
	const { errors } = checkDeadDependencies({
		manifests: withIndirect([{ dir: '.', deps: [] }]),
		usage: indirectUsage(),
		outside: emptyUsage(),
		commands: new Set([...indirectBins].filter((b) => b !== 'tsx')),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0] ?? '', /no package\.json script and no workflow runs `tsx`/);
});

test('an INDIRECT hoist pin fails once no workspace member declares the package', () => {
	const { errors } = checkDeadDependencies({
		manifests: withIndirect([{ dir: '.', deps: [] }]).map((m) =>
			m.dir === '.' ? m : { dir: m.dir, deps: m.deps.filter((d) => d !== 'svelte') },
		),
		usage: indirectUsage(),
		outside: emptyUsage(),
		commands: new Set(indirectBins),
	});
	assert.ok(errors.some((e) => /`\.:svelte`|\.:svelte —/.test(e)), errors.join('\n'));
	assert.ok(errors.some((e) => /nothing\s+to pin/.test(e)), errors.join('\n'));
});

test('an INDIRECT entry for a package no manifest declares any more is stale', () => {
	const { errors } = checkDeadDependencies({
		manifests: [{ dir: '.', deps: [] }],
		usage: emptyUsage(),
		outside: emptyUsage(),
		commands: new Set(indirectBins),
	});
	assert.equal(errors.length, INDIRECT.size);
	for (const key of INDIRECT.keys()) {
		assert.ok(errors.some((e) => e.includes(key)), key);
	}
});

// `npm install html-to-image` from the repo root, which is how 10b5ec519 put
// the same package in two manifests at once.
test('a root declaration only a workspace member reads is reported as redundant', () => {
	const { errors } = run({
		manifests: [
			{ dir: '.', deps: ['html-to-image'] },
			{ dir: 'apps/web', deps: ['html-to-image'] },
		],
		usage: specifiers(['html-to-image']),
		outside: emptyUsage(),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0] ?? '', /^\.:html-to-image/);
});

test('a root declaration something outside the members reads is not redundant', () => {
	const { errors } = run({
		manifests: [
			{ dir: '.', deps: ['html-to-image'] },
			{ dir: 'apps/web', deps: ['html-to-image'] },
		],
		usage: specifiers(['html-to-image']),
		outside: specifiers(['html-to-image']),
	});
	assert.deepEqual(errors, []);
});

test('reading no manifest at all is a failure, not a vacuous pass', () => {
	const { errors } = checkDeadDependencies({
		manifests: [],
		usage: emptyUsage(),
		outside: emptyUsage(),
		commands: new Set(),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0] ?? '', /checked nothing/);
});

test('declaredDeps and workspaceDirs read the committed root manifest', () => {
	const text = readFileSync(join(REPO_ROOT, 'package.json'), 'utf-8');
	assert.deepEqual(workspaceDirs(text), ['apps/web', 'apps/backend']);
	assert.ok(declaredDeps(text).includes('svelte'));
});

// The committed tree, through the real walk. Last, so a genuine dead
// dependency reads as one rather than as a broken guard.
test('the committed tree declares no dependency nothing reads', () => {
	const out = execFileSync('node', [join(REPO_ROOT, 'scripts', 'check_dead_dependencies.mjs')], {
		cwd: REPO_ROOT,
		encoding: 'utf8',
	});
	assert.match(out, /dependency declaration\(s\) across 3 manifest\(s\)/);
});

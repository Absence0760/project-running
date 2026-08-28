import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	NPM_LOCK,
	PACKAGE_JSON,
	PNPM_LOCK,
	checkAll,
	checkDeclarations,
	checkResolutions,
	flattenOverrides,
	parseLockOverrides,
	parseNpmResolutions,
	parsePnpmResolutions,
	parsePnpmSnapshotEdges,
	parseVersion,
	pinTarget,
	satisfies,
} from './check_pnpm_overrides.mjs';

const PINS = {
	cookie: '^1.0.2',
	devalue: '^5.8.1',
	'@sveltejs/kit>cookie': '^1.0.2',
};

/** @typedef {Record<string, string>} PinMap */

/** @param {{ pnpmOverrides?: PinMap, overrides?: Record<string, unknown> }} [opts] */
function pkg({ pnpmOverrides = PINS, overrides } = {}) {
	return {
		pnpm: { overrides: pnpmOverrides },
		overrides: overrides ?? { cookie: '^1.0.2', devalue: '^5.8.1', '@sveltejs/kit': { cookie: '^1.0.2' } },
	};
}

/** @param {{ overrides?: PinMap | null, packages?: string[] }} [opts] */
function lock({ overrides = PINS, packages = ['cookie@1.1.1', 'devalue@5.9.1', "'@sveltejs/kit@2.70.3'"] } = {}) {
	const overrideLines =
		overrides === null
			? ''
			: Object.entries(overrides)
					.map(([k, v]) => `  ${k.includes('>') || k.startsWith('@') ? `'${k}'` : k}: ${v}`)
					.join('\n');
	return [
		"lockfileVersion: '9.0'",
		'',
		'settings:',
		'  autoInstallPeers: true',
		'',
		...(overrides === null ? [] : ['overrides:', overrideLines, '']),
		'importers:',
		'',
		'  .: {}',
		'',
		'packages:',
		'',
		...packages.map((p) => `  ${p}:\n    resolution: {integrity: sha512-x==}`),
		'',
		'snapshots:',
		'',
		'  cookie@1.1.1: {}',
		'',
		"  '@sveltejs/kit@2.70.3':",
		'    dependencies:',
		'      cookie: 1.1.1',
		'',
	].join('\n');
}

/** @param {Record<string, string>} [entries] */
function npmLock(entries = { 'node_modules/cookie': '1.1.1', 'node_modules/devalue': '5.8.1' }) {
	return {
		packages: Object.fromEntries([
			['', { name: 'run-app-root' }],
			...Object.entries(entries).map(([path, version]) => [path, { version }]),
		]),
	};
}

test('parseLockOverrides reads the block, unquoting the keys pnpm had to quote', () => {
	const found = parseLockOverrides(lock());
	assert.ok(found, 'the block must parse, or the checks below assert nothing');
	assert.equal(found.get('cookie'), '^1.0.2');
	assert.equal(found.get('@sveltejs/kit>cookie'), '^1.0.2');
	assert.equal(found.size, 3);
});

// The #812 regression itself: the block is gone, not empty. Null and an empty
// Map have to stay distinguishable, because the messages differ.
test('parseLockOverrides returns null when the block is absent, not an empty map', () => {
	assert.equal(parseLockOverrides(lock({ overrides: null })), null);
	assert.deepEqual(parseLockOverrides('lockfileVersion: \'9.0\'\n\noverrides:\n\nimporters:\n'), new Map());
});

test('parseLockOverrides stops at the next top-level key', () => {
	const text = ["overrides:", '  cookie: ^1.0.2', '', 'importers:', '  .:', '    devalue: nope'].join('\n');
	const found = parseLockOverrides(text);
	assert.ok(found, 'the block must parse, or the check below asserts nothing');
	assert.deepEqual([...found.keys()], ['cookie']);
});

test('parsePnpmResolutions reads name@version, scoped names included', () => {
	const found = parsePnpmResolutions(lock({ packages: ['cookie@1.1.1', "'@sveltejs/kit@2.70.3'", "'@types/node@26.2.0'"] }));
	assert.deepEqual(
		found.map((r) => `${r.name}|${r.version}`),
		['cookie|1.1.1', '@sveltejs/kit|2.70.3', '@types/node|26.2.0'],
	);
});

test('parsePnpmResolutions ignores the snapshots section, so a version is counted once', () => {
	const found = parsePnpmResolutions(lock({ packages: ['cookie@1.1.1'] }));
	assert.equal(found.filter((r) => r.name === 'cookie').length, 1);
});

// The nested copy is the shape `@sveltejs/kit>cookie` exists to reach, so it
// must not be skipped for sitting below the top level.
test('parseNpmResolutions walks to the LAST node_modules segment, so nested copies count', () => {
	const found = parseNpmResolutions(
		npmLock({
			'node_modules/cookie': '1.1.1',
			'node_modules/@sveltejs/kit/node_modules/cookie': '0.6.0',
			'apps/web/node_modules/devalue': '5.8.1',
		}),
	);
	assert.deepEqual(
		found.map((r) => `${r.name}@${r.version}`).sort(),
		['cookie@0.6.0', 'cookie@1.1.1', 'devalue@5.8.1'],
	);
});

test('parseNpmResolutions skips the root entry and anything with no version', () => {
	assert.deepEqual(parseNpmResolutions({ packages: { '': { name: 'root' }, 'node_modules/x': {} } }), []);
	assert.deepEqual(parseNpmResolutions(null), []);
});

test("flattenOverrides normalises npm's nested spelling onto pnpm's flat one", () => {
	const { flat, problems } = flattenOverrides({
		cookie: '^1.0.2',
		'@sveltejs/kit': { cookie: '^1.0.2', devalue: '^5.8.1' },
	});
	assert.deepEqual(problems, []);
	assert.deepEqual([...flat.entries()].sort(), [
		['@sveltejs/kit>cookie', '^1.0.2'],
		['@sveltejs/kit>devalue', '^5.8.1'],
		['cookie', '^1.0.2'],
	]);
});

test('flattenOverrides reports npm\'s "." parent-version key rather than dropping it', () => {
	const { flat, problems } = flattenOverrides({ foo: { '.': '1.0.0', bar: '^2.0.0' } });
	assert.deepEqual([...flat.keys()], ['foo>bar']);
	assert.equal(problems.length, 1);
	assert.match(problems[0], /pnpm has no spelling/);
});

test('pinTarget splits on the LAST > and drops a parent range', () => {
	assert.deepEqual(pinTarget('cookie'), { target: 'cookie', parent: null });
	assert.deepEqual(pinTarget('@sveltejs/kit>cookie'), { target: 'cookie', parent: '@sveltejs/kit' });
	assert.deepEqual(pinTarget('foo>bar>baz'), { target: 'baz', parent: 'foo>bar' });
	assert.deepEqual(pinTarget('foo@1>bar'), { target: 'bar', parent: 'foo' });
});

test('parseVersion accepts prerelease and build metadata, rejects anything else', () => {
	const plain = parseVersion('1.2.3');
	const prerelease = parseVersion('1.2.3-beta.1');
	const build = parseVersion('1.2.3+build');
	assert.ok(plain);
	assert.ok(prerelease);
	assert.ok(build);
	assert.equal(plain.patch, 3);
	assert.equal(prerelease.prerelease, 'beta.1');
	assert.equal(build.prerelease, null);
	assert.equal(parseVersion('1.2'), null);
	assert.equal(parseVersion('https://example.test/x.tgz'), null);
});

test('satisfies implements caret for major, 0.minor and 0.0.patch separately', () => {
	assert.equal(satisfies('1.1.1', '^1.0.2').ok, true);
	assert.equal(satisfies('1.0.1', '^1.0.2').ok, false);
	assert.equal(satisfies('2.0.0', '^1.0.2').ok, false);
	assert.equal(satisfies('0.6.9', '^0.6.4').ok, true);
	assert.equal(satisfies('0.7.0', '^0.6.4').ok, false);
	assert.equal(satisfies('0.0.5', '^0.0.5').ok, true);
	assert.equal(satisfies('0.0.6', '^0.0.5').ok, false);
});

test('satisfies implements tilde, >= and exact', () => {
	assert.equal(satisfies('1.2.9', '~1.2.3').ok, true);
	assert.equal(satisfies('1.3.0', '~1.2.3').ok, false);
	assert.equal(satisfies('9.9.9', '>=1.2.3').ok, true);
	assert.equal(satisfies('1.2.2', '>=1.2.3').ok, false);
	assert.equal(satisfies('1.2.3', '1.2.3').ok, true);
	assert.equal(satisfies('1.2.4', '=1.2.3').ok, false);
});

// A range the checker cannot read must not report success — that is the
// vacuous pass the whole guard is written against.
test('satisfies reports an unreadable range as unsupported, never as satisfied', () => {
	assert.equal(satisfies('1.2.3', '1.x').unsupported, true);
	assert.equal(satisfies('1.2.3', '>=1.0.0 <2.0.0').unsupported, true);
	assert.equal(satisfies('1.2.3', 'npm:other@^1.0.0').unsupported, true);
	assert.equal(satisfies('1.2.3', '*').unsupported, true);
});

test('satisfies narrows to exact equality when either side carries a prerelease', () => {
	assert.equal(satisfies('1.2.3-beta.1', '^1.0.0').ok, false);
	assert.equal(satisfies('1.2.3-beta.1', '1.2.3-beta.1').ok, true);
});

test('a version the tree could not resolve to semver is reported, not assumed fine', () => {
	const v = satisfies('file:../local', '^1.0.0');
	assert.equal(v.ok, false);
	assert.ok(v.reason, 'a version the parser rejected must say so, not just fail silently');
	assert.match(v.reason, /not a plain semver version/);
});

test('the committed tree passes every check', () => {
	const result = checkAll(
		JSON.parse(readFileSync(PACKAGE_JSON, 'utf-8')),
		readFileSync(PNPM_LOCK, 'utf-8'),
		JSON.parse(readFileSync(NPM_LOCK, 'utf-8')),
	);
	assert.deepEqual(result.errors, []);
	assert.ok(result.declared.size > 0, 'the guard must be checking a non-empty pin set');
	assert.ok(result.resolutions.length > 100, 'both lockfile trees must have been parsed');
});

// The #812 reconstruction, as a unit case rather than only as a scratch-tree
// experiment: the block deleted, everything else untouched.
test('a lockfile with the overrides block deleted fails, naming the frozen-install abort', () => {
	const { errors } = checkDeclarations(pkg(), lock({ overrides: null }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /NO top-level `overrides:` block/);
	assert.match(errors[0], /ERR_PNPM_LOCKFILE_CONFIG_MISMATCH/);
	assert.match(errors[0], /pnpm install --lockfile-only/);
});

test('a lockfile whose overrides block dropped one entry fails naming that entry', () => {
	const partial = { cookie: '^1.0.2', devalue: '^5.8.1' };
	const { errors } = checkDeclarations(pkg(), lock({ overrides: partial }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /@sveltejs\/kit>cookie/);
	assert.match(errors[0], /missing from pnpm-lock.yaml overrides/);
});

test('a lockfile pinning a different range than package.json fails with both values', () => {
	const stale = { ...PINS, cookie: '^0.6.0' };
	const { errors } = checkDeclarations(pkg(), lock({ overrides: stale }));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /package.json pnpm.overrides says \^1\.0\.2, pnpm-lock.yaml overrides says \^0\.6\.0/);
});

test('an empty or missing pnpm.overrides is an error, not a vacuous pass', () => {
	for (const p of [{}, { pnpm: {} }, { pnpm: { overrides: {} } }]) {
		const { errors } = checkDeclarations(p, lock());
		assert.equal(errors.length, 1);
		assert.match(errors[0], /declares no `pnpm.overrides`/);
	}
});

test('the two package.json declarations disagreeing is reported in the flat spelling', () => {
	const { errors } = checkDeclarations(
		pkg({ overrides: { cookie: '^1.0.2', devalue: '^5.8.1' } }),
		lock(),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /two override declarations disagree/);
	assert.match(errors[0], /@sveltejs\/kit>cookie/);
});

test('declaring pnpm.overrides with no npm-style block fails, because npm ci reads only the latter', () => {
	const { errors } = checkDeclarations({ pnpm: { overrides: PINS } }, lock());
	assert.equal(errors.length, 1);
	assert.match(errors[0], /no top-level `overrides`/);
	assert.match(errors[0], /npm ci/);
});

// The half a frozen install can never catch: the block is present and correct,
// and the tree resolved around it anyway.
test('a declared override the tree resolved around fails, in either lockfile', () => {
	const declared = new Map([['cookie', '^1.0.2']]);
	const pnpmSide = checkResolutions(declared, [{ name: 'cookie', version: '0.6.0', where: 'pnpm-lock.yaml', parent: null }]);
	assert.equal(pnpmSide.errors.length, 1);
	assert.match(pnpmSide.errors[0], /declared and NOT in effect/);
	assert.match(pnpmSide.errors[0], /cookie@0\.6\.0 \(pnpm-lock\.yaml\)/);

	const npmSide = checkResolutions(declared, [
		{ name: 'cookie', version: '1.1.1', where: 'pnpm-lock.yaml', parent: null },
		{ name: 'cookie', version: '0.6.0', where: 'package-lock.json', parent: null },
	]);
	assert.equal(npmSide.errors.length, 1);
	assert.match(npmSide.errors[0], /cookie@0\.6\.0 \(package-lock\.json\)/);
});

test('a pinned package absent from both trees is an error, not a silent skip', () => {
	const { errors } = checkResolutions(new Map([['cookie', '^1.0.2']]), [
		{ name: 'devalue', version: '5.9.1', where: 'pnpm-lock.yaml', parent: null },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /appears in neither lockfile's package tree/);
});

test('a scoped pin whose parent is gone is reported, because it reaches nothing', () => {
	const { errors } = checkResolutions(new Map([['@sveltejs/kit>cookie', '^1.0.2']]), [
		{ name: 'cookie', version: '1.1.1', where: 'pnpm-lock.yaml', parent: null },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /scopes a pin to `@sveltejs\/kit`, which is in neither lockfile/);
});

test('an unevaluatable range is an error rather than a pass', () => {
	const { errors } = checkResolutions(new Map([['cookie', '>=1.0.0 <2.0.0']]), [
		{ name: 'cookie', version: '1.1.1', where: 'pnpm-lock.yaml', parent: null },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /cannot evaluate/);
});

test('an empty resolution set is an error, so a broken parser cannot report success', () => {
	const { errors } = checkResolutions(new Map([['cookie', '^1.0.2']]), []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /parser matched nothing/);
});

test('a bare pin reaches every copy; a scoped one reaches only its parent\'s', () => {
	// The bare pin covers both copies and fails on the 1.0.5 one. The scoped
	// pin's subject is what @sveltejs/kit resolved — 1.1.1 per the snapshot
	// edge — so it passes. Enforcing it against every copy of the NAME accuses
	// a sibling the override never touched: decisions § 774.
	const declared = new Map([
		['cookie', '^1.1.0'],
		['@sveltejs/kit>cookie', '^1.1.0'],
	]);
	const resolutions = [
		{ name: 'cookie', version: '1.0.5', where: 'pnpm-lock.yaml', parent: null },
		{ name: 'cookie', version: '1.1.1', where: 'pnpm-lock.yaml', parent: null },
		{ name: '@sveltejs/kit', version: '2.70.3', where: 'pnpm-lock.yaml', parent: null },
	];
	const edges = new Map([['@sveltejs/kit', new Map([['cookie', new Set(['1.1.1'])]])]]);

	const { errors, ok } = checkResolutions(declared, resolutions, edges);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`cookie` pins `\^1\.1\.0`/);
	assert.match(errors[0], /cookie@1\.0\.5/);
	assert.deepEqual(ok, ['@sveltejs/kit>cookie resolves to 1.1.1 across 1 copy/copies, satisfying ^1.1.0']);
});

test('a scoped pin does not accuse a copy under a different parent', () => {
	// The reproduction: `@sveltejs/kit>cookie` used to fail on express's own
	// nested cookie@0.6.0, which the override never reached. Latent on the
	// committed tree only because package.json declares a bare `cookie` pin
	// beside the scoped one — dropping that, a reasonable change once
	// SvelteKit bumps, turns it on.
	const resolutions = parseNpmResolutions({
		packages: {
			'': { version: '1.0.0' },
			'node_modules/@sveltejs/kit': { version: '2.70.3' },
			'node_modules/@sveltejs/kit/node_modules/cookie': { version: '1.1.1' },
			'node_modules/express': { version: '5.0.0' },
			'node_modules/express/node_modules/cookie': { version: '0.6.0' },
		},
	});
	const { errors, ok } = checkResolutions(new Map([['@sveltejs/kit>cookie', '^1.0.2']]), resolutions);

	assert.deepEqual(errors, []);
	assert.deepEqual(ok, ['@sveltejs/kit>cookie resolves to 1.1.1 across 1 copy/copies, satisfying ^1.0.2']);
});

test('a scoped pin still reaches the hoisted copy when the parent has no nested one', () => {
	// npm dedupes an override into the top level whenever it can, which is the
	// state the committed package-lock.json is in — narrowing to nested copies
	// alone would check the pin against nothing.
	const resolutions = parseNpmResolutions({
		packages: {
			'node_modules/@sveltejs/kit': { version: '2.70.3' },
			'node_modules/cookie': { version: '0.6.0' },
		},
	});
	const { errors } = checkResolutions(new Map([['@sveltejs/kit>cookie', '^1.0.2']]), resolutions);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /declared and NOT in effect/);
	assert.match(errors[0], /cookie@0\.6\.0/);
});

test('a scoped pin whose parent resolves no copy of the target is reported', () => {
	const resolutions = parseNpmResolutions({
		packages: {
			'node_modules/@sveltejs/kit': { version: '2.70.3' },
			'node_modules/express/node_modules/cookie': { version: '1.1.1' },
		},
	});
	const { errors } = checkResolutions(new Map([['@sveltejs/kit>cookie', '^1.0.2']]), resolutions);

	assert.equal(errors.length, 1);
	assert.match(errors[0], /resolves no `cookie` in either lockfile/);
});

test('a scoped pin over a resolving parent is not checked against an empty snapshots graph', () => {
	const { errors } = checkResolutions(
		new Map([['@sveltejs/kit>cookie', '^1.0.2']]),
		[
			{ name: 'cookie', version: '1.1.1', where: 'pnpm-lock.yaml', parent: null },
			{ name: '@sveltejs/kit', version: '2.70.3', where: 'pnpm-lock.yaml', parent: null },
		],
		new Map(),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`snapshots:` graph parsed as empty/);
});

test('parseNpmResolutions names the package that encloses a nested copy', () => {
	assert.deepEqual(
		parseNpmResolutions({
			packages: {
				'node_modules/cookie': { version: '1.1.1' },
				'apps/web/node_modules/cookie': { version: '1.1.1' },
				'node_modules/@sveltejs/kit/node_modules/cookie': { version: '0.6.0' },
			},
		}).map((r) => [r.name, r.parent]),
		[
			['cookie', null],
			['cookie', null],
			['cookie', '@sveltejs/kit'],
		],
	);
});

test('parsePnpmSnapshotEdges reads the dependency graph, peer suffixes stripped', () => {
	const edges = parsePnpmSnapshotEdges(
		[
			'packages:',
			'',
			'  cookie@1.1.1:',
			'',
			'snapshots:',
			'',
			"  '@sveltejs/kit@2.70.3(svelte@5.56.10)':",
			'    dependencies:',
			'      cookie: 1.1.1',
			'      devalue: 5.9.1(svelte@5.56.10)',
			'    optionalDependencies:',
			'      undici: 7.29.0',
			'',
			'  cookie@1.1.1: {}',
			'',
		].join('\n'),
	);
	assert.deepEqual(
		[...(edges.get('@sveltejs/kit') ?? [])].map(([k, v]) => [k, [...v]]),
		[
			['cookie', ['1.1.1']],
			['devalue', ['5.9.1']],
			['undici', ['7.29.0']],
		],
	);
	assert.equal(edges.has('cookie'), false);
});

test('the committed pnpm-lock.yaml carries the edges the scoped pins are read through', () => {
	const edges = parsePnpmSnapshotEdges(readFileSync(PNPM_LOCK, 'utf-8'));
	assert.ok(edges.size > 50, `only ${edges.size} parents parsed from snapshots:`);
	const kit = edges.get('@sveltejs/kit');
	assert.ok(kit, 'no @sveltejs/kit snapshot parsed, so both scoped pins would be unnarrowed');
	assert.ok(kit.has('cookie') && kit.has('devalue'));
});

test('checkAll composes both halves and passes on a well-formed pair', () => {
	const { errors, ok } = checkAll(pkg(), lock(), npmLock());
	assert.deepEqual(errors, []);
	assert.ok(ok.some((line) => line.startsWith('cookie resolves to 1.1.1')));
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { isTruthyFlagValue } from './env_flag';

test('isTruthyFlagValue — accepts every affirmative literal', () => {
	for (const v of ['1', 'true', 'yes', 'on']) {
		assert.equal(isTruthyFlagValue(v), true, `${v} should enable`);
	}
});

test('isTruthyFlagValue — affirmatives are case-insensitive', () => {
	for (const v of ['TRUE', 'True', 'YES', 'On', 'ON']) {
		assert.equal(isTruthyFlagValue(v), true, `${v} should enable`);
	}
});

test('isTruthyFlagValue — surrounding whitespace is trimmed', () => {
	for (const v of [' true ', '\t1', 'yes\n', '  on  ']) {
		assert.equal(isTruthyFlagValue(v), true, `"${v}" should enable`);
	}
});

test('isTruthyFlagValue — fail-closed for unset / empty', () => {
	for (const v of [null, undefined, '', '   ']) {
		assert.equal(isTruthyFlagValue(v), false, `${String(v)} should stay off`);
	}
});

test('isTruthyFlagValue — fail-closed for negatives + junk', () => {
	for (const v of ['0', 'false', 'no', 'off', 'enabled', 'y', 't', '2', 'truthy']) {
		assert.equal(isTruthyFlagValue(v), false, `${v} should stay off`);
	}
});

// Source-level guards. The parse above is only canonical while every gate
// actually routes through it: before decisions § 709 four modules carried
// their own copy of the affirmative chain, and mobile's narrowest copy
// accepted two of the four values, so the same documented flag meant
// different things on different surfaces.

const CORE_DIR = import.meta.dirname;
const LIB_ROOT = resolve(CORE_DIR, '..');
const SRC_ROOT = resolve(CORE_DIR, '..', '..');
const WEB_ROOT = resolve(CORE_DIR, '..', '..', '..');

/// The shape of the copied parse: a comparison chain opening on `'1'` and
/// naming one of the two literals only a full copy carries.
const CHAIN_HEAD = /===\s*'1'\s*\|\|/;
const CHAIN_TAIL = /===\s*'(?:yes|on)'/;

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const e of readdirSync(dir, { withFileTypes: true })) {
		const p = resolve(dir, e.name);
		if (e.isDirectory()) {
			if (e.name === 'node_modules') continue;
			sourceFiles(p, out);
		} else if (/\.(ts|mjs|svelte)$/.test(e.name)) {
			out.push(p);
		}
	}
	return out;
}

test('env_flag.ts is the only module that spells the affirmative set out', () => {
	const canonical = resolve(CORE_DIR, 'env_flag.ts');
	const canonicalSource = readFileSync(canonical, 'utf-8');
	assert.ok(
		CHAIN_HEAD.test(canonicalSource) && CHAIN_TAIL.test(canonicalSource),
		'env_flag.ts no longer matches the chain pattern this guard looks for — ' +
			'the parse was rewritten and the guard is now checking nothing.',
	);

	// `scripts/` is walked because it was outside every guard this repo runs —
	// including this one — and carried a full inline copy of the set for as
	// long as it existed (decisions § 752). `.mjs` for the same reason: the
	// build-env guards there are the flag-reading code that is not `.ts`.
	const offenders = [
		...sourceFiles(SRC_ROOT),
		...sourceFiles(resolve(WEB_ROOT, 'lambda')),
		...sourceFiles(resolve(WEB_ROOT, 'scripts')),
	]
		.filter((p) => p !== canonical && !/\.test\.(ts|mjs)$/.test(p))
		.filter((p) => {
			const s = readFileSync(p, 'utf-8');
			return CHAIN_HEAD.test(s) && CHAIN_TAIL.test(s);
		})
		.map((p) => relative(WEB_ROOT, p))
		.sort();

	assert.deepEqual(
		offenders,
		[],
		`Inline copy of the feature-flag affirmative set in: ${offenders.join(', ')}. ` +
			`Import isTruthyFlagValue from core/env_flag instead — a second copy is how ` +
			`the accepted values drift apart between gates (decisions § 709).`,
	);
});

test('every *_flag module routes its parse through isTruthyFlagValue', () => {
	const flagFiles = sourceFiles(LIB_ROOT)
		.filter((p) => /_flag\.ts$/.test(p) && !p.endsWith('env_flag.ts'));
	assert.ok(
		flagFiles.length >= 8,
		`expected the *_flag.ts gate modules to be discoverable, found ${flagFiles.length}`,
	);

	// A gate may reach the canonical parse through one named delegate — the two
	// flags whose parser lives inside a TS<->Dart parity pair do, so the pair
	// keeps owning its own flag while the parse stays single-sourced.
	const routes = (file: string, depth: number): boolean => {
		const source = readFileSync(file, 'utf-8');
		if (source.includes('isTruthyFlagValue')) return true;
		if (depth === 0) return false;
		return [...source.matchAll(/from '(\.[^']+)'/g)].some((m) => {
			const target = resolve(file, '..', `${m[1]}.ts`);
			return existsSync(target) && routes(target, depth - 1);
		});
	};

	const offenders = flagFiles
		.filter((p) => !routes(p, 1))
		.map((p) => relative(WEB_ROOT, p))
		.sort();

	assert.deepEqual(
		offenders,
		[],
		`Gate module(s) not routed through isTruthyFlagValue: ${offenders.join(', ')}.`,
	);
});

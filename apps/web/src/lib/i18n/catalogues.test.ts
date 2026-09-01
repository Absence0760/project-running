// Which catalogue each shipped locale actually reaches. Invocation:
//   npx tsx --test src/lib/i18n/catalogues.test.ts
//
// `messages_parity.test.ts` loads every locale through this registry and
// checks the KEY SET, which two locales sharing one catalogue satisfy
// perfectly — every key present, every placeholder faithful, no test
// anywhere the wiser. That is not hypothetical: `pt-PT` was added to the
// registry as a one-line copy of the `pt-BR` row (decisions § 755), and
// the whole point of shipping it was that a Lisbon reader stops being
// answered in Brazilian. A mistyped path there is a locale that ships,
// passes, and says the wrong words.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { CATALOGUE_LOADERS } from './catalogues';
import { SUPPORTED_LOCALES, type Locale } from './locale';

async function catalogueOnDisk(loc: Locale): Promise<Record<string, string>> {
	const mod = (await import(`./locales/${loc}`)) as Record<string, unknown>;
	const dict = (mod.messages ?? mod.en) as Record<string, string> | undefined;
	assert.ok(dict, `locales/${loc}.ts exports neither 'messages' nor 'en'`);
	return dict;
}

test('every supported locale has a loader and no loader is unreachable', () => {
	assert.deepEqual(
		Object.keys(CATALOGUE_LOADERS).sort(),
		[...SUPPORTED_LOCALES].sort(),
		'CATALOGUE_LOADERS and SUPPORTED_LOCALES must name the same set',
	);
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: the loader resolves locales/${loc}, not another locale's file`, async () => {
		const loaded = await CATALOGUE_LOADERS[loc]();
		const onDisk = await catalogueOnDisk(loc);
		// ESM caches module namespaces, so the object the loader yields is
		// the SAME object the direct import yields when — and only when —
		// the loader names the right file.
		assert.equal(
			loaded as unknown,
			onDisk as unknown,
			`CATALOGUE_LOADERS['${loc}'] does not resolve locales/${loc}.ts`,
		);
	});
}

test('no two locales resolve the same catalogue', async () => {
	const seen = new Map<unknown, Locale>();
	for (const loc of SUPPORTED_LOCALES) {
		const dict = await CATALOGUE_LOADERS[loc]();
		const prior = seen.get(dict as unknown);
		assert.equal(
			prior,
			undefined,
			`${loc} and ${prior} share one catalogue object — one of them ships the other's words`,
		);
		seen.set(dict as unknown, loc);
	}
});

test('the two Portuguese catalogues differ in the words they were split over', async () => {
	// Object identity alone would survive a `pt-PT.ts` that is a verbatim
	// re-export of the Brazilian strings. The reason the locale exists is
	// lexical, so measure the lexicon: the accessibility skip link is
	// `Pular` in Brazil and `Saltar` in Portugal (decisions § 755), and
	// `Definições` is the European word for the Settings screen.
	const br = (await CATALOGUE_LOADERS['pt-BR']()) as Record<string, string>;
	const pt = (await CATALOGUE_LOADERS['pt-PT']()) as Record<string, string>;
	const differing = Object.keys(br).filter((k) => br[k] !== pt[k]);
	assert.ok(
		differing.length > 100,
		`only ${differing.length} strings differ between pt-BR and pt-PT — the European catalogue looks like a copy`,
	);
	for (const [key, brWord, ptWord] of [
		['shell.skipToMain', 'Pular', 'Saltar'],
		['prefs.kicker', 'Configurações', 'Definições'],
	] as const) {
		assert.ok(br[key]?.includes(brWord), `pt-BR ${key} no longer says ${brWord}`);
		assert.ok(pt[key]?.includes(ptWord), `pt-PT ${key} must say ${ptWord}, not ${brWord}`);
	}
});

test('each loader names its own locale file in source', () => {
	// The runtime checks above catch a mis-wired loader; this catches the
	// shape that makes one easy — a row copied from its neighbour — at the
	// point a reader reviews the diff.
	const source = readFileSync(resolve('src/lib/i18n/catalogues.ts'), 'utf-8');
	for (const loc of SUPPORTED_LOCALES) {
		if (loc === 'en') continue; // resolved synchronously from the static import
		const row = new RegExp(
			`'?${loc}'?\\s*:\\s*\\(\\)\\s*=>\\s*import\\('\\./locales/${loc}'\\)`,
		);
		assert.match(source, row, `the ${loc} loader must import ./locales/${loc}`);
	}
});

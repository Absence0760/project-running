import { test } from 'node:test';
import assert from 'node:assert/strict';
import { en } from './locales/en';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// `satisfies Messages` already enforces key parity at compile time; this
// guards it at runtime too and — by iterating SUPPORTED_LOCALES through
// the typed loader registry rather than a hard-coded list — guarantees
// that *every* shipped locale is loadable, complete, non-empty, and
// preserves the English {placeholder} set. Adding a locale to
// SUPPORTED_LOCALES (with its CATALOGUE_LOADERS entry) automatically
// brings it under this test; a forgotten/empty/placeholder-drifted
// catalogue fails here.

const enRecord = en as Record<string, string>;
const enKeys = Object.keys(en).sort();

function placeholders(s: string): string[] {
	return (s.match(/\{[a-zA-Z0-9_]+\}/g) ?? []).sort();
}

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: catalogue is loadable, complete, non-empty, placeholder-faithful`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		assert.deepEqual(Object.keys(dict).sort(), enKeys, `${loc} key set differs from en`);
		for (const key of enKeys) {
			assert.ok(dict[key].trim().length > 0, `${loc}.${key} is empty`);
			assert.deepEqual(
				placeholders(dict[key]),
				placeholders(enRecord[key]),
				`${loc}.${key} placeholder mismatch`,
			);
		}
	});
}

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { en } from './locales/en';
import { messages as de } from './locales/de';
import { messages as fr } from './locales/fr';
import { messages as es } from './locales/es';
import { messages as ja } from './locales/ja';
import { messages as ptBR } from './locales/pt-BR';

// `satisfies Messages` already enforces key parity at compile time; this
// guards it at runtime too (a hand-edited catalogue, a merge that drops a
// key, or a stray entry surfaces here) and proves every shipped locale is
// actually present and non-empty. The placeholder check catches the most
// common translation bug: a translator dropping or renaming a {param}.

const LOCALES: Record<string, Record<string, string>> = { de, fr, es, ja, 'pt-BR': ptBR };
const enKeys = Object.keys(en).sort();

function placeholders(s: string): string[] {
	return (s.match(/\{[a-zA-Z0-9_]+\}/g) ?? []).sort();
}

for (const [name, dict] of Object.entries(LOCALES)) {
	test(`${name} defines exactly the English key set`, () => {
		assert.deepEqual(Object.keys(dict).sort(), enKeys);
	});

	test(`${name} has no empty translations`, () => {
		for (const [key, value] of Object.entries(dict)) {
			assert.ok(value.trim().length > 0, `${name}.${key} is empty`);
		}
	});

	test(`${name} preserves every {placeholder} from English`, () => {
		for (const key of enKeys) {
			assert.deepEqual(
				placeholders(dict[key]),
				placeholders((en as Record<string, string>)[key]),
				`${name}.${key} placeholder mismatch`,
			);
		}
	});
}

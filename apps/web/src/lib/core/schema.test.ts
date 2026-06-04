// Architecture guard for the F11 string-literal registry. The table /
// bucket names that flow through `core/schema.ts` must NOT also appear as
// bare `.from('runs')` / `.storage.from('runs')` string literals anywhere
// else in the source tree — a stray literal silently dodges the registry
// and reopens the rename-by-grep hazard the registry exists to close.
//
// Mirrors the `security_guards.test.ts` file-as-text pattern: walk the
// source tree, read each file, assert the forbidden pattern is absent.
// See reviews/audit-db-optimization.md § F11.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TABLES, BUCKETS } from './schema';

const __dirname = dirname(fileURLToPath(import.meta.url));
const srcRoot = resolve(__dirname, '../..');

// Files allowed to carry the bare literals: the registry itself (it
// defines them) and this guard (it names them in patterns + prose).
const ALLOWLIST = new Set(['lib/core/schema.ts', 'lib/core/schema.test.ts']);

function walk(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === '.svelte-kit') continue;
			walk(full, out);
		} else if (
			(entry.name.endsWith('.ts') || entry.name.endsWith('.svelte')) &&
			!entry.name.endsWith('.test.ts') &&
			!entry.name.endsWith('.spec.ts')
		) {
			out.push(full);
		}
	}
	return out;
}

// Every name routed through the registry is guarded — `runs` is the
// headline case from the audit, and the F11 rollout has since folded in the
// activity-core siblings plus the social / club / event / coaching / gear /
// segment / fitness base tables and the run-photos bucket. The set is derived
// straight from TABLES + BUCKETS, so adding a name there automatically guards
// every bare `.from('<name>')` for it tree-wide.
const guardedNames = Array.from(new Set([...Object.values(TABLES), ...Object.values(BUCKETS)]));

test('no bare .from(<registry name>) literal outside core/schema.ts', () => {
	const files = walk(srcRoot);
	const offenders: string[] = [];
	for (const file of files) {
		const rel = relative(srcRoot, file);
		if (ALLOWLIST.has(rel)) continue;
		const source = readFileSync(file, 'utf-8');
		for (const name of guardedNames) {
			// Matches both `.from('runs')` and `.storage.from('runs')`
			// (the latter contains the former as a substring).
			const re = new RegExp(`\\.from\\(\\s*['"]${name}['"]\\s*\\)`);
			if (re.test(source)) offenders.push(`${rel}: .from('${name}')`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`Bare table/bucket literals must route through core/schema.ts (TABLES / BUCKETS). ` +
			`Replace .from('runs') with .from(TABLES.runs) and .storage.from('runs') with ` +
			`.storage.from(BUCKETS.runs). Offenders:\n${offenders.join('\n')}`,
	);
});

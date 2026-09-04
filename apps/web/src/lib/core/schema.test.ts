// Architecture guard for the F11 string-literal registry. The table /
// bucket names that flow through `core/schema.ts` must NOT also appear as
// bare `.from('runs')` / `.storage.from('runs')` string literals anywhere
// else in the source tree — a stray literal silently dodges the registry
// and reopens the rename-by-grep hazard the registry exists to close.
//
// Mirrors the `privacy_guards.test.ts` file-as-text pattern: walk the
// source tree, read each file, assert the forbidden pattern is absent.
// See reviews/audit-db-optimization.md § F11.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { TABLES, BUCKETS, METADATA_KEYS } from './schema';

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

// The registry's own doc comment declares METADATA_KEYS and
// docs/backend/metadata.md are kept "in lockstep" — but nothing enforced it,
// so PR #460 could add a `runs.metadata` key to the doc, use a bare string
// literal for it, and never register it (CI green). These two guards close
// that gap from both ends: every registered key must be documented, and the
// stamp helper that motivated the gap must read/write through the registry.
test('every METADATA_KEYS entry is documented in docs/backend/metadata.md', () => {
	// Reason: the registry is the only compile-time coupling between the
	// writer and reader sides of the schema-less jsonb bag (codegen cannot
	// see inside it), and docs/backend/metadata.md is the registry of record
	// for shape / writers / readers / public-view safety. A key that exists
	// in code but not in the doc has no recorded public_runs classification.
	// Path is cwd-relative (cwd = apps/web under `test:unit`), matching
	// data.test.ts.
	const doc = readFileSync(resolve('../../docs/backend/metadata.md'), 'utf-8');
	const undocumented = Object.values(METADATA_KEYS).filter((key) => !doc.includes(`\`${key}\``));
	assert.deepEqual(
		undocumented,
		[],
		`Every METADATA_KEYS entry needs a row in docs/backend/metadata.md (shape, writer, ` +
			`reader, public-view safety). Undocumented:\n${undocumented.join('\n')}`,
	);
});

test('the global-segments scored stamp routes through METADATA_KEYS, not a bare literal', () => {
	// Reason: data_normalise.ts owns both the read and the write of
	// `runs.metadata.global_segments_scored_count`. Spelling the key inline
	// on either side is exactly the typo-and-silent-failure hazard the
	// registry exists to close — a misspelt writer key makes the rescore
	// gate read `null` forever, silently reverting the optimisation.
	const source = readFileSync(resolve('src/lib/core/data_normalise.ts'), 'utf-8');
	assert.match(
		source,
		/METADATA_KEYS\.global_segments_scored_count/,
		'data_normalise.ts must reach the stamp key through METADATA_KEYS.',
	);
	// Every mention of the key in CODE must be the registry member access —
	// a quoted literal, a shorthand property or a dotted read all dodge the
	// registry. Prose in the doc comments is exempt.
	const code = source
		.split('\n')
		.filter((line) => !line.trimStart().startsWith('//') && !line.trimStart().startsWith('///'))
		.join('\n');
	const stray = code
		.split('global_segments_scored_count')
		.slice(0, -1)
		.filter((before) => !before.endsWith('METADATA_KEYS.')).length;
	assert.equal(
		stray,
		0,
		'data_normalise.ts must not spell global_segments_scored_count outside ' +
			'METADATA_KEYS.<key> — a bare literal or shorthand property dodges the registry.',
	);
});

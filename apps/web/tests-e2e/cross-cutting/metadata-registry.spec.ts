import { expect, test } from '@playwright/test';
import { readdirSync, readFileSync } from 'node:fs';

/**
 * `runs.metadata` jsonb registry — web parity with the mobile
 * `metadata_registry_test.dart` (apps/mobile_android/test/).
 *
 * `runs.metadata` is a jsonb bag with no schema. The registry in
 * `docs/backend/metadata.md` is the only thing keeping cross-platform writers
 * and readers in sync — when web writes a key the mobile reader
 * doesn't know about (or vice versa), data silently disappears at
 * the platform boundary.
 *
 * This test scans web TS / Svelte sources for every `metadata.X` /
 * `metadata['X']` / `metadata?.X` access and asserts each key is
 * documented in `docs/backend/metadata.md`. Mirrors the mobile test so a key
 * added on either side without a doc update fails CI on both.
 */

const DOCS_PATH = '../../docs/backend/metadata.md';

// Keys we deliberately don't enforce — false positives from grep.
// Matches the mobile test's allow-list shape.
const ALLOW_LIST = new Set<string>([
	// Generic property names that happen to follow the pattern
	'metadata', // recursive `metadata.metadata` — happens in some types
	'data', // metadata.data is sometimes a generic blob field
]);

function webSourceFiles(): string[] {
	return readdirSync('src', { recursive: true, encoding: 'utf-8' })
		.filter((p) => p.endsWith('.ts') || p.endsWith('.svelte'))
		.map((p) => `src/${p}`);
}

function repoMetadataKeys(): string[] {
	// Two precise patterns, mirroring the mobile test, rather than one broad
	// grep: a dotted access, and a subscript whose key is a quoted literal.
	// A bare `metadata[key]` subscripts a variable whose value isn't knowable
	// statically, so it is deliberately not collected as a key.
	const dotted = /(?<![A-Za-z0-9_])metadata[!?]?\.([a-zA-Z_][a-zA-Z0-9_]*)/g;
	const subscript =
		/(?<![A-Za-z0-9_])metadata[!?]?\s*\[\s*(['"])([a-zA-Z_][a-zA-Z0-9_]*)\1\s*\]/g;

	const keys = new Set<string>();
	for (const file of webSourceFiles()) {
		const source = readFileSync(file, 'utf-8');
		for (const m of source.matchAll(dotted)) {
			// `docs/backend/metadata.md` is this guard's own registry document,
			// cited in comments throughout the source — a filename, not a key.
			// A genuine `md` key would still be caught by the subscript form.
			if (m[1] === 'md') continue;
			keys.add(m[1]);
		}
		for (const m of source.matchAll(subscript)) keys.add(m[2]);
	}
	return [...keys].filter((k) => k !== 'metadata' && !ALLOW_LIST.has(k)).sort();
}

function documentedKeys(): Set<string> {
	const md = readFileSync(DOCS_PATH, 'utf-8');
	const keys = new Set<string>();
	for (const m of md.matchAll(/`([a-z_][a-z0-9_]*)`/g)) {
		keys.add(m[1]);
	}
	return keys;
}

test.describe('runs.metadata registry parity', () => {
	test('every metadata key referenced in web source is documented in docs/backend/metadata.md', () => {
		const referenced = repoMetadataKeys();
		const docs = documentedKeys();

		// Filter the referenced set down to keys that LOOK like real
		// metadata jsonb keys. We bias towards lowercase-with-
		// underscores (snake_case) because that's the documented
		// convention; camelCase / PascalCase usually means a TS
		// property access that grep tagged by accident.
		const candidates = referenced.filter((k) =>
			/^[a-z][a-z0-9_]*$/.test(k)
		);

		const missing = candidates.filter((k) => !docs.has(k));

		expect(
			missing,
			`These metadata keys are referenced in apps/web/src/ but not\n` +
				`documented in docs/backend/metadata.md. Adding a key to runs.metadata\n` +
				`without a doc entry creates cross-client drift — the mobile\n` +
				`reader (or another web feature) won't know to expect it.\n\n` +
				`Either (a) add the key to docs/backend/metadata.md, or (b) if the grep\n` +
				`hit a false positive (a non-metadata jsonb property access\n` +
				`that happens to live under a variable named "metadata"), add\n` +
				`it to the ALLOW_LIST in this test.`
		).toEqual([]);
	});
});

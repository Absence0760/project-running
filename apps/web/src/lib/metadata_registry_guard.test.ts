import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { METADATA_KEYS } from './core/schema';

/**
 * Guard-rail: every `runs.metadata` key referenced in the web source tree
 * must be registered in `docs/backend/metadata.md`.
 *
 * `runs.metadata` is a jsonb bag with no type-level protection. Cross-client
 * drift (mobile writes `activity_type`, web reads `activityType`) is the exact
 * failure mode the registry was created to prevent. The Dart twin of this
 * guard is `apps/mobile_android/test/metadata_registry_test.dart`; the Kotlin
 * and Swift twins live under `apps/watch_wear/` and `apps/watch_ios/`. Each
 * scans its own platform's sources against the one shared registry.
 *
 * Supersedes `tests-e2e/cross-cutting/metadata-registry.spec.ts`, which paid
 * for the whole Playwright harness to run a static source scan, never saw
 * object-literal writes or `METADATA_KEYS` indirection, and counted any
 * backticked token anywhere in the doc — prose included — as "documented".
 *
 * Distinct from `core/schema.test.ts`, which walks the other direction —
 * every `METADATA_KEYS` entry must have a doc row. That leaves a bare string
 * literal or a dotted read (`run.metadata.foo`) unguarded, which is what this
 * file closes. The registry→code "dead key" direction is deliberately not
 * mirrored here: `docs/backend/metadata.md` is cross-platform, so a key no
 * web module touches is expected, not drift.
 */

const libRoot = import.meta.dirname;
const srcRoot = resolve(libRoot, '..');
const repoRoot = resolve(libRoot, '..', '..', '..', '..');

/// Keys the guard should ignore because the match is a real `metadata`
/// identifier that isn't `runs.metadata` (e.g. a Learn-guide frontmatter bag).
/// Keep empty until a genuine spurious match appears, and always add a
/// one-line reason beside the entry.
const EXEMPT_REFERENCES = new Set<string>();

/// Registered key names from the markdown registry: each table row opens
/// `| \`key\` |`. Same parse as the Dart guard, so the two can't disagree
/// about what "registered" means.
function parseRegistry(doc: string): Set<string> {
	const out = new Set<string>();
	for (const m of doc.matchAll(/^\|\s*`([a-z_][a-z0-9_]*)`\s*\|/gm)) out.add(m[1]);
	return out;
}

function sourceFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = resolve(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === '.svelte-kit') continue;
			sourceFiles(full, out);
		} else if (
			(entry.name.endsWith('.ts') || entry.name.endsWith('.svelte')) &&
			!entry.name.endsWith('.test.ts') &&
			!entry.name.endsWith('.spec.ts') &&
			!entry.name.endsWith('.d.ts') &&
			entry.name !== 'database.types.ts'
		) {
			out.push(full);
		}
	}
	return out;
}

/// Blank out `//` and block comments, leaving offsets intact. String literals
/// are walked over rather than blanked, so a `'//'` inside a string can't be
/// mistaken for a comment and swallow the rest of the line.
function stripJsComments(source: string): string {
	const out = source.split('');
	let i = 0;
	while (i < source.length) {
		const c = source[i];
		if (c === "'" || c === '"' || c === '`') {
			i++;
			while (i < source.length) {
				if (source[i] === '\\') i++;
				else if (source[i] === c) break;
				i++;
			}
			i++;
			continue;
		}
		if (c === '/' && source[i + 1] === '/') {
			while (i < source.length && source[i] !== '\n') out[i++] = ' ';
			continue;
		}
		if (c === '/' && source[i + 1] === '*') {
			const end = source.indexOf('*/', i + 2);
			const stop = end === -1 ? source.length : end + 2;
			for (; i < stop; i++) if (source[i] !== '\n') out[i] = ' ';
			continue;
		}
		i++;
	}
	return out.join('');
}

/// Scannable text of one file. A `.svelte` file is split into its script
/// bodies (real TS, comment-stripped) and its markup (HTML comments dropped);
/// running the string-aware comment stripper over raw markup would trip on
/// apostrophes in prose and blank whole regions.
///
/// The tag patterns are case-insensitive and anchor the tag name on a
/// delimiter (`\b` would let `<scripts>` through). A `<SCRIPT>` body that
/// failed to match would be scanned as markup instead of as TS, so the
/// object-literal and `METADATA_KEYS` extraction would silently skip it — a
/// guard that under-enforces without saying so, which is the exact failure
/// this file exists to replace.
const SCRIPT_BLOCK = /<script(?=[\s/>])[^>]*>[\s\S]*?<\/script\s*>/gi;
const STYLE_BLOCK = /<style(?=[\s/>])[^>]*>[\s\S]*?<\/style\s*>/gi;

function chunksOf(file: string, raw: string): string[] {
	if (!file.endsWith('.svelte')) return [stripJsComments(raw)];
	const scripts = [...raw.matchAll(/<script(?=[\s/>])[^>]*>([\s\S]*?)<\/script\s*>/gi)].map((m) =>
		stripJsComments(m[1]),
	);
	const markup = raw
		.replace(SCRIPT_BLOCK, ' ')
		.replace(STYLE_BLOCK, ' ')
		.replace(/<!--[\s\S]*?--!?>/g, ' ');
	return [...scripts, markup];
}

/// Every string-literal key at depth 1 of the object literal whose opening
/// brace sits at [open], plus computed `[METADATA_KEYS.x]` keys.
function literalKeys(chunk: string, open: number, into: Set<string>): void {
	let depth = 1;
	let i = open + 1;
	while (i < chunk.length && depth > 0) {
		const c = chunk[i];
		if (c === '{') depth++;
		else if (c === '}') depth--;
		if (depth === 1) {
			const rest = chunk.slice(i);
			const quoted = /^\s*(['"])([a-z_][a-z0-9_]*)\1\s*:/.exec(rest);
			const bare = /^[\s,{]\s*([a-z_][a-z0-9_]*)\s*:/.exec(rest);
			const computed = /^\s*\[\s*METADATA_KEYS\.([A-Za-z0-9_]+)\s*\]\s*:/.exec(rest);
			if (quoted) {
				into.add(quoted[2]);
				i += quoted[0].length;
				continue;
			}
			if (computed) {
				const value = (METADATA_KEYS as Record<string, string>)[computed[1]];
				if (value) into.add(value);
				i += computed[0].length;
				continue;
			}
			if (bare) {
				into.add(bare[1]);
				i += bare[0].length;
				continue;
			}
		}
		i++;
	}
}

/// Find every `runs.metadata` key reference in one scannable chunk. Covers:
///
///   * `METADATA_KEYS.<ident>` — resolved back to the wire key
///   * subscript reads/writes: `metadata['x']`, `metadata?.['x']`, `run.metadata!['x']`
///   * dotted reads: `run.metadata.x`, `run.metadata?.x`
///   * object literals: `metadata: { x: … }` / `const metadata: T = { 'x': … }`
///
/// Deliberately not covered: dynamic keys (`metadata[someVar]`), which carry
/// no literal to check.
function extractKeys(chunk: string): Set<string> {
	const keys = new Set<string>();

	for (const m of chunk.matchAll(/METADATA_KEYS\.([A-Za-z0-9_]+)/g)) {
		const value = (METADATA_KEYS as Record<string, string>)[m[1]];
		if (value) keys.add(value);
	}
	for (const m of chunk.matchAll(
		/(?<![\w$])metadata\s*[!?]?\s*\.?\s*\[\s*(['"])([a-z_][a-z0-9_]*)\1\s*\]/g,
	)) {
		keys.add(m[2]);
	}
	for (const m of chunk.matchAll(/(?<![\w$])metadata\s*[!?]?\s*\.\s*([a-z_][a-z0-9_]*)/g)) {
		keys.add(m[1]);
	}
	for (const m of chunk.matchAll(/(?<![\w$])metadata\s*(?::[^=;\n]*)?=\s*\{/g)) {
		literalKeys(chunk, m.index + m[0].length - 1, keys);
	}
	for (const m of chunk.matchAll(/(?<![\w$])metadata\s*:\s*\{/g)) {
		literalKeys(chunk, m.index + m[0].length - 1, keys);
	}

	return keys;
}

test('every `runs.metadata` key referenced in web source is registered in docs/backend/metadata.md', () => {
	const registry = parseRegistry(
		readFileSync(resolve(repoRoot, 'docs', 'backend', 'metadata.md'), 'utf-8'),
	);
	assert.ok(registry.size > 0, 'parsed an empty registry — the markdown table shape changed');

	const referenced = new Map<string, string[]>();
	for (const file of sourceFiles(srcRoot)) {
		const raw = readFileSync(file, 'utf-8');
		for (const chunk of chunksOf(file, raw)) {
			for (const key of extractKeys(chunk)) {
				const at = referenced.get(key) ?? [];
				const rel = relative(repoRoot, file);
				if (!at.includes(rel)) at.push(rel);
				referenced.set(key, at);
			}
		}
	}

	const unknown = [...referenced.keys()]
		.filter((k) => !registry.has(k) && !EXEMPT_REFERENCES.has(k))
		.sort();

	assert.deepEqual(
		unknown,
		[],
		`Unregistered runs.metadata key(s) referenced in web source:\n` +
			unknown.map((k) => `  ${k}\n${referenced.get(k)!.map((p) => `      at ${p}`).join('\n')}`).join('\n') +
			`\n\nEither:\n` +
			`  1) Register the key in docs/backend/metadata.md (preferred) — snake_case, ` +
			`shape, writers, readers, public_runs safety — and add it to METADATA_KEYS in ` +
			`src/lib/core/schema.ts.\n` +
			`  2) If the match is spurious (a \`metadata\` identifier that is not ` +
			`runs.metadata), add the key to EXEMPT_REFERENCES in this file with a reason.\n\n` +
			`Drift in runs.metadata is invisible to the DB type system — this registry IS ` +
			`the coordination point across web, mobile, watch_wear, and watch_ios.`,
	);
});

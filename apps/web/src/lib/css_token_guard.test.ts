import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

// A `var(--foo)` whose custom property is defined nowhere is not an error in
// CSS — the declaration silently resolves to the property's initial/inherited
// value at computed-value time (`background` -> transparent, `border` -> none,
// `color` -> inherited). Three surfaces (roadbook, RouteMarkerEditor, the
// event board) shipped with a whole undefined token vocabulary
// (--surface/--text-primary/--border/--accent) and therefore never tracked
// the light/dark theme (accessibility audit 2026-07-02 High). This guard
// fails the build on any fallback-less var() reference to a token that is
// neither in app.css nor defined/assigned in the same file.

const __dirname = resolve(new URL('.', import.meta.url).pathname);
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

function walkFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) {
			if (!SKIP_DIRS.has(entry.name)) walkFiles(path, out);
			continue;
		}
		if (/\.(svelte|css)$/.test(entry.name)) out.push(path);
	}
	return out;
}

test('every fallback-less var(--token) reference resolves to a defined custom property', () => {
	const srcRoot = resolve(__dirname, '..');
	const globalCss = readFileSync(join(srcRoot, 'app.css'), 'utf-8');
	const globalTokens = new Set(
		[...globalCss.matchAll(/--([a-zA-Z0-9-]+)\s*:/g)].map((m) => m[1]),
	);

	const offenders: string[] = [];
	for (const path of walkFiles(srcRoot)) {
		const source = readFileSync(path, 'utf-8');
		// Local definitions: `--x: ...` in a style block or inline style, and
		// Svelte's `style:--x={...}` / `--x={...}` component custom-property
		// directives all end up defining the property for this subtree.
		const localTokens = new Set([
			...[...source.matchAll(/--([a-zA-Z0-9-]+)\s*[:=]/g)].map((m) => m[1]),
			...[...source.matchAll(/style:--([a-zA-Z0-9-]+)/g)].map((m) => m[1]),
		]);
		source.split('\n').forEach((line, i) => {
			for (const m of line.matchAll(/var\(\s*--([a-zA-Z0-9-]+)\s*\)/g)) {
				const name = m[1];
				if (!globalTokens.has(name) && !localTokens.has(name)) {
					offenders.push(`${path}:${i + 1}  var(--${name})`);
				}
			}
		});
	}
	assert.equal(
		offenders.length,
		0,
		`var() references an undefined custom property (the declaration silently ` +
			`collapses to its initial value and ignores the theme). Use the matching ` +
			`--color-*/--space-*/--radius-* token from app.css or define the property:\n` +
			offenders.join('\n'),
	);
});

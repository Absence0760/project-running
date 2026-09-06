// Build the share-entity Lambda zip.
//
// Run from `apps/web/`:   node lambda/share-entity/build.mjs
//
// Output: apps/web/lambda/share-entity/dist/share-entity.zip
//
// Strategy: esbuild bundles src/index.ts (and everything it imports
// transitively from $lib/*) into a single index.mjs. supabase-js is
// inlined. Unlike share-run/route/badge/recap this Lambda serves HTML
// ONLY (no per-entity og:image PNG), so there is NO native @resvg addon
// to keep external + copy — the whole handler bundles cleanly. The
// SPA shell 200.html is read from apps/web/build/200.html (built by
// `npm run build`) and substituted in as the __SPA_SHELL_HTML__ constant.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync, rmSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..', '..');
const distDir = resolve(here, 'dist');
const spaShellPath = resolve(webRoot, 'build', '200.html');

if (!existsSync(spaShellPath)) {
	console.error(
		`[share-entity build] missing SPA shell at ${spaShellPath}. ` +
			`Run \`npm run build\` (from apps/web/) first so the 200.html shell exists.`,
	);
	process.exit(1);
}

const spaShellHtml = readFileSync(spaShellPath, 'utf-8');

if (existsSync(distDir)) rmSync(distDir, { recursive: true });
mkdirSync(distDir, { recursive: true });

await build({
	entryPoints: [resolve(here, 'src/index.ts')],
	bundle: true,
	platform: 'node',
	// Match the Lambda runtime (`runtime = "nodejs24.x"` in
	// infra/modules/web-stack/main.tf).
	target: 'node24',
	format: 'esm',
	outfile: resolve(distDir, 'index.mjs'),
	// Lambda's managed runtime only ships AWS SDK v3, which we don't use,
	// so supabase-js + $lib helpers get inlined.
	external: [],
	// Some transitive deps (e.g. inside @supabase/realtime-js) still ship
	// CJS. Provide a `require` in the ESM bundle so they load.
	banner: {
		js: 'import { createRequire as __cr } from "module"; const require = __cr(import.meta.url);',
	},
	define: {
		__SPA_SHELL_HTML__: JSON.stringify(spaShellHtml),
	},
	minify: true,
	sourcemap: 'linked',
	keepNames: true,
});

writeFileSync(
	resolve(distDir, 'package.json'),
	JSON.stringify({ type: 'module' }, null, 2) + '\n',
);

execSync('zip -qr share-entity.zip index.mjs index.mjs.map package.json', {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'share-entity.zip')}`);

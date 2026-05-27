// Build the share-run Lambda zip.
//
// Run from `apps/web/`:   node lambda/share-run/build.mjs
// Or from CI:              same.
//
// Output: apps/web/lambda/share-run/dist/share-run.zip
//
// Strategy: esbuild bundles src/index.ts (and everything it imports
// transitively from $lib/*) into a single index.mjs. supabase-js +
// @resvg/resvg-js are inlined because the Lambda runtime doesn't ship
// them. The SPA-shell index.html is read from apps/web/build/index.html
// (built by `npm run build`) and substituted in as the
// __SPA_SHELL_HTML__ constant via esbuild's `define`.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
	mkdirSync,
	rmSync,
	writeFileSync,
	existsSync,
	readFileSync,
} from 'node:fs';
import { execSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..', '..');
const distDir = resolve(here, 'dist');
const spaShellPath = resolve(webRoot, 'build', 'index.html');

if (!existsSync(spaShellPath)) {
	console.error(
		`[share-run build] missing SPA shell at ${spaShellPath}. ` +
			`Run \`npm run build\` (from apps/web/) first so the index.html template exists.`,
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
	// infra/modules/web-stack/main.tf). @supabase/realtime-js >=2.105
	// needs native WebSocket support (node 22+); node 24 gives us that
	// + better ESM ergonomics.
	target: 'node24',
	format: 'esm',
	outfile: resolve(distDir, 'index.mjs'),
	// Bundle everything — Lambda's managed runtime only ships AWS
	// SDK v3, which we don't use. supabase-js, @resvg/resvg-js, and
	// $lib helpers all get inlined.
	external: [],
	// Some transitive deps (e.g. inside @supabase/realtime-js) still
	// ship CJS. Provide a `require` in the ESM bundle so they load.
	banner: {
		js: 'import { createRequire as __cr } from "module"; const require = __cr(import.meta.url);',
	},
	// Substitute the SPA shell at bundle time so the Lambda doesn't
	// need to load it from S3 / disk at runtime. The handler treats
	// __SPA_SHELL_HTML__ as an opaque string.
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

execSync('zip -qr share-run.zip index.mjs index.mjs.map package.json', {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'share-run.zip')}`);

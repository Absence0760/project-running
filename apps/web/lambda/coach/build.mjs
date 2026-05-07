// Build the coach Lambda zip.
//
// Run from `apps/web/`:   node lambda/coach/build.mjs
// Or from CI:              same.
//
// Output: apps/web/lambda/coach/dist/coach.zip
//
// Strategy: esbuild bundles src/index.ts (and everything it imports
// transitively from $lib/coach/) into a single index.mjs. Anthropic
// SDK + supabase-js are inlined because the Lambda runtime doesn't
// ship them. The createRequire shim keeps any CJS-only transitive
// deps importable from ESM.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const distDir = resolve(here, 'dist');

if (existsSync(distDir)) rmSync(distDir, { recursive: true });
mkdirSync(distDir, { recursive: true });

await build({
	entryPoints: [resolve(here, 'src/index.ts')],
	bundle: true,
	platform: 'node',
	// Match the Lambda runtime (`runtime = "nodejs24.x"` in
	// infra/modules/web-stack/main.tf). Must be node22+ regardless:
	// @supabase/realtime-js >=2.105 needs native WebSocket support,
	// which only landed in Node 22.
	target: 'node24',
	format: 'esm',
	outfile: resolve(distDir, 'index.mjs'),
	// Bundle everything — Lambda's managed Node.js runtime ships with
	// only the AWS SDK v3, not @anthropic-ai/sdk or @supabase/supabase-js.
	// We don't import any aws-sdk modules at runtime, so nothing to mark
	// external.
	external: [],
	// Some transitive deps (e.g. inside @supabase/realtime-js) still
	// ship CJS. Provide a `require` in the ESM bundle so they load.
	banner: {
		js: 'import { createRequire as __cr } from "module"; const require = __cr(import.meta.url);',
	},
	minify: true,
	sourcemap: 'linked',
	// Strict mode by default; preserve property names so source maps
	// stay readable on Sentry server-side.
	keepNames: true,
});

writeFileSync(
	resolve(distDir, 'package.json'),
	JSON.stringify({ type: 'module' }, null, 2) + '\n',
);

execSync('zip -qr coach.zip index.mjs index.mjs.map package.json', {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'coach.zip')}`);

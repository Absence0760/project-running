// Build the share-recap Lambda zip.
//
// Run from `apps/web/`:   node lambda/share-recap/build.mjs
//
// Output: apps/web/lambda/share-recap/dist/share-recap.zip
//
// Same strategy as lambda/share-run/build.mjs: esbuild bundles src/index.ts
// (+ everything it imports from $lib/*) into one index.mjs; supabase-js is
// inlined; @resvg/resvg-js is a native addon kept external and copied into
// the zip's node_modules; the SPA shell 200.html is substituted in as
// __SPA_SHELL_HTML__. See lambda/share-run/README.md for the rationale.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { mkdirSync, rmSync, writeFileSync, existsSync, readFileSync, cpSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..', '..');
const distDir = resolve(here, 'dist');
const spaShellPath = resolve(webRoot, 'build', '200.html');

const RESVG_LOADER = '@resvg/resvg-js';
const RESVG_ARM64 = '@resvg/resvg-js-linux-arm64-gnu';
const RESVG_EXTERNAL = [RESVG_LOADER, RESVG_ARM64];

if (!existsSync(spaShellPath)) {
	console.error(
		`[share-recap build] missing SPA shell at ${spaShellPath}. ` +
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
	target: 'node24',
	format: 'esm',
	outfile: resolve(distDir, 'index.mjs'),
	external: RESVG_EXTERNAL,
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

copyResvgPackages();

execSync('zip -qr share-recap.zip index.mjs index.mjs.map package.json node_modules', {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'share-recap.zip')}`);

function copyResvgPackages() {
	const req = createRequire(resolve(webRoot, 'package.json'));
	let arm64PkgDir;
	try {
		arm64PkgDir = dirname(req.resolve(`${RESVG_ARM64}/package.json`));
	} catch {
		console.error(
			`[share-recap build] missing ${RESVG_ARM64}. The Lambda runs on arm64, ` +
				`so its native binary must ship in the zip. Fetch the versioned ` +
				`tarball and unpack it into node_modules (npm pack + tar; do NOT ` +
				`npm install --cpu=arm64 — that re-evaluates every optional dep ` +
				`for arm64 and prunes the x64 bindings the build toolchain itself ` +
				`needs). Recipe: release-web.yml's install step.`,
		);
		process.exit(1);
	}
	const loaderPkgDir = dirname(req.resolve(`${RESVG_LOADER}/package.json`));
	const nm = resolve(distDir, 'node_modules', '@resvg');
	mkdirSync(nm, { recursive: true });
	cpSync(loaderPkgDir, resolve(nm, 'resvg-js'), { recursive: true });
	cpSync(arm64PkgDir, resolve(nm, 'resvg-js-linux-arm64-gnu'), { recursive: true });
}

// Build the share-run Lambda zip.
//
// Run from `apps/web/`:   node lambda/share-run/build.mjs
// Or from CI:              same.
//
// Output: apps/web/lambda/share-run/dist/share-run.zip
//
// Strategy: esbuild bundles src/index.ts (and everything it imports
// transitively from $lib/*) into a single index.mjs. supabase-js is
// inlined. @resvg/resvg-js is a NATIVE addon — esbuild can't inline a
// `.node` binary, so the loader package + its arm64 binary are marked
// external and copied into the zip's node_modules instead (see
// RESVG_EXTERNAL + copyResvgPackages below). The SPA-shell index.html
// is read from apps/web/build/index.html (built by `npm run build`)
// and substituted in as the __SPA_SHELL_HTML__ constant via esbuild's
// `define`.
//
// The Lambda runs on arm64 (infra/modules/web-stack/main.tf sets
// `architectures = ["arm64"]`), so the build needs the
// `@resvg/resvg-js-linux-arm64-gnu` native package present even when
// the build host is x64. `npm ci`/`npm install` in apps/web pulls it
// in as an optional dep on a linux/x64 host too (optional deps for
// other platforms are still downloaded unless `--no-optional` or
// `--cpu`/`--os` filters are set). If it's missing, this script fails
// fast with the install command — see apps/web/lambda/share-run/README.md.

import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
	mkdirSync,
	rmSync,
	writeFileSync,
	existsSync,
	readFileSync,
	cpSync,
} from 'node:fs';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, '..', '..');
const distDir = resolve(here, 'dist');
const spaShellPath = resolve(webRoot, 'build', 'index.html');

// The native PNG rasteriser. The arm64 binary package must ship in the
// zip; the JS loader (`@resvg/resvg-js`) require()s it at runtime by
// name, so both stay external (not inlined) and get copied below.
const RESVG_LOADER = '@resvg/resvg-js';
const RESVG_ARM64 = '@resvg/resvg-js-linux-arm64-gnu';
const RESVG_EXTERNAL = [RESVG_LOADER, RESVG_ARM64];

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
	// Bundle everything except the native PNG rasteriser. Lambda's
	// managed runtime only ships AWS SDK v3, which we don't use, so
	// supabase-js + $lib helpers get inlined. @resvg/resvg-js is a
	// native addon — kept external and copied into node_modules below.
	external: RESVG_EXTERNAL,
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

copyResvgPackages();

execSync('zip -qr share-run.zip index.mjs index.mjs.map package.json node_modules', {
	cwd: distDir,
	stdio: 'inherit',
});

console.log(`built: ${resolve(distDir, 'share-run.zip')}`);

// Copy the @resvg loader + the arm64 native binary package into the
// zip's node_modules so the Lambda's `require('@resvg/resvg-js')`
// resolves at runtime and finds the arm64 `.node` addon. esbuild
// can't inline a native addon, hence this explicit copy.
function copyResvgPackages() {
	const req = createRequire(resolve(webRoot, 'package.json'));
	let arm64PkgDir;
	try {
		arm64PkgDir = dirname(req.resolve(`${RESVG_ARM64}/package.json`));
	} catch {
		console.error(
			`[share-run build] missing ${RESVG_ARM64}. The Lambda runs on ` +
				`arm64, so its native binary must ship in the zip. Install it ` +
				`with:\n\n  npm install --workspace=apps/web --cpu=arm64 ` +
				`--os=linux ${RESVG_ARM64}\n\nor run \`npm ci\` on a host that ` +
				`resolves linux/arm64 optional deps. See ` +
				`apps/web/lambda/share-run/README.md.`,
		);
		process.exit(1);
	}
	const loaderPkgDir = dirname(req.resolve(`${RESVG_LOADER}/package.json`));
	const nm = resolve(distDir, 'node_modules', '@resvg');
	mkdirSync(nm, { recursive: true });
	cpSync(loaderPkgDir, resolve(nm, 'resvg-js'), { recursive: true });
	cpSync(arm64PkgDir, resolve(nm, 'resvg-js-linux-arm64-gnu'), {
		recursive: true,
	});
}

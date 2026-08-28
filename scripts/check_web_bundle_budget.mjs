#!/usr/bin/env node
// Guardrail: the web bundle's ceilings measure what one reader downloads, and
// a translation is not a dep.
//
// This job summed every emitted JS+CSS file into one number. That is the right
// arithmetic for a dependency — code-splitting a library must not lower the
// total, or the gate rewards moving weight around instead of removing it — and
// the wrong arithmetic for a message catalogue. The six non-default catalogues
// are `import()`ed one at a time by `i18n/store.svelte.ts`; a German reader
// fetches `de` and never the other five. Summing them charges every reader for
// bytes only one language's readers ever request, so the ceiling had to climb
// once per language: pt-PT (§ 755) moved the total 2376 -> 2462 and forced
// 2400 -> 2700 while the largest chunk stayed byte-identical, i.e. the gate
// fired on a change that moved no reader's payload at all. Each language after
// that buys the next rogue dep another ~88 KB of cover.
//
// So the emitted files are split into two populations with a budget each:
//
//   MAX_CODE_KB           everything a reader downloads regardless of language.
//   MAX_CATALOGUE_KB      per catalogue, NOT summed — this is the number that
//                         must not move when a language is added.
//   MAX_LARGEST_CHUNK_KB  the largest single CODE chunk, catalogues excluded:
//                         a catalogue is already its own lazy chunk and cannot
//                         be split further, so it is governed by its own
//                         ceiling and by nothing else.
//   MAX_ASSET_KB          per emitted file that is neither JS nor CSS — a font,
//                         an icon, a prerendered page, the manifest — and, like
//                         a catalogue, never summed.
//
// The asset ceiling closes a hole the other three could not see. The walk
// matched `*.js` and `*.css` only, so everything else the build emits was
// outside the metric entirely: measured, 33 files and 4058 KB gzipped, of which
// ONE file was 3866 KB — the unsubsetted `material-symbols-outlined.woff2`,
// declared `font-display: block` in the ROOT layout's stylesheet, so it was
// blocking weight for every reader and 1.8x the whole code ceiling. It shipped
// for one measurement under a named exemption rather than being absorbed,
// because a ceiling that would admit it silently admits the next one too, and
// the exemption is now gone: the font is subset to the icons the app names
// (decisions § 779) and clears the same 100 KB every other asset is held to.
// ASSET_EXEMPTIONS is deliberately left in place and EMPTY — the arithmetic it
// carries is worth keeping, and an empty list is the honest statement that
// nothing currently needs covering.
//
// Per file and never summed is the right arithmetic here for the catalogues'
// reason: a reader loads ONE prerendered page, ONE favicon. That also answers
// the question this population was added for — whether prerendered HTML needs a
// budget. It does, and this is it: 16 HTML files today (15 of them under
// `/learn`), 71 KB gzipped in total, largest 5 KB. A per-locale prerender of
// `/learn` would multiply the file count and move no ceiling, exactly as a
// seventh language moves no catalogue ceiling. (The filing that asked for this
// assumed the 8 guides already prerendered once per language; they do not —
// prose localization has not shipped, and the tree holds one language's HTML.)
//
// The English catalogue is deliberately on the CODE side, and that is not an
// accounting convenience. `store.svelte.ts` imports it statically as the
// synchronous fallback dict (`dict[key] ?? en[key] ?? key`), so rollup emits it
// inside the shared store chunk that every reader downloads before any locale
// is negotiated. Every non-English reader therefore downloads TWO catalogues,
// not one. It is a real unconditional cost, it belongs in the number that
// tracks unconditional cost, and it is why exactly one locale is expected to be
// absent from the manifest below.
//
// Classification comes from vite's client manifest, not from a filename
// pattern. Client chunks are content-hashed (`chunks/3HhVpFjz.js`) and carry no
// name at all, so a pattern could only guess; the manifest states which emitted
// file each `src/lib/i18n/locales/<tag>.ts` became. It also makes the guard
// fail on the interesting drift rather than silently absorb it: a catalogue
// that stops being its own chunk disappears from the manifest, and the count
// check below names the locale instead of letting ~88 KB land in the code
// budget under a message about deps.
//
// Ceilings, and the measurements behind them (2026-08-28, gzip via node:zlib):
//   code 1934 KB across 403 files, largest code chunk 245 KB
//   catalogues 522 KB across 6 — de 88, es 85, fr 88, ja 91, pt-BR 85, pt-PT 85
//   total 2456 KB (the retired single ceiling was 2700)
// MAX_CODE_KB is 2120: ~9.6% headroom over 1934, the same convention the four
// bumps this file replaces used (2026-06-10, 06-20, 07-11, 07-27), now applied
// to a base that no longer carries 522 KB no browser fetches together. Against
// the old rule that is 238 KB of cover for a rogue dep cut to 186 KB, and —
// the point — it stays 186 KB however many languages ship.
// MAX_CATALOGUE_KB is 100: ~9.9% over the largest catalogue (ja). It moves when
// the KEY COUNT grows, which is payload growth for every reader, and never when
// the locale count grows, which is payload growth for none.
// MAX_LARGEST_CHUNK_KB stays 350, unchanged: 245 KB * the 33% headroom that
// number was always justified by is 326, so the existing figure still states
// the rule. What changed is the population it measures, not the ceiling.
// MAX_ASSET_KB is 100, the same per-file payload figure as a catalogue: ~35%
// over the largest asset (the subset font, 74 KB) and 20x over the largest
// prerendered page (5 KB). Assets re-measured after subsetting: 33 files and
// 266 KB gzipped in total (was 4058) — font 74 KB, icon-512 68, og-default 20,
// icon-192 11, apple-touch-icon 10, then the 16 HTML pages at 5 KB and below
// and everything else at 1.
//
// Run: `node scripts/check_web_bundle_budget.mjs` (after a production build of
//      apps/web — it reads build output, it does not produce any).
// CI:  the `build-web` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list (decisions § 775).
// Unit tests: `node --test scripts/check_web_bundle_budget.test.mjs`

import { appendFileSync, existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WEB_DIR = join(REPO_ROOT, 'apps', 'web');
export const BUILD_DIR = join(WEB_DIR, 'build');
export const CLIENT_MANIFEST = join(
	WEB_DIR,
	'.svelte-kit',
	'output',
	'client',
	'.vite',
	'manifest.json',
);
export const LOCALES_DIR = join(WEB_DIR, 'src', 'lib', 'i18n', 'locales');

export const MAX_CODE_KB = 2120;
export const MAX_CATALOGUE_KB = 100;
export const MAX_LARGEST_CHUNK_KB = 350;
export const MAX_ASSET_KB = 100;

/// Assets already over MAX_ASSET_KB, named one at a time with the ceiling each
/// is allowed and why. Vite content-hashes emitted assets, so the pattern skips
/// the hash segment — a font version bump keeps the same exemption, a font that
/// GROWS past `maxKb` does not.
///
/// An exemption that matches no emitted file fails the guard, and so does one
/// whose file now fits under MAX_ASSET_KB: a list of exemptions that has
/// stopped describing the build is cover for nothing.
/**
 * @typedef {{ pattern: RegExp, maxKb: number, why: string }} AssetExemption
 * @type {readonly AssetExemption[]}
 */
export const ASSET_EXEMPTIONS = [];

/// The manifest keys a catalogue by its source path. `pt-BR` carries a hyphen,
/// so the tag is everything between the directory and the extension.
export const CATALOGUE_SOURCE = /^src\/lib\/i18n\/locales\/([^/]+)\.ts$/;

/**
 * @typedef {{ file?: string }} ManifestEntry
 * @typedef {{ path: string, kb: number }} EmittedFile
 * @typedef {{ budget: string, message: string }} BudgetError
 */

/** @param {Buffer} buf */
export function gzipKb(buf) {
	return Math.ceil(gzipSync(buf).length / 1024);
}

/// locale tag -> emitted file, both as the manifest spells them.
/**
 * @param {Record<string, ManifestEntry>} manifest
 * @returns {Map<string, string>}
 */
export function catalogueChunks(manifest) {
	/** @type {Map<string, string>} */
	const out = new Map();
	for (const [source, entry] of Object.entries(manifest)) {
		const m = CATALOGUE_SOURCE.exec(source);
		if (!m || !entry?.file) continue;
		out.set(m[1], entry.file);
	}
	return out;
}

/** @param {string} dir */
export function localeTags(dir) {
	return readdirSync(dir)
		.filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'))
		.map((f) => f.slice(0, -3))
		.sort();
}

/// True for a file the CODE budget measures. Everything else the build emits —
/// fonts, images, prerendered HTML, the manifest — is an asset.
/** @param {string} path */
export function isCodeFile(path) {
	return path.endsWith('.js') || path.endsWith('.css');
}

/// EVERY emitted file, path relative to the build root and posix-spelled so it
/// compares against a manifest entry directly. The walk used to skip anything
/// that was not JS or CSS, which is how a 3866 KB font sat outside all three
/// ceilings; classification is checkBudgets' job, not the walk's.
/**
 * @param {string} root
 * @returns {EmittedFile[]}
 */
export function collectEmitted(root) {
	/** @type {EmittedFile[]} */
	const out = [];
	/** @param {string} dir */
	const walk = (dir) => {
		// Types come off the directory entry rather than a separate stat: a
		// stat-then-read pair is a check the read cannot rely on, and the build
		// output this walks is written by a concurrent vite process.
		const entries = readdirSync(dir, { withFileTypes: true });
		entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
		for (const entry of entries) {
			const abs = join(dir, entry.name);
			if (entry.isDirectory()) {
				walk(abs);
				continue;
			}
			out.push({
				path: abs.slice(root.length + 1).split(sep).join('/'),
				kb: gzipKb(readFileSync(abs)),
			});
		}
	};
	walk(root);
	return out;
}

/**
 * @param {{
 *   files: readonly EmittedFile[],
 *   catalogues: ReadonlyMap<string, string>,
 *   locales: readonly string[],
 *   maxCodeKb?: number,
 *   maxCatalogueKb?: number,
 *   maxLargestChunkKb?: number,
 *   maxAssetKb?: number,
 *   assetExemptions?: readonly AssetExemption[],
 * }} input
 */
export function checkBudgets({
	files,
	catalogues,
	locales,
	maxCodeKb = MAX_CODE_KB,
	maxCatalogueKb = MAX_CATALOGUE_KB,
	maxLargestChunkKb = MAX_LARGEST_CHUNK_KB,
	maxAssetKb = MAX_ASSET_KB,
	assetExemptions = ASSET_EXEMPTIONS,
}) {
	/** @type {BudgetError[]} */
	const errors = [];
	const byPath = new Map(files.map((f) => [f.path, f]));

	/** @type {{ locale: string, path: string, kb: number }[]} */
	const catalogueFiles = [];
	for (const [locale, path] of [...catalogues].sort()) {
		const emitted = byPath.get(path);
		if (!emitted) {
			errors.push({
				budget: 'classification',
				message:
					`the client manifest maps locale ${locale} to ${path}, which the build ` +
					`does not contain. The budget cannot tell code from translation, so no ` +
					`ceiling below means anything.`,
			});
			continue;
		}
		catalogueFiles.push({ locale, path, kb: emitted.kb });
	}

	const staticLocales = locales.filter((l) => !catalogues.has(l));
	if (staticLocales.length !== 1) {
		errors.push({
			budget: 'classification',
			message:
				`expected exactly one statically-bundled catalogue (the synchronous ` +
				`fallback every reader downloads); found ${staticLocales.length}` +
				`${staticLocales.length ? ` — ${staticLocales.join(', ')}` : ''}. The code ` +
				`ceiling is sized for one catalogue inside it, so a second one silently ` +
				`spends ~${maxCatalogueKb} KB of a budget meant for deps.`,
		});
	}

	const cataloguePaths = new Set(catalogueFiles.map((c) => c.path));
	const code = files.filter((f) => isCodeFile(f.path) && !cataloguePaths.has(f.path));
	const assets = files.filter((f) => !isCodeFile(f.path));
	const codeKb = code.reduce((sum, f) => sum + f.kb, 0);
	const catalogueKb = catalogueFiles.reduce((sum, c) => sum + c.kb, 0);
	const largest = code.reduce(
		(best, f) => (f.kb > best.kb ? f : best),
		/** @type {EmittedFile} */ ({ path: '', kb: 0 }),
	);

	if (codeKb > maxCodeKb) {
		errors.push({
			budget: 'code',
			message:
				`code is ${codeKb} KB gzipped, over the ${maxCodeKb} KB ceiling by ` +
				`${codeKb - maxCodeKb} KB. This is every byte a reader downloads whatever ` +
				`language they read in, so a new locale cannot have caused it — look for a ` +
				`new dependency or a duplicated one. Largest code chunk: ${largest.path} ` +
				`(${largest.kb} KB). Trim it, or raise MAX_CODE_KB in ` +
				`scripts/check_web_bundle_budget.mjs with the measurement that justifies it.`,
		});
	}

	for (const c of catalogueFiles) {
		if (c.kb <= maxCatalogueKb) continue;
		errors.push({
			budget: 'catalogue',
			message:
				`the ${c.locale} catalogue is ${c.kb} KB gzipped, over the ` +
				`${maxCatalogueKb} KB per-catalogue ceiling by ${c.kb - maxCatalogueKb} KB ` +
				`(${c.path}). This ceiling is per catalogue and never summed, so adding a ` +
				`language cannot trip it — either the key count grew for every locale, or ` +
				`this one catalogue carries something that is not translated text.`,
		});
	}

	if (largest.kb > maxLargestChunkKb) {
		errors.push({
			budget: 'largest-chunk',
			message:
				`the largest single code chunk is ${largest.kb} KB gzipped, over the ` +
				`${maxLargestChunkKb} KB ceiling by ${largest.kb - maxLargestChunkKb} KB ` +
				`(${largest.path}). Split it behind a dynamic import, or raise ` +
				`MAX_LARGEST_CHUNK_KB in scripts/check_web_bundle_budget.mjs.`,
		});
	}

	/** @type {Set<AssetExemption>} */
	const usedExemptions = new Set();
	for (const asset of assets) {
		const exemption = assetExemptions.find((e) => e.pattern.test(asset.path));
		if (!exemption) {
			if (asset.kb <= maxAssetKb) continue;
			errors.push({
				budget: 'asset',
				message:
					`${asset.path} is ${asset.kb} KB gzipped, over the ${maxAssetKb} KB ` +
					`per-asset ceiling by ${asset.kb - maxAssetKb} KB. This ceiling is per ` +
					`emitted file and never summed, so adding a page or an icon cannot trip ` +
					`it — one file got big. Shrink it (subset the font, re-encode the image, ` +
					`stop inlining data into the prerendered page), or name it in ` +
					`ASSET_EXEMPTIONS in scripts/check_web_bundle_budget.mjs with the ` +
					`measurement and the reason.`,
			});
			continue;
		}
		usedExemptions.add(exemption);
		if (asset.kb <= maxAssetKb) {
			errors.push({
				budget: 'asset-exemption',
				message:
					`${asset.path} is ${asset.kb} KB gzipped, which is under the ${maxAssetKb} KB ` +
					`ceiling every other asset is held to — it no longer needs the exemption ` +
					`carrying it. Delete that entry from ASSET_EXEMPTIONS in ` +
					`scripts/check_web_bundle_budget.mjs.`,
			});
			continue;
		}
		if (asset.kb > exemption.maxKb) {
			errors.push({
				budget: 'asset-exemption',
				message:
					`${asset.path} is ${asset.kb} KB gzipped, over its own ${exemption.maxKb} KB ` +
					`exemption ceiling by ${asset.kb - exemption.maxKb} KB. It is exempt from the ` +
					`${maxAssetKb} KB asset ceiling because ${exemption.why} — exempt from growing, ` +
					`it is not.`,
			});
		}
	}
	for (const exemption of assetExemptions) {
		if (usedExemptions.has(exemption)) continue;
		errors.push({
			budget: 'asset-exemption',
			message:
				`ASSET_EXEMPTIONS carries an entry for ${exemption.pattern} and the build emits ` +
				`no such file. An exemption that matches nothing is cover for nothing — the ` +
				`asset was removed or renamed. Delete the entry or correct its pattern.`,
		});
	}

	const largestAsset = assets.reduce(
		(best, f) => (f.kb > best.kb ? f : best),
		/** @type {EmittedFile} */ ({ path: '', kb: 0 }),
	);

	return {
		errors,
		summary: {
			codeKb,
			catalogueKb,
			catalogueFiles,
			largest,
			largestAsset,
			assetKb: assets.reduce((sum, f) => sum + f.kb, 0),
			assetFileCount: assets.length,
			fileCount: files.length,
			codeFileCount: code.length,
			maxCodeKb,
			maxCatalogueKb,
			maxLargestChunkKb,
			maxAssetKb,
		},
	};
}

/** @param {ReturnType<typeof checkBudgets>['summary']} s */
export function renderSummary(s) {
	const worst = s.catalogueFiles.reduce(
		(best, c) => (c.kb > best.kb ? c : best),
		{ locale: '—', path: '', kb: 0 },
	);
	return [
		'## Web bundle budget',
		'',
		'| Budget | Measured | Ceiling |',
		'|---|---|---|',
		`| Code (every reader, any language) | ${s.codeKb} KB across ${s.codeFileCount} files | ${s.maxCodeKb} KB |`,
		`| Largest single code chunk | ${s.largest.kb} KB | ${s.maxLargestChunkKb} KB |`,
		`| Largest message catalogue (${worst.locale}) | ${worst.kb} KB | ${s.maxCatalogueKb} KB, per catalogue |`,
		`| Largest single asset (font / image / prerendered page) | ${s.largestAsset.kb} KB | ${s.maxAssetKb} KB, per asset |`,
		'',
		`Catalogues are ungated in total (${s.catalogueKb} KB across ${s.catalogueFiles.length}, one fetched per reader): ` +
			s.catalogueFiles.map((c) => `${c.locale} ${c.kb} KB`).join(', ') + '.',
		'',
		`Assets are ungated in total too (${s.assetKb} KB across ${s.assetFileCount}, a reader loads one page and one icon).`,
		'',
		`Largest code chunk: \`${s.largest.path}\``,
		`Largest asset: \`${s.largestAsset.path}\``,
	].join('\n');
}

function main() {
	for (const [what, path] of [
		['build output', BUILD_DIR],
		['vite client manifest', CLIENT_MANIFEST],
	]) {
		if (existsSync(path)) continue;
		console.error(
			`::error::No ${what} at ${path}. Run a production build of apps/web first ` +
				`(\`npm run build --workspace=apps/web\`).`,
		);
		process.exit(1);
	}

	const files = collectEmitted(BUILD_DIR);
	const catalogues = catalogueChunks(JSON.parse(readFileSync(CLIENT_MANIFEST, 'utf8')));
	const locales = localeTags(LOCALES_DIR);
	const { errors, summary } = checkBudgets({ files, catalogues, locales });

	console.log(
		`Code (every reader, any language): ${summary.codeKb} KB across ` +
			`${summary.codeFileCount} files (ceiling ${summary.maxCodeKb} KB)`,
	);
	console.log(
		`Largest code chunk:                ${summary.largest.kb} KB — ` +
			`${summary.largest.path} (ceiling ${summary.maxLargestChunkKb} KB)`,
	);
	for (const c of summary.catalogueFiles) {
		console.log(
			`Catalogue ${c.locale.padEnd(24)} ${c.kb} KB (ceiling ` +
				`${summary.maxCatalogueKb} KB, per catalogue — never summed)`,
		);
	}
	console.log(
		`Largest asset:                     ${summary.largestAsset.kb} KB — ` +
			`${summary.largestAsset.path} (ceiling ${summary.maxAssetKb} KB per asset, ` +
			`never summed; ${summary.assetFileCount} assets, ${summary.assetKb} KB in total)`,
	);
	if (process.env.GITHUB_STEP_SUMMARY) {
		appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${renderSummary(summary)}\n`);
	}

	if (errors.length) {
		for (const e of errors) console.error(`::error::[${e.budget}] ${e.message}`);
		process.exit(1);
	}
	console.log(
		`Web bundle budget passed: code ${summary.codeKb}/${summary.maxCodeKb} KB, ` +
			`largest code chunk ${summary.largest.kb}/${summary.maxLargestChunkKb} KB, ` +
			`${summary.catalogueFiles.length} catalogues each under ${summary.maxCatalogueKb} KB, ` +
			`${summary.assetFileCount} assets each under ${summary.maxAssetKb} KB or a named exemption.`,
	);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();

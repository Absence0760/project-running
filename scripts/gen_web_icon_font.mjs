#!/usr/bin/env node
// Regenerates the web app's subset icon font from the vendored upstream one.
//
// Writes three committed artifacts and nothing else:
//   scripts/material_symbols_ligatures.txt          the upstream vocabulary
//   apps/web/src/lib/assets/material-symbols-subset.woff2   the shipped font
//   apps/web/src/lib/assets/material-symbols-subset.json    what is in it
//
// The selection rule, the axis pins and the reason the vocabulary is committed
// all live in scripts/web_icon_font.mjs, next to the code that applies them.
//
// fontTools does the font work. It is reached through whichever of these the
// machine has, in order: a `python3` that can already import it, then `uvx`,
// which fetches the pinned version into a throwaway environment (this is a
// developer-run generator, not a CI step -- CI verifies the committed output
// against the sources it was derived from, and needs no font tooling at all).
//
// Run: `node scripts/gen_web_icon_font.mjs`
// Verified by: `node --test scripts/web_icon_font.test.mjs`

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { mkdtempSync, rmSync } from 'node:fs';

import {
	ASSETS_DIR,
	LAYOUT_FEATURES,
	MANIFEST,
	PINNED_AXES,
	REPO_ROOT,
	SUBSET_FONT,
	UPSTREAM_FONT,
	UPSTREAM_PACKAGE,
	VOCABULARY_FILE,
	WEB_SRC,
	collectSources,
	parseVocabulary,
	selectIcons,
	sha256Bytes,
} from './web_icon_font.mjs';

export const FONTTOOLS_PIN = 'fonttools[woff]==4.62.0';
const PYTHON_SCRIPT = join(REPO_ROOT, 'scripts', 'material_symbols_subset.py');

/** @returns {string[]} argv prefix that runs a python with fontTools available */
function pythonRunner() {
	try {
		execFileSync('python3', ['-c', 'import fontTools'], { stdio: 'ignore' });
		return ['python3'];
	} catch {
		// fall through
	}
	try {
		execFileSync('uvx', ['--version'], { stdio: 'ignore' });
		return ['uvx', '--from', FONTTOOLS_PIN, 'python'];
	} catch {
		throw new Error(
			'This generator needs fontTools. Either `pipx install fonttools` / a venv ' +
				`with \`${FONTTOOLS_PIN}\` on \`python3\`, or \`uvx\` on PATH so it can be ` +
				'fetched into a throwaway environment.',
		);
	}
}

/**
 * @param {readonly string[]} runner
 * @param {readonly string[]} args
 * @returns {Record<string, unknown>}
 */
function runPython(runner, args) {
	const out = execFileSync(runner[0], [...runner.slice(1), PYTHON_SCRIPT, ...args], {
		encoding: 'utf8',
		stdio: ['ignore', 'pipe', 'inherit'],
	});
	return JSON.parse(out.trim().split('\n').at(-1) ?? '{}');
}

function main() {
	const runner = pythonRunner();
	const upstream = readFileSync(UPSTREAM_FONT);
	const upstreamVersion = JSON.parse(
		readFileSync(join(UPSTREAM_PACKAGE, 'package.json'), 'utf8'),
	).version;

	const vocabularyResult = runPython(runner, ['vocabulary', UPSTREAM_FONT, VOCABULARY_FILE]);
	const vocabulary = parseVocabulary(readFileSync(VOCABULARY_FILE, 'utf8'));
	console.log(`Vocabulary: ${vocabularyResult.count} ligatures -> ${VOCABULARY_FILE}`);

	const { icons, unrenderable, unreadable } = selectIcons(collectSources(WEB_SRC), vocabulary);
	for (const u of unreadable) {
		console.error(
			`::error::${u.path} carries \`${u.name}\` on an element whose content the ` +
				'extractor in scripts/web_icon_font.mjs cannot read a ligature out of. ' +
				'Extend CLASS_ATTRIBUTE / ELEMENT_TEXT before shipping that shape.',
		);
	}
	for (const u of unrenderable) {
		console.error(
			`::error::${u.path} renders \`${u.name}\`, which the upstream font has no ` +
				'ligature for. That icon is broken today; the subset cannot fix it.',
		);
	}
	if (unreadable.length || unrenderable.length) process.exit(1);

	const scratch = mkdtempSync(join(tmpdir(), 'icon-font-'));
	try {
		const request = join(scratch, 'request.json');
		writeFileSync(
			request,
			JSON.stringify({ icons, pinnedAxes: PINNED_AXES, layoutFeatures: LAYOUT_FEATURES }),
		);
		mkdirSync(ASSETS_DIR, { recursive: true });
		const result = runPython(runner, ['subset', UPSTREAM_FONT, SUBSET_FONT, request]);
		const subset = readFileSync(SUBSET_FONT);
		writeFileSync(
			MANIFEST,
			`${JSON.stringify(
				{
					generator: 'scripts/gen_web_icon_font.mjs',
					upstream: {
						package: `material-symbols@${upstreamVersion}`,
						file: 'material-symbols-outlined.woff2',
						bytes: upstream.length,
						sha256: sha256Bytes(upstream),
						ligatures: vocabularyResult.count,
					},
					pinnedAxes: PINNED_AXES,
					variableAxes: result.axes,
					layoutFeatures: LAYOUT_FEATURES,
					subset: {
						bytes: subset.length,
						sha256: sha256Bytes(subset),
						glyphs: result.glyphs,
						ligatures: result.ligaturesInSubset,
					},
					icons,
				},
				null,
				'\t',
			)}\n`,
		);
		const pct = (100 * (1 - subset.length / upstream.length)).toFixed(1);
		console.log(
			`Subset: ${icons.length} icons over ${result.glyphs} glyphs, ` +
				`${subset.length} bytes (${pct}% off ${upstream.length}) -> ${SUBSET_FONT}`,
		);
	} finally {
		rmSync(scratch, { recursive: true, force: true });
	}
}

if (process.argv[1] === new URL(import.meta.url).pathname) main();

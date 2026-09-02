#!/usr/bin/env node
// Guardrail: the committed accent-fold table is what its generator renders.
//
// `apps/mobile_android/lib/catalogue_fold_table.dart` is derived data — the
// answer web's `fold` computes at runtime from `normalize('NFD')` and the
// Unicode `Diacritic` property, which Dart's core library cannot compute at
// all. It is the second generated table in this repo after `age_grade_tables`,
// and it exists because the hand-written class it replaced left 14,719 code
// points folding differently on the two platforms with nothing able to see it
// (decisions § 852). A hand-edit, or a commit that forgot to re-run the
// generator, would put the pair straight back into that state.
//
// The comparison is byte-exact against a fresh render. That has two possible
// causes and the message below distinguishes them, because only one is a
// mistake: the file was edited or committed stale, OR this Node's Unicode
// tables have moved under the generator (a newer ICU folds more letters). The
// second is a real drift too — the committed table is then poorer than the web
// runtime beside it — and the repair for both is the same one command.
//
// What this guard does NOT check is that the generator still agrees with web's
// `fold`; both spell the fold out and only one of them is what ships to a
// browser. `apps/web/src/lib/segments/catalogue_fold_table.test.ts` is the rail
// that runs web's own implementation against this committed table.
//
// Run: `node scripts/check_catalogue_fold_table.mjs`
// CI:  the `parity-types` job in .github/workflows/ci.yml, which is in the
//      `CI gate` aggregator's `needs:` list.
// Unit tests: `node --test scripts/check_catalogue_fold_table.test.mjs`

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { OUTPUT_PATH, render } from './gen_catalogue_fold_table.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** The `kCatalogueFoldUnicodeVersion` line the generator stamps into the file. */
const VERSION_LINE = /const String kCatalogueFoldUnicodeVersion = '([^']*)';/;

/**
 * The Unicode version a rendered table says it came from, or null when the
 * stamp is gone — which is itself a finding, since the message below leans on
 * it to tell a stale commit from an ICU bump.
 *
 * @param {string} text
 * @returns {string | null}
 */
export function stampedUnicodeVersion(text) {
	const m = text.match(VERSION_LINE);
	return m === null ? null : m[1];
}

/**
 * @param {{ committed: string | null, fresh: string, runtimeUnicode: string }} input
 * @returns {string[]}
 */
export function describeDrift({ committed, fresh, runtimeUnicode }) {
	/** @type {string[]} */
	const errors = [];

	if (committed === null) {
		errors.push(
			`${OUTPUT_PATH} is missing. It is generated, not written: run ` +
				`\`node scripts/gen_catalogue_fold_table.mjs\` and commit it (and its ` +
				`apps/mobile_ios/lib/ mirror).`,
		);
		return errors;
	}

	const stamped = stampedUnicodeVersion(fresh);
	if (stamped === null) {
		errors.push(
			`the freshly rendered table carries no \`kCatalogueFoldUnicodeVersion\` line. ` +
				`The generator's output shape changed and this guard can no longer tell an ` +
				`ICU bump from a hand-edit; update it in the same change.`,
		);
	}

	if (committed === fresh) return errors;

	const committedVersion = stampedUnicodeVersion(committed);
	if (committedVersion !== null && committedVersion !== runtimeUnicode) {
		errors.push(
			`${OUTPUT_PATH} was generated from Unicode ${committedVersion} and this Node ` +
				`carries Unicode ${runtimeUnicode}. The table is derived from the runtime's ` +
				`own Unicode data, so a newer ICU folds letters the committed table leaves ` +
				`alone — which is drift against the web runtime beside it, not a false ` +
				`alarm.\n` +
				`  Re-run \`node scripts/gen_catalogue_fold_table.mjs\`, mirror the file into ` +
				`apps/mobile_ios/lib/, and commit both.`,
		);
		return errors;
	}

	errors.push(
		`${OUTPUT_PATH} is not what its generator renders, and both were read on ` +
			`Unicode ${runtimeUnicode} — so this is a hand-edit or a commit that skipped ` +
			`the generator, not an ICU bump.\n` +
			`  ${describeFirstDifference(committed, fresh)}\n` +
			`  Re-run \`node scripts/gen_catalogue_fold_table.mjs\`, mirror the file into ` +
			`apps/mobile_ios/lib/, and commit both. The table is derived data — decisions ` +
			`§ 852 — so it is never the thing to edit.`,
	);
	return errors;
}

/**
 * The first line the two renders disagree on, so the failure names a place
 * rather than a file.
 *
 * @param {string} committed
 * @param {string} fresh
 * @returns {string}
 */
export function describeFirstDifference(committed, fresh) {
	const a = committed.split('\n');
	const b = fresh.split('\n');
	for (let i = 0; i < Math.max(a.length, b.length); i++) {
		if (a[i] === b[i]) continue;
		return (
			`first difference at line ${i + 1}: committed ${JSON.stringify(a[i] ?? '<end of file>')}, ` +
			`generated ${JSON.stringify(b[i] ?? '<end of file>')}.`
		);
	}
	return 'the two renders differ in length but share every line.';
}

function main() {
	/** @type {string | null} */
	let committed = null;
	try {
		committed = readFileSync(join(REPO_ROOT, OUTPUT_PATH), 'utf8');
	} catch {
		committed = null;
	}

	const errors = describeDrift({
		committed,
		fresh: render(),
		runtimeUnicode: process.versions.unicode ?? 'unknown',
	});

	if (errors.length > 0) {
		for (const e of errors) console.error(e);
		process.exit(1);
	}
	console.log(`${OUTPUT_PATH} matches its generator (Unicode ${process.versions.unicode}).`);
}

if (process.argv[1] && import.meta.url === `file://${process.argv[1]}`) main();

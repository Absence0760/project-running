import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { stripComments } from '../../src/lib/core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');
const SIMULATE = join(HERE, 'simulate.ts');

/*
 * A run is one row and up to three Storage objects, and only `deleteRun`
 * knows all three.
 *
 * `insertRun` uploads `{user_id}/{run_id}.json.gz` for a `track` and
 * `{user_id}/{run_id}.hr.json.gz` for an `hrSeries`; `insertMatchedTrack`
 * uploads `{user_id}/{run_id}.matched.json.gz`. Each writes the path into a
 * column, and each column is what `deleteRun` reads back before it removes
 * the object. A spec that disposes of the run with
 * `admin.from('runs').delete()` instead takes the row — and, by cascade, the
 * `run_matched_tracks` row naming the third object — while every object it
 * pointed at stays in the `runs` bucket for the life of the local stack,
 * with nothing left that names them. `supabase db reset` does not clear
 * Storage either, so the debris outlives the schema it was seeded against.
 *
 * There is no offender today, which is the moment to state the rule: the
 * cost of it is one line at the point somebody adds the fourth object, and
 * the cost of not having it is a bucket nobody can attribute.
 *
 * **Nothing below is a list.** The helpers that upload, the option names
 * that make them upload, and the columns they write are all read out of
 * `simulate.ts`, so a fourth object added to `insertRun` — or a new helper
 * that uploads one — is covered without touching this file, and a helper
 * renamed here cannot leave the guard silently matching nothing. Each
 * derivation is asserted non-empty for exactly that reason: a scan that
 * finds nothing must fail rather than pass.
 */

const source = stripComments(readFileSync(SIMULATE, 'utf8'));

/** The body of a top-level `export async function`, by name. */
function exportedBody(name: string): string {
	const start = source.indexOf(`export async function ${name}(`);
	assert.ok(start >= 0, `simulate.ts no longer exports ${name} — this guard is reading a stale name.`);
	const next = source.indexOf('\nexport ', start + 1);
	return source.slice(start, next === -1 ? source.length : next);
}

const EXPORTED = /^export async function ([A-Za-z_$][\w$]*)\(/gm;

/** Every exported helper that puts an object in a Storage bucket. */
function uploadingHelpers(): string[] {
	const out: string[] = [];
	EXPORTED.lastIndex = 0;
	let match: RegExpExecArray | null;
	while ((match = EXPORTED.exec(source))) {
		const body = exportedBody(match[1]);
		if (/\.storage\s*\.?\s*[\s\S]{0,80}?\.upload\s*\(/.test(body)) out.push(match[1]);
	}
	return out;
}

/**
 * The caller-supplied option names that decide whether a helper uploads —
 * `opts.track` / `opts.hrSeries` today. A call passing none of them writes no
 * object and its run can be disposed of any way at all.
 */
function seedingOptions(helpers: string[]): string[] {
	const out = new Set<string>();
	for (const helper of helpers) {
		const body = exportedBody(helper);
		for (const [, option] of body.matchAll(/if\s*\(\s*opts\.([A-Za-z_$][\w$]*)/g)) {
			const guarded = body.slice(body.indexOf(`if (opts.${option}`));
			const closes = guarded.indexOf('\n\t}');
			if (/\.upload\s*\(/.test(guarded.slice(0, closes === -1 ? guarded.length : closes))) {
				out.add(option);
			}
		}
	}
	return [...out].sort();
}

/** The `*_url` columns those helpers write the object paths into. */
function pathColumns(helpers: string[]): string[] {
	const out = new Set<string>();
	for (const helper of helpers) {
		for (const [, column] of exportedBody(helper).matchAll(/\b([a-z_]+_url)\s*:/g)) out.add(column);
	}
	return [...out].sort();
}

const UPLOADERS = uploadingHelpers();
const SEEDS_BY = seedingOptions(UPLOADERS);
const PATH_COLUMNS = pathColumns(UPLOADERS);

test('the derivations that drive this guard found something', () => {
	assert.ok(
		UPLOADERS.length > 0,
		'No exported helper in simulate.ts uploads to Storage. Either the seeding moved, or the ' +
			'detection did — every assertion below is vacuous until this finds them again.'
	);
	assert.ok(
		SEEDS_BY.length > 0,
		`No option gates an upload in ${UPLOADERS.join(' / ')} — the guard would then treat every ` +
			'call as harmless and never report anything.'
	);
	assert.ok(
		PATH_COLUMNS.length > 0,
		'No *_url column is written by the uploading helpers — the disposer check below has nothing to compare.'
	);
});

test('deleteRun reads back every column an uploading helper writes a path into', () => {
	const disposer = exportedBody('deleteRun');
	assert.match(
		disposer,
		/\.storage[\s\S]{0,120}?\.remove\s*\(/,
		'deleteRun no longer removes anything from Storage — it is the only disposer that knows the object paths.'
	);
	const missing = PATH_COLUMNS.filter((column) => !disposer.includes(column));
	assert.deepEqual(
		missing,
		[],
		`These columns carry a Storage path written by ${UPLOADERS.join(' / ')} and deleteRun never ` +
			`reads them, so the objects they name are orphaned by every teardown: ${missing.join(', ')}. ` +
			'Add the read beside the others — a cascade takes the row, not the object.'
	);
});

const SCANNED = ['.ts', '.mjs'];

function scannedSources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) scannedSources(full, out);
		else if (SCANNED.some((ext) => full.endsWith(ext))) out.push(full);
	}
	return out;
}

/** Does this file call an uploading helper in a form that actually uploads? */
function seedsStorageBackedRun(text: string): boolean {
	for (const helper of UPLOADERS) {
		const call = new RegExp(`\\b${helper}\\s*\\(`, 'g');
		// The match object is never read -- `exec` advances `lastIndex`, which is
		// what the argument scan below walks from -- so binding it would be a
		// useless assignment.
		while (call.exec(text) !== null) {
			let depth = 1;
			let i = call.lastIndex;
			while (i < text.length && depth > 0) {
				if (text[i] === '(') depth++;
				else if (text[i] === ')') depth--;
				i++;
			}
			const args = text.slice(call.lastIndex, i - 1);
			// A spread carries options this scan cannot see, so it counts —
			// reporting a harmless call costs one `deleteRun`, missing a real
			// one costs an object nothing names.
			if (args.includes('...')) return true;
			if (SEEDS_BY.some((option) => new RegExp(`\\b${option}\\s*:`).test(args))) return true;
		}
	}
	return false;
}

/** Lines that delete a `runs` row without going through the disposer. */
function directRunDeleteLines(text: string): number[] {
	const hits: number[] = [];
	const table = /\.from\(\s*['"]runs['"]\s*\)/g;
	let match: RegExpExecArray | null;
	while ((match = table.exec(text))) {
		const rest = text.slice(match.index);
		const statement = rest.slice(0, rest.indexOf(';') === -1 ? rest.length : rest.indexOf(';'));
		if (/\.delete\s*\(/.test(statement)) hits.push(text.slice(0, match.index).split('\n').length);
	}
	return hits;
}

test('a spec that plants a run-scoped Storage object disposes of the run through deleteRun', () => {
	const offenders: string[] = [];
	for (const file of scannedSources(E2E_ROOT)) {
		const rel = relative(E2E_ROOT, file);
		if (rel === 'fixtures/simulate.ts' || rel === 'fixtures/storage-teardown.test.ts') continue;
		const text = stripComments(readFileSync(file, 'utf8'));
		if (!seedsStorageBackedRun(text)) continue;
		const hits = directRunDeleteLines(text);
		if (hits.length) offenders.push(`${rel}:${hits.join(',')}`);
	}
	assert.deepEqual(
		offenders,
		[],
		'These files seed a run with a Storage object behind it and then delete the row directly. ' +
			'The row goes, the cascade takes run_matched_tracks with it, and the gzipped objects stay ' +
			`in the runs bucket with nothing left naming them. Call deleteRun instead — it is the only ` +
			`caller that knows all of ${PATH_COLUMNS.join(', ')}: ${offenders.join(' ')}`
	);
});

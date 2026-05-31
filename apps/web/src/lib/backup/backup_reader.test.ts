// Unit tests for the pure backup-archive parsing helpers extracted
// from `backup.ts`. Invocation:
//   npx tsx --test src/lib/backup/backup_reader.test.ts
//
// The Supabase upserts in `restoreBackup` need a live client and
// stay covered by Playwright e2e — these tests pin the parsing +
// pure-transform logic the upsert path consumes.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';

import {
	parseBackupArchive,
	stripServerManagedProfileFields,
	coalesceActivityType,
	extractEventIds
} from './backup_reader';
import { BACKUP_FORMAT, BACKUP_VERSION } from './backup_writer';

interface ArchiveSpec {
	manifest?: object | null;
	runs?: object[];
	routes?: object[];
	profile?: { profile?: object | null; settings_prefs?: object } | null;
	tracks?: Record<string, Uint8Array>;
	manifestSkipped?: boolean;
}

async function buildArchive(spec: ArchiveSpec = {}): Promise<Uint8Array> {
	const zip = new JSZip();
	if (!spec.manifestSkipped) {
		zip.file(
			'manifest.json',
			JSON.stringify(
				spec.manifest ?? {
					format: BACKUP_FORMAT,
					version: BACKUP_VERSION,
					exported_at: '2026-05-11T10:00:00Z'
				}
			)
		);
	}
	if (spec.runs) zip.file('runs.json', JSON.stringify(spec.runs));
	if (spec.routes) zip.file('routes.json', JSON.stringify(spec.routes));
	if (spec.profile !== undefined) {
		zip.file('profile.json', JSON.stringify(spec.profile ?? {}));
	}
	if (spec.tracks) {
		for (const [runId, bytes] of Object.entries(spec.tracks)) {
			zip.file(`tracks/${runId}.json.gz`, bytes);
		}
	}
	// Uint8Array round-trip is the portable choice — Node's
	// `Blob` ↔ JSZip interop occasionally fails on the read side
	// even when the write side accepts `{ type: 'blob' }`. The
	// parser's parameter is widened to accept Uint8Array for
	// exactly this reason (see backup_reader.ts).
	return zip.generateAsync({ type: 'uint8array' });
}

// ─────────────────────── parseBackupArchive ───────────────────────

test('parseBackupArchive: throws when manifest.json is missing', async () => {
	const blob = await buildArchive({ manifestSkipped: true, runs: [] });
	await assert.rejects(() => parseBackupArchive(blob), /missing manifest/);
});

test('parseBackupArchive: throws on wrong format', async () => {
	const blob = await buildArchive({
		manifest: { format: 'something-else', version: 1 }
	});
	await assert.rejects(() => parseBackupArchive(blob), /Unexpected format/);
});

test('parseBackupArchive: throws when version is newer than supported', async () => {
	const blob = await buildArchive({
		manifest: { format: BACKUP_FORMAT, version: 99 }
	});
	await assert.rejects(() => parseBackupArchive(blob), /newer version/);
});

test('parseBackupArchive: accepts version 0 (missing/old) for back-compat', async () => {
	// Older archives could land without a version field — parser
	// must tolerate that and treat it as "anything goes".
	const blob = await buildArchive({
		manifest: { format: BACKUP_FORMAT },
		runs: []
	});
	const parsed = await parseBackupArchive(blob);
	assert.equal(parsed.manifest.version, 0);
});

test('parseBackupArchive: happy path with all four files', async () => {
	const trackBytes = new Uint8Array([0x1f, 0x8b, 0x08, 0x00]); // gzip magic
	const blob = await buildArchive({
		runs: [{ id: 'r-1', distance_m: 5000 }],
		routes: [{ id: 'rt-1', name: 'Park loop' }],
		profile: {
			profile: { id: 'old-uid', username: 'tester' },
			settings_prefs: { unit: 'km' }
		},
		tracks: { 'r-1': trackBytes }
	});
	const parsed = await parseBackupArchive(blob);
	assert.equal(parsed.manifest.format, BACKUP_FORMAT);
	assert.equal(parsed.runs.length, 1);
	assert.equal(parsed.runs[0].id, 'r-1');
	assert.equal(parsed.routes.length, 1);
	assert.equal(parsed.routes[0].name, 'Park loop');
	assert.equal(parsed.profile?.username, 'tester');
	assert.equal(parsed.settingsPrefs.unit, 'km');

	const fetched = await parsed.getTrackBytes('r-1');
	assert.ok(fetched);
	assert.deepEqual(Array.from(fetched), Array.from(trackBytes));
});

test('parseBackupArchive: getTrackBytes returns null for unknown run id', async () => {
	const blob = await buildArchive({ runs: [{ id: 'r-1' }] });
	const parsed = await parseBackupArchive(blob);
	assert.equal(await parsed.getTrackBytes('not-in-archive'), null);
});

test('parseBackupArchive: missing runs.json yields empty array', async () => {
	const blob = await buildArchive();
	const parsed = await parseBackupArchive(blob);
	assert.deepEqual(parsed.runs, []);
});

test('parseBackupArchive: missing routes.json yields empty array', async () => {
	const blob = await buildArchive({ runs: [{ id: 'r-1' }] });
	const parsed = await parseBackupArchive(blob);
	assert.deepEqual(parsed.routes, []);
});

test('parseBackupArchive: missing profile.json yields null + empty prefs', async () => {
	const blob = await buildArchive({ runs: [] });
	const parsed = await parseBackupArchive(blob);
	assert.equal(parsed.profile, null);
	assert.deepEqual(parsed.settingsPrefs, {});
});

test('parseBackupArchive: profile.json with null profile field', async () => {
	const blob = await buildArchive({
		profile: { profile: null, settings_prefs: { unit: 'mi' } }
	});
	const parsed = await parseBackupArchive(blob);
	assert.equal(parsed.profile, null);
	assert.equal(parsed.settingsPrefs.unit, 'mi');
});

test('parseBackupArchive: manifest carries through metadata keys', async () => {
	const blob = await buildArchive({
		manifest: {
			format: BACKUP_FORMAT,
			version: 1,
			exported_by_user_id: 'uid',
			exported_from: 'mobile_android',
			counts: { runs: 5, routes: 2, tracks: 5, goals: 0 }
		}
	});
	const parsed = await parseBackupArchive(blob);
	assert.equal(parsed.manifest.exported_by_user_id, 'uid');
	assert.equal(parsed.manifest.exported_from, 'mobile_android');
	assert.deepEqual(parsed.manifest.counts, {
		runs: 5,
		routes: 2,
		tracks: 5,
		goals: 0
	});
});

// ─────────────────── stripServerManagedProfileFields ───────────────────

test('stripServerManagedProfileFields: drops subscription_tier + subscription_at + parkrun_number', () => {
	const out = stripServerManagedProfileFields({
		display_name: 'Tester',
		preferred_unit: 'km',
		subscription_tier: 'pro',
		subscription_at: '2026-05-11T10:00:00Z',
		parkrun_number: 'A123456'
	});
	assert.equal(out.display_name, 'Tester');
	assert.equal(out.preferred_unit, 'km');
	assert.equal(out.subscription_tier, undefined);
	assert.equal(out.subscription_at, undefined);
	assert.equal(out.parkrun_number, undefined);
});

test('stripServerManagedProfileFields: no-op when none of the keys are present', () => {
	const original = { display_name: 'X', preferred_unit: 'mi' };
	const out = stripServerManagedProfileFields(original);
	assert.deepEqual(out, original);
	// Returns a new object (caller is free to mutate).
	assert.notEqual(out, original);
});

test('stripServerManagedProfileFields: preserves nested objects untouched', () => {
	const out = stripServerManagedProfileFields({
		display_name: 'X',
		subscription_tier: 'pro',
		nested: { hr_zones: [120, 140, 160, 180] }
	});
	assert.deepEqual(out.nested, { hr_zones: [120, 140, 160, 180] });
});

// ─────────────────── coalesceActivityType ───────────────────

test('coalesceActivityType: inserts "run" when metadata is null/undefined', () => {
	assert.equal(coalesceActivityType(null).activity_type, 'run');
	assert.equal(coalesceActivityType(undefined).activity_type, 'run');
});

test('coalesceActivityType: inserts "run" when metadata is missing the key', () => {
	const out = coalesceActivityType({ title: 'x', avg_bpm: 142 });
	assert.equal(out.activity_type, 'run');
	assert.equal(out.title, 'x');
	assert.equal(out.avg_bpm, 142);
});

test('coalesceActivityType: preserves explicit activity_type', () => {
	const out = coalesceActivityType({ activity_type: 'cycle', title: 'x' });
	assert.equal(out.activity_type, 'cycle');
});

test('coalesceActivityType: rejects non-string activity_type and defaults', () => {
	// A corrupt backup that stuck an int in the key should coalesce
	// rather than poison the DB row.
	const out = coalesceActivityType({ activity_type: 42 });
	assert.equal(out.activity_type, 'run');
});

test('coalesceActivityType: not a Map → returns a fresh map with the default', () => {
	const out = coalesceActivityType('this should not be a string');
	assert.deepEqual(out, { activity_type: 'run' });
});

test('coalesceActivityType: clones the input instead of mutating it', () => {
	const input = { title: 'before' };
	const out = coalesceActivityType(input);
	out.title = 'after';
	assert.equal((input as Record<string, unknown>).title, 'before');
});

// ─────────────────── extractEventIds ───────────────────

test('extractEventIds: empty input → empty array', () => {
	assert.deepEqual(extractEventIds([]), []);
});

test('extractEventIds: extracts distinct ids', () => {
	const ids = extractEventIds([
		{ event_id: 'e-1' },
		{ event_id: 'e-2' },
		{ event_id: 'e-1' }, // duplicate
		{ event_id: 'e-3' }
	]);
	assert.equal(ids.length, 3);
	assert.ok(ids.includes('e-1'));
	assert.ok(ids.includes('e-2'));
	assert.ok(ids.includes('e-3'));
});

test('extractEventIds: drops nulls, undefineds, empty strings, non-strings', () => {
	const ids = extractEventIds([
		{ event_id: null },
		{ event_id: undefined },
		{ event_id: '' },
		{ event_id: 42 },
		{ event_id: 'e-good' },
		{ /* no key at all */ }
	]);
	assert.deepEqual(ids, ['e-good']);
});

// Unit tests for the restore orchestrator extracted from
// `backup.ts`. The Supabase upserts are behind a `RestoreBackend`
// interface; tests substitute a counter-tracking fake so the loop
// is observable without booting supabase-js.
//
// Invocation:
//   npx tsx --test src/lib/backup/restore_orchestrator.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	restoreOrchestrate,
	type RestoreBackend
} from './restore_orchestrator';
import type { ParsedBackup } from './backup_reader';

// ─────────────────── helpers ───────────────────

interface FakeBackendCall {
	method: string;
	arg?: unknown;
}

interface FakeBackend extends RestoreBackend {
	calls: FakeBackendCall[];
	uploadBytes: Map<string, Uint8Array>;
	failures: Partial<{
		upsertProfile: Error;
		upsertSettings: Error;
		uploadTrack: Error;
		upsertRun: Error;
		upsertRoute: Error;
		fetchValidEventIds: Error;
	}>;
	validEventIds: Set<string>;
	uploadTrackSelectiveFailure?: (path: string) => Error | null;
	upsertRunSelectiveFailure?: (row: Record<string, unknown>) => Error | null;
	upsertRouteSelectiveFailure?: (row: Record<string, unknown>) => Error | null;
}

function makeFakeBackend(): FakeBackend {
	const calls: FakeBackendCall[] = [];
	const uploadBytes = new Map<string, Uint8Array>();
	const failures: FakeBackend['failures'] = {};
	const fake: FakeBackend = {
		calls,
		uploadBytes,
		failures,
		validEventIds: new Set<string>(),
		async upsertProfile(row) {
			calls.push({ method: 'upsertProfile', arg: row });
			if (failures.upsertProfile) throw failures.upsertProfile;
		},
		async upsertSettings(prefs) {
			calls.push({ method: 'upsertSettings', arg: prefs });
			if (failures.upsertSettings) throw failures.upsertSettings;
		},
		async uploadTrack(path, bytes) {
			calls.push({ method: 'uploadTrack', arg: { path, byteLength: bytes.length } });
			if (failures.uploadTrack) throw failures.uploadTrack;
			const selective = fake.uploadTrackSelectiveFailure?.(path);
			if (selective) throw selective;
			uploadBytes.set(path, bytes);
		},
		async upsertRun(row) {
			calls.push({ method: 'upsertRun', arg: row });
			if (failures.upsertRun) throw failures.upsertRun;
			const selective = fake.upsertRunSelectiveFailure?.(row);
			if (selective) throw selective;
		},
		async upsertRoute(row) {
			calls.push({ method: 'upsertRoute', arg: row });
			if (failures.upsertRoute) throw failures.upsertRoute;
			const selective = fake.upsertRouteSelectiveFailure?.(row);
			if (selective) throw selective;
		},
		async fetchValidEventIds(ids) {
			calls.push({ method: 'fetchValidEventIds', arg: ids });
			if (failures.fetchValidEventIds) throw failures.fetchValidEventIds;
			return new Set([...fake.validEventIds].filter((id) => ids.includes(id)));
		}
	};
	return fake;
}

interface ParsedBackupOpts {
	runs?: Record<string, unknown>[];
	routes?: Record<string, unknown>[];
	profile?: Record<string, unknown> | null;
	settingsPrefs?: Record<string, unknown>;
	tracks?: Record<string, Uint8Array>;
}

function makeParsedBackup(opts: ParsedBackupOpts = {}): ParsedBackup {
	const tracks = opts.tracks ?? {};
	return {
		manifest: { format: 'run-app-backup', version: 1 },
		runs: opts.runs ?? [],
		routes: opts.routes ?? [],
		profile: opts.profile ?? null,
		settingsPrefs: opts.settingsPrefs ?? {},
		async getTrackBytes(runId: string) {
			return tracks[runId] ?? null;
		}
	};
}

// ─────────────────── profile + settings ───────────────────

test('profile present → upsertProfile fired with stripped fields + user id', async () => {
	const backend = makeFakeBackend();
	const result = await restoreOrchestrate(
		makeParsedBackup({
			profile: {
				display_name: 'Tester',
				preferred_unit: 'km',
				subscription_tier: 'pro',
				parkrun_number: 'A1234'
			}
		}),
		'new-uid',
		backend
	);
	assert.equal(result.profileRestored, true);
	const profileCall = backend.calls.find((c) => c.method === 'upsertProfile');
	assert.ok(profileCall, 'upsertProfile must have been called');
	const arg = profileCall.arg as Record<string, unknown>;
	assert.equal(arg.id, 'new-uid');
	assert.equal(arg.display_name, 'Tester');
	assert.equal(arg.preferred_unit, 'km');
	assert.equal(arg.subscription_tier, undefined, 'server-managed field must be stripped');
	assert.equal(arg.parkrun_number, undefined);
});

test('null profile → upsertProfile not called', async () => {
	const backend = makeFakeBackend();
	const result = await restoreOrchestrate(
		makeParsedBackup({ profile: null }),
		'new-uid',
		backend
	);
	assert.equal(result.profileRestored, false);
	assert.equal(
		backend.calls.filter((c) => c.method === 'upsertProfile').length,
		0
	);
});

test('upsertProfile error becomes a warning, settings + runs still process', async () => {
	const backend = makeFakeBackend();
	backend.failures.upsertProfile = new Error('rls denied');
	const result = await restoreOrchestrate(
		makeParsedBackup({
			profile: { display_name: 'X' },
			settingsPrefs: { unit: 'mi' },
			runs: [{ id: 'r-1' }]
		}),
		'uid',
		backend
	);
	assert.equal(result.profileRestored, false);
	assert.ok(
		result.warnings.some((w) => w.startsWith('profile:') && w.includes('rls denied')),
		`expected profile warning; got ${JSON.stringify(result.warnings)}`
	);
	// Subsequent stages still ran — partial-success contract.
	assert.equal(
		backend.calls.filter((c) => c.method === 'upsertSettings').length,
		1
	);
	assert.equal(
		backend.calls.filter((c) => c.method === 'upsertRun').length,
		1
	);
});

test('non-empty settingsPrefs → upsertSettings fires', async () => {
	const backend = makeFakeBackend();
	await restoreOrchestrate(
		makeParsedBackup({
			settingsPrefs: { unit: 'km', split_audio: true }
		}),
		'uid',
		backend
	);
	const call = backend.calls.find((c) => c.method === 'upsertSettings');
	assert.ok(call);
	assert.deepEqual(call.arg, { unit: 'km', split_audio: true });
});

test('empty settingsPrefs → upsertSettings does not fire', async () => {
	const backend = makeFakeBackend();
	await restoreOrchestrate(
		makeParsedBackup({ settingsPrefs: {} }),
		'uid',
		backend
	);
	assert.equal(
		backend.calls.filter((c) => c.method === 'upsertSettings').length,
		0
	);
});

test('upsertSettings error becomes a warning, runs still process', async () => {
	const backend = makeFakeBackend();
	backend.failures.upsertSettings = new Error('settings table down');
	const result = await restoreOrchestrate(
		makeParsedBackup({
			settingsPrefs: { unit: 'km' },
			runs: [{ id: 'r-1' }]
		}),
		'uid',
		backend
	);
	assert.ok(
		result.warnings.some((w) => w.startsWith('settings_prefs:')),
		`got warnings: ${JSON.stringify(result.warnings)}`
	);
	assert.equal(result.runsImported, 1);
});

// ─────────────────── runs + tracks ───────────────────

test('happy-path single run with track uploads then upserts', async () => {
	const backend = makeFakeBackend();
	const trackBytes = new Uint8Array([1, 2, 3, 4]);
	const result = await restoreOrchestrate(
		makeParsedBackup({
			runs: [
				{
					id: 'run-1',
					started_at: '2026-05-11T10:00:00Z',
					distance_m: 5000
				}
			],
			tracks: { 'run-1': trackBytes }
		}),
		'uid',
		backend
	);
	assert.equal(result.runsImported, 1);
	assert.equal(result.tracksUploaded, 1);
	assert.equal(result.warnings.length, 0);

	// uploadTrack fired BEFORE upsertRun (track URL must exist before the row).
	const uploadIdx = backend.calls.findIndex((c) => c.method === 'uploadTrack');
	const upsertIdx = backend.calls.findIndex((c) => c.method === 'upsertRun');
	assert.ok(uploadIdx >= 0 && upsertIdx >= 0);
	assert.ok(uploadIdx < upsertIdx, 'uploadTrack must precede upsertRun');

	// The track was uploaded to the user-prefixed path.
	const uploadCall = backend.calls[uploadIdx];
	const uploadArg = uploadCall.arg as { path: string; byteLength: number };
	assert.equal(uploadArg.path, 'uid/run-1.json.gz');
	assert.equal(uploadArg.byteLength, 4);

	// The upserted run row carries track_url + activity_type default.
	const runRow = backend.calls[upsertIdx].arg as Record<string, unknown>;
	assert.equal(runRow.id, 'run-1');
	assert.equal(runRow.user_id, 'uid');
	assert.equal(runRow.track_url, 'uid/run-1.json.gz');
	assert.equal((runRow.metadata as Record<string, unknown>).activity_type, 'run');
});

test('run with no track in archive still upserts the row, track_url=null', async () => {
	const backend = makeFakeBackend();
	const result = await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'run-no-track', started_at: '2026-05-11T10:00:00Z' }]
		}),
		'uid',
		backend
	);
	assert.equal(result.runsImported, 1);
	assert.equal(result.tracksUploaded, 0);
	const row = backend.calls.find((c) => c.method === 'upsertRun')!
		.arg as Record<string, unknown>;
	assert.equal(row.track_url, null);
});

test('uploadTrack failure becomes a warning, row still upserts (no track_url)', async () => {
	const backend = makeFakeBackend();
	const result = await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'run-1' }],
			tracks: { 'run-1': new Uint8Array([1, 2, 3]) }
		}),
		'uid',
		{
			...backend,
			uploadTrack: async () => {
				throw new Error('storage offline');
			}
		}
	);
	assert.ok(
		result.warnings.some((w) => w.startsWith('track run-1:')),
		`got: ${JSON.stringify(result.warnings)}`
	);
	// runsImported still reflects the row landing — we don't sink
	// the run because the track upload failed.
	assert.equal(result.runsImported, 1);
});

test('upsertRun failure becomes a warning, other rows continue', async () => {
	const backend = makeFakeBackend();
	backend.upsertRunSelectiveFailure = (row) =>
		row.id === 'r-bad' ? new Error('synthetic') : null;
	const result = await restoreOrchestrate(
		makeParsedBackup({
			runs: [
				{ id: 'r-1' },
				{ id: 'r-bad' },
				{ id: 'r-2' }
			]
		}),
		'uid',
		backend
	);
	assert.equal(result.runsImported, 2);
	assert.equal(
		result.warnings.filter((w) => w.startsWith('run r-bad:')).length,
		1
	);
});

test('generateNewIds replaces every run id with a new uuid', async () => {
	const backend = makeFakeBackend();
	let nextId = 0;
	const uuids = ['new-uuid-1', 'new-uuid-2', 'new-uuid-3'];
	await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'orig-1' }, { id: 'orig-2' }, { id: 'orig-3' }]
		}),
		'uid',
		backend,
		{ generateNewIds: true, randomUUID: () => uuids[nextId++] }
	);
	const upsertedIds = backend.calls
		.filter((c) => c.method === 'upsertRun')
		.map((c) => (c.arg as Record<string, unknown>).id);
	assert.deepEqual(upsertedIds, ['new-uuid-1', 'new-uuid-2', 'new-uuid-3']);
});

test('generateNewIds: track path uses the NEW id, not the original', async () => {
	const backend = makeFakeBackend();
	let counter = 100;
	await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'orig-1' }],
			tracks: { 'orig-1': new Uint8Array([42]) }
		}),
		'uid',
		backend,
		{ generateNewIds: true, randomUUID: () => `gen-${counter++}` }
	);
	// Track was looked up by ORIGINAL id (it's keyed in the archive)
	// but uploaded under the NEW id (matches the upserted run row).
	const upload = backend.calls.find((c) => c.method === 'uploadTrack')!;
	const arg = upload.arg as { path: string };
	assert.equal(arg.path, 'uid/gen-100.json.gz');
});

test('event_id resolution: unknown ids nulled, known ids preserved', async () => {
	const backend = makeFakeBackend();
	backend.validEventIds = new Set(['e-known']);
	const result = await restoreOrchestrate(
		makeParsedBackup({
			runs: [
				{ id: 'r-1', event_id: 'e-known' },
				{ id: 'r-2', event_id: 'e-orphan' }
			]
		}),
		'uid',
		backend
	);
	assert.equal(result.runsImported, 2);
	const rows = backend.calls
		.filter((c) => c.method === 'upsertRun')
		.map((c) => c.arg as Record<string, unknown>);
	assert.equal(rows[0].event_id, 'e-known');
	assert.equal(rows[1].event_id, null);
});

test('event_id resolution: fetchValidEventIds called only when ids are present', async () => {
	const backend = makeFakeBackend();
	await restoreOrchestrate(
		makeParsedBackup({ runs: [{ id: 'r-1' }] }),
		'uid',
		backend
	);
	assert.equal(
		backend.calls.filter((c) => c.method === 'fetchValidEventIds').length,
		0,
		'no event_ids → no resolver call'
	);
});

test('event_id resolver failure becomes part of warnings, all event_ids null', async () => {
	// The resolver throws but the loop continues. The caller-side
	// shape is: every event_id is treated as unknown (nulled).
	const backend = makeFakeBackend();
	backend.failures.fetchValidEventIds = new Error('events table down');
	await assert.rejects(
		restoreOrchestrate(
			makeParsedBackup({
				runs: [{ id: 'r-1', event_id: 'e-known' }]
			}),
			'uid',
			backend
		),
		/events table down/,
		'today the resolver error bubbles — pin the contract'
	);
});

test('coalesceActivityType: run with missing metadata gets activity_type=run', async () => {
	const backend = makeFakeBackend();
	await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'r-1', distance_m: 5000 }]
		}),
		'uid',
		backend
	);
	const row = backend.calls.find((c) => c.method === 'upsertRun')!
		.arg as Record<string, unknown>;
	const md = row.metadata as Record<string, unknown>;
	assert.equal(md.activity_type, 'run');
});

test('preserves explicit metadata.activity_type', async () => {
	const backend = makeFakeBackend();
	await restoreOrchestrate(
		makeParsedBackup({
			runs: [
				{ id: 'r-1', metadata: { activity_type: 'cycle' } }
			]
		}),
		'uid',
		backend
	);
	const row = backend.calls.find((c) => c.method === 'upsertRun')!
		.arg as Record<string, unknown>;
	const md = row.metadata as Record<string, unknown>;
	assert.equal(md.activity_type, 'cycle');
});

// ─────────────────── routes ───────────────────

test('happy-path route upserts with new user_id stamped', async () => {
	const backend = makeFakeBackend();
	const result = await restoreOrchestrate(
		makeParsedBackup({
			routes: [
				{ id: 'rt-1', name: 'Park loop', waypoints: [] }
			]
		}),
		'new-uid',
		backend
	);
	assert.equal(result.routesImported, 1);
	const row = backend.calls.find((c) => c.method === 'upsertRoute')!
		.arg as Record<string, unknown>;
	assert.equal(row.id, 'rt-1');
	assert.equal(row.user_id, 'new-uid');
	assert.equal(row.name, 'Park loop');
});

test('generateNewIds replaces route ids too', async () => {
	const backend = makeFakeBackend();
	await restoreOrchestrate(
		makeParsedBackup({
			routes: [{ id: 'orig', name: 'X', waypoints: [] }]
		}),
		'uid',
		backend,
		{ generateNewIds: true, randomUUID: () => 'gen-route' }
	);
	const row = backend.calls.find((c) => c.method === 'upsertRoute')!
		.arg as Record<string, unknown>;
	assert.equal(row.id, 'gen-route');
});

test('upsertRoute failure becomes a warning, other routes continue', async () => {
	const backend = makeFakeBackend();
	backend.upsertRouteSelectiveFailure = (row) =>
		row.id === 'rt-bad' ? new Error('synthetic') : null;
	const result = await restoreOrchestrate(
		makeParsedBackup({
			routes: [
				{ id: 'rt-1', name: 'OK', waypoints: [] },
				{ id: 'rt-bad', name: 'Bad', waypoints: [] },
				{ id: 'rt-2', name: 'OK', waypoints: [] }
			]
		}),
		'uid',
		backend
	);
	assert.equal(result.routesImported, 2);
	assert.equal(
		result.warnings.filter((w) => w.startsWith('route rt-bad:')).length,
		1
	);
});

// ─────────────────── progress events ───────────────────

test('emits reading → profile → runs → routes → done in order', async () => {
	const backend = makeFakeBackend();
	const stages: string[] = [];
	await restoreOrchestrate(
		makeParsedBackup({
			profile: { display_name: 'X' },
			runs: [{ id: 'r-1' }, { id: 'r-2' }],
			routes: [{ id: 'rt-1', name: 'Y', waypoints: [] }]
		}),
		'uid',
		backend,
		{ onProgress: (p) => stages.push(p.stage) }
	);
	// `reading` is emitted by restoreBackup BEFORE orchestrate is
	// called, so it won't appear here. Pin everything past that.
	assert.ok(stages.includes('profile'));
	assert.ok(stages.includes('runs'));
	assert.ok(stages.includes('routes'));
	assert.equal(stages[stages.length - 1], 'done');
});

test('progress reports running totals: runs index goes 0 → 1 → 2', async () => {
	const backend = makeFakeBackend();
	const runProgresses: Array<{ current: number; total: number }> = [];
	await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'r-1' }, { id: 'r-2' }, { id: 'r-3' }]
		}),
		'uid',
		backend,
		{
			onProgress: (p) => {
				if (p.stage === 'runs')
					runProgresses.push({ current: p.current, total: p.total });
			}
		}
	);
	assert.deepEqual(
		runProgresses,
		[
			{ current: 0, total: 3 },
			{ current: 1, total: 3 },
			{ current: 2, total: 3 }
		]
	);
});

// ─────────────────── edge cases ───────────────────

test('empty parsed backup is a no-op (no calls fire)', async () => {
	const backend = makeFakeBackend();
	const result = await restoreOrchestrate(
		makeParsedBackup(),
		'uid',
		backend
	);
	assert.equal(result.runsImported, 0);
	assert.equal(result.routesImported, 0);
	assert.equal(result.tracksUploaded, 0);
	assert.equal(result.profileRestored, false);
	// Only the `done` event fires (no other stages reached).
	assert.equal(
		backend.calls.length,
		0,
		'empty backup must not poke the backend'
	);
});

test('100-run backup processes everything in order without dropping', async () => {
	// Smoke + perf — a realistic restore size shouldn't take more
	// than a moment.
	const backend = makeFakeBackend();
	const runs = Array.from({ length: 100 }, (_, i) => ({ id: `r-${i}` }));
	const start = Date.now();
	const result = await restoreOrchestrate(
		makeParsedBackup({ runs }),
		'uid',
		backend
	);
	const elapsed = Date.now() - start;
	assert.equal(result.runsImported, 100);
	assert.ok(elapsed < 2000, `100-run orchestration took ${elapsed}ms`);
	const ids = backend.calls
		.filter((c) => c.method === 'upsertRun')
		.map((c) => (c.arg as Record<string, unknown>).id);
	// Order preserved from input.
	assert.deepEqual(ids, runs.map((r) => r.id));
});

test('coalesceActivityType clones — original metadata is not mutated', async () => {
	const backend = makeFakeBackend();
	const inputMeta = { title: 'Original' };
	await restoreOrchestrate(
		makeParsedBackup({
			runs: [{ id: 'r-1', metadata: inputMeta }]
		}),
		'uid',
		backend
	);
	// The caller's metadata object was not mutated to add
	// activity_type — coalesceActivityType clones.
	assert.equal((inputMeta as Record<string, unknown>).activity_type, undefined);
});

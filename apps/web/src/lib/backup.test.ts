// Unit tests for the streaming + parallel-download web backup writer.
// Invocation:
//   npx tsx --test src/lib/backup.test.ts
//
// The writer is pulled out of `createBackup` as `buildBackupZip` so the
// streaming contract is testable without booting supabase-js. The
// fetcher seam lets us count concurrent calls + simulate partial
// failures.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';

import { buildBackupZip, BACKUP_FORMAT, BACKUP_VERSION } from './backup_writer';

function gzipOf(_payload: object): Uint8Array {
	// Tests don't actually need real gzip — the writer treats track
	// bytes as opaque (level: 0 = STORE). Any bytes round-trip.
	return new TextEncoder().encode(JSON.stringify(_payload));
}

test('buildBackupZip: writes a valid archive with all four metadata files', async () => {
	const blob = await buildBackupZip({
		runsOut: [{ id: 'r-1', distance_m: 5000 }],
		routesOut: [{ id: 'rt-1', name: 'Park loop' }],
		profile: { username: 'tester' },
		settingsPrefs: { unit: 'km' },
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: [{ id: 'r-1', track_url: 'uid/r-1.json.gz' }],
		fetchTrackBytes: async () => gzipOf([{ lat: 0.0, lng: 0.0 }])
	});

	// Round-trip via JSZip (the existing restore path uses it; pinning
	// this proves the new writer hasn't drifted from what restore reads).
	const buf = new Uint8Array(await blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);

	const manifestRaw = await zip.file('manifest.json')!.async('string');
	const manifest = JSON.parse(manifestRaw);
	assert.equal(manifest.format, BACKUP_FORMAT);
	assert.equal(manifest.version, BACKUP_VERSION);
	assert.equal(manifest.exported_by_user_id, 'uid');
	assert.equal(manifest.counts.runs, 1);
	assert.equal(manifest.counts.routes, 1);
	assert.equal(manifest.counts.tracks, 1);

	const runs = JSON.parse(await zip.file('runs.json')!.async('string'));
	assert.equal(runs[0].id, 'r-1');

	const routes = JSON.parse(await zip.file('routes.json')!.async('string'));
	assert.equal(routes[0].name, 'Park loop');

	const profile = JSON.parse(await zip.file('profile.json')!.async('string'));
	assert.equal(profile.profile.username, 'tester');
	assert.equal(profile.settings_prefs.unit, 'km');

	const trackEntry = zip.file('tracks/r-1.json.gz');
	assert.ok(trackEntry, 'tracks/r-1.json.gz must be present');
});

test('buildBackupZip: downloads tracks in bounded-concurrency batches', async () => {
	let inFlight = 0;
	let peakInFlight = 0;
	let totalCalls = 0;

	const fetcher = async (path: string): Promise<Uint8Array> => {
		totalCalls++;
		inFlight++;
		if (inFlight > peakInFlight) peakInFlight = inFlight;
		// Yield so concurrent calls observably overlap rather than
		// running to completion synchronously and resetting peak to 1.
		await new Promise((r) => setTimeout(r, 5));
		inFlight--;
		return gzipOf({ path });
	};

	const runsWithTracks = Array.from({ length: 20 }, (_, i) => ({
		id: `r-${i}`,
		track_url: `uid/r-${i}.json.gz`
	}));

	await buildBackupZip({
		runsOut: runsWithTracks,
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks,
		fetchTrackBytes: fetcher,
		concurrency: 4
	});

	assert.equal(totalCalls, 20);
	assert.ok(peakInFlight <= 4, `concurrency: 4 must cap simultaneous downloads, peak=${peakInFlight}`);
	assert.ok(
		peakInFlight >= 2,
		`with 20 tasks + 5ms-each fetcher we should observe parallelism, peak=${peakInFlight}`
	);
});

test('buildBackupZip: a single download failure does not sink the rest', async () => {
	const fetcher = async (path: string): Promise<Uint8Array> => {
		if (path === 'uid/r-bad.json.gz') {
			throw new Error('synthetic download error');
		}
		return gzipOf({ path });
	};

	const runs = [
		{ id: 'r-good-1', track_url: 'uid/r-good-1.json.gz' },
		{ id: 'r-bad', track_url: 'uid/r-bad.json.gz' },
		{ id: 'r-good-2', track_url: 'uid/r-good-2.json.gz' }
	];

	const blob = await buildBackupZip({
		runsOut: runs,
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: runs,
		fetchTrackBytes: fetcher,
		concurrency: 4
	});

	const buf = new Uint8Array(await blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);
	// Healthy runs land in the archive; the bad one is silently absent.
	assert.ok(zip.file('tracks/r-good-1.json.gz'), 'r-good-1 track must be present');
	assert.ok(zip.file('tracks/r-good-2.json.gz'), 'r-good-2 track must be present');
	assert.equal(zip.file('tracks/r-bad.json.gz'), null);

	// Manifest counts reflect only the tracks actually added.
	const manifest = JSON.parse(await zip.file('manifest.json')!.async('string'));
	assert.equal(manifest.counts.tracks, 2);
});

test('buildBackupZip: empty runsWithTracks produces a valid manifest-only archive', async () => {
	let calls = 0;
	const fetcher = async (): Promise<Uint8Array> => {
		calls++;
		return gzipOf([]);
	};

	const blob = await buildBackupZip({
		runsOut: [],
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: [],
		fetchTrackBytes: fetcher
	});

	assert.equal(calls, 0, 'no tracks → no fetcher calls');
	const buf = new Uint8Array(await blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);
	const manifest = JSON.parse(await zip.file('manifest.json')!.async('string'));
	assert.equal(manifest.counts.tracks, 0);
});

test('buildBackupZip: rejects concurrency < 1', async () => {
	await assert.rejects(
		() =>
			buildBackupZip({
				runsOut: [],
				routesOut: [],
				profile: null,
				settingsPrefs: {},
				userId: 'uid',
				exportedFrom: 'test',
				runsWithTracks: [],
				fetchTrackBytes: async () => new Uint8Array(),
				concurrency: 0
			}),
		/concurrency must be >= 1/
	);
});

test('buildBackupZip: emits stage + tracks + done progress events in order', async () => {
	const stages: string[] = [];
	await buildBackupZip({
		runsOut: [{ id: 'r-1' }],
		routesOut: [],
		profile: null,
		settingsPrefs: {},
		userId: 'uid',
		exportedFrom: 'test',
		runsWithTracks: [{ id: 'r-1', track_url: 'uid/r-1.json.gz' }],
		fetchTrackBytes: async () => gzipOf([]),
		onProgress: (p) => stages.push(p.stage)
	});

	assert.ok(stages.includes('tracks'));
	assert.ok(stages.includes('writing'));
	assert.equal(stages[stages.length - 1], 'done');
});

test('buildBackupZip: profile id field is stripped to keep the archive re-homeable', async () => {
	const blob = await buildBackupZip({
		runsOut: [],
		routesOut: [],
		profile: { id: 'old-user-uuid', username: 'tester' },
		settingsPrefs: {},
		userId: 'new-user-uuid',
		exportedFrom: 'test',
		runsWithTracks: [],
		fetchTrackBytes: async () => new Uint8Array()
	});
	const buf = new Uint8Array(await blob.arrayBuffer());
	const zip = await JSZip.loadAsync(buf);
	const profile = JSON.parse(await zip.file('profile.json')!.async('string'));
	assert.equal(profile.profile.username, 'tester');
	assert.equal(profile.profile.id, undefined, 'id must be stripped');
});

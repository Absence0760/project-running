// Source-grep architecture guards for the export-data handler.
//
// The handler itself can't be unit tested in Deno (importing index.ts
// runs Deno.serve and needs a live Supabase). The streaming invariants
// are structural — the archive must never be assembled in memory, a
// failed build must leave no artifact, and no cap may creep back in —
// and every one of them would regress silently under a refactor with a
// green suite. These guards pin them in source.
//
// Mirrors the source-grep pattern in delete-account/wiring.test.ts.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(new URL('./index.ts', import.meta.url));

Deno.test('the archive is streamed, never buffered into a Blob', () => {
	assert(
		SRC.includes('createResumableUpload('),
		'the archive must go out through the chunked tus sink',
	);
	assert(
		SRC.includes('resumableWritable(upload)'),
		'ZipWriter must target the sink, not a BlobWriter',
	);
	assert(
		!SRC.includes('BlobWriter'),
		'a BlobWriter accumulates the whole archive in memory — the exact ' +
			'allocation the 5000-run and 50,000-row caps existed to protect',
	);
	assert(
		!SRC.includes("storage\n\t\t.from('runs')\n\t\t.upload(") && !SRC.includes('.upload('),
		'a single-shot Storage upload needs the whole body resident',
	);
});

Deno.test('no run cap and no per-section row ceiling survive', () => {
	assert(!SRC.includes('MAX_RUNS'), 'the 5000-run cap is gone; it was a memory bound');
	assert(!SRC.includes('EXPORT_ROW_CEILING'), 'the per-section row ceiling is gone');
	assert(!SRC.includes('fetchAllPages'), 'collecting a whole section is what the caps existed for');
});

Deno.test('the surviving bound is the wall clock, and it is threaded through', () => {
	assert(SRC.includes('createExportBudget()'), 'the handler must create a budget');
	// Every fan-out sweep is budgeted, or a deep history burns the whole
	// request on tracks and the request dies with nothing to show.
	const budgeted = (SRC.match(/budgeted\(budget, '/g) ?? []).length;
	assert(budgeted >= 5, `only ${budgeted} budgeted blob sweeps; expected tracks, hr_series, photos, avatars, storage_orphans`);
	for (const label of ['tracks', 'hr_series', 'photos', 'avatars', 'storage_orphans']) {
		assert(SRC.includes(`budgeted(budget, '${label}'`), `${label} sweep is not budgeted`);
	}
	// And the paged section walks.
	assert(SRC.includes("label: 'runs'"), 'the runs walk must be labelled for the manifest');
});

Deno.test('a failed build aborts the upload before answering', () => {
	const abort = SRC.indexOf('await upload.abort()');
	const sign = SRC.indexOf('createSignedUrl');
	assert(abort !== -1, 'the catch must abort the tus session');
	assert(
		abort < sign,
		'the abort must precede the signing path: an archive that stopped ' +
			'half-way must not exist, let alone be handed to the caller',
	);
});

Deno.test('the signed URL is only minted after the build returned', () => {
	const build = SRC.indexOf('built = await write');
	const sign = SRC.indexOf('createSignedUrl');
	assert(build !== -1 && sign !== -1);
	assert(build < sign, 'signing before the upload finalises would sign a nonexistent object');
});

Deno.test('the response `complete` folds in the deadline shortfall', () => {
	assert(
		SRC.includes('built.runs.complete && built.incomplete.length === 0'),
		'a section the wall clock cut off must not be reported as a complete export',
	);
});

Deno.test('the manifest merges the budget shortfall into `incomplete`', () => {
	assert(
		SRC.includes('budget.deadlineSkipped()'),
		'sections skipped for time must reach manifest.json',
	);
	assert(
		SRC.includes('incomplete: shortfall'),
		'buildBackupManifest must be given the merged shortfall list',
	);
});

Deno.test('every personal-data section the export used to carry is still wired', () => {
	// audit/data-export-completeness: the streaming rewrite touched every
	// builder, so the entry set is re-pinned here rather than trusted.
	for (const entry of [
		'runs.json',
		'routes.json',
		'profile.json',
		'run_gear.json',
		'jobs_summary.json',
		'manifest.json',
	]) {
		assert(SRC.includes(`'${entry}'`), `${entry} is no longer written`);
	}
	for (const prefix of ['tracks/', 'hr/', 'photos/', 'avatar.']) {
		assert(SRC.includes(prefix), `the ${prefix} blob sweep is no longer wired`);
	}
	assert(SRC.includes('buildBackupSpecs(userId)'), 'the per-table section set is no longer read');
	assert(SRC.includes('orphanStorageEntries('), 'the Storage orphan sweep is no longer wired');
});

Deno.test('manifest.json is still the last entry written', () => {
	// It carries the counts, so anything added after it would not be
	// counted. Everything the backup builder adds must precede it.
	const manifest = SRC.lastIndexOf("await zip.add(\n\t\t'manifest.json'");
	assert(manifest !== -1, 'manifest.json add not found in the expected shape');
	const after = SRC.slice(manifest);
	const laterAdds = (after.match(/zip\.add\(/g) ?? []).length;
	assertEquals(laterAdds, 1, 'an entry is added after manifest.json and is therefore uncounted');
});

Deno.test('the track and hr path-shape assertions still gate the downloader', () => {
	// RLS guarantees ownership; these keep a corrupt or legacy row from
	// feeding an unconstrained string to the service-role downloader.
	assert(SRC.includes('canonicalTrackUrl(r)'), 'track_url path shape is no longer asserted');
	assert(SRC.includes('canonicalHrUrl(r)'), 'hr_series_url path shape is no longer asserted');
	assert(SRC.includes('isSafeStoragePath(sp)'), 'photo path shape is no longer asserted');
});

Deno.test('the artifact lands in the exports bucket, not runs', () => {
	// `file_size_limit` is per bucket. `runs` caps an object at 25 MB,
	// which on a full-history backup is a tighter ceiling than either cap
	// §703 removed — and storage-api enforces it for service_role too, so
	// the subject gets a failed upload rather than a short archive.
	assert(SRC.includes("const EXPORT_BUCKET = 'exports';"));
	assert(SRC.includes('bucket: EXPORT_BUCKET'), 'the upload must target the exports bucket');
	assert(SRC.includes('.from(EXPORT_BUCKET)'), 'the signed URL must be minted on the same bucket');
	assert(
		!/storage\s*\n?\s*\.from\('runs'\)\s*\n?\s*\.createSignedUrl/.test(SRC),
		'a signed URL on `runs` would point at the old bucket',
	);
});

Deno.test('the exports bucket admits a big archive and stays signed-URL-only', async () => {
	const mig = await Deno.readTextFile(
		new URL('../../migrations/20270602_001_exports_storage_bucket.sql', import.meta.url),
	);
	const limit = Number(/\n\s*(\d{9,}), -- /.exec(mig)?.[1] ?? '0');
	assert(limit > 26214400, `exports limit ${limit} is not above the runs bucket's 25 MB`);
	assert(mig.includes("'exports'"), 'the bucket id must be `exports`');
	// 20260816_001 carved `exports/` out of the owner-folder SELECT on
	// `runs` so an export is reachable through its 10-minute signed URL
	// and nothing else. A policy here would reverse that.
	assert(
		!mig.includes('create policy'),
		'the exports bucket must carry no storage.objects policy — service_role ' +
			'is the only reader/writer and 20260816_001 made exports signed-URL-only',
	);
	// And the 7-day retention sweep has to reach the new bucket, or an
	// archive of the subject's whole history outlives its URL forever.
	assert(
		mig.includes('cleanup_stale_export_blobs') && mig.includes("bucket_id = 'exports'"),
		'the retention sweep must be widened to the new bucket',
	);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	CLOUD_EXPORT_POLL_MAX_MS,
	CLOUD_EXPORT_POLL_MIN_MS,
	type CloudExportResponse,
	buildCloudExportBody,
	buildCloudExportJobStatusUrl,
	buildCloudExportJobsUrl,
	cloudExportJobFromResponse,
	cloudExportPollDelayMs,
	cloudExportShortfall,
	isCloudExportJobActive,
} from './cloud_export_helpers';

function res(over: Partial<CloudExportResponse> = {}): CloudExportResponse {
	return {
		url: 'https://signed.example/x',
		expires_in: 600,
		count: 5000,
		total: 7412,
		complete: false,
		format: 'backup',
		...over,
	};
}

test('buildCloudExportBody — csv shape', () => {
	assert.equal(buildCloudExportBody('csv'), '{"format":"csv"}');
});

test('buildCloudExportBody — gpx shape', () => {
	assert.equal(buildCloudExportBody('gpx'), '{"format":"gpx"}');
});

test('cloudExportShortfall — a complete export discloses nothing', () => {
	assert.equal(
		cloudExportShortfall(res({ count: 12, total: 12, complete: true })),
		null,
	);
});

test('cloudExportShortfall — a truncated export reports both counts', () => {
	assert.deepEqual(cloudExportShortfall(res()), { count: 5000, total: 7412 });
});

test('cloudExportShortfall — a response without `complete` claims nothing', () => {
	// An older deployment of either transport omits the field. Absence is
	// not evidence of truncation, and a shortfall banner on every export
	// would be its own lie.
	assert.equal(
		cloudExportShortfall({
			url: 'https://signed.example/x',
			expires_in: 600,
			count: 12,
			format: 'gpx',
		}),
		null,
	);
});

test('cloudExportShortfall — a missing total falls back to the archive count', () => {
	assert.deepEqual(cloudExportShortfall(res({ count: 40, total: undefined })), {
		count: 40,
		total: 40,
	});
});

test('cloudExportShortfall — total can never render below count', () => {
	assert.deepEqual(cloudExportShortfall(res({ count: 12, total: 3 })), {
		count: 12,
		total: 12,
	});
});

// ─────────────────── the queued rail (decisions.md § 717) ───────────────────

test('buildCloudExportJobsUrl / buildCloudExportJobStatusUrl — trailing slashes normalise', () => {
	assert.equal(
		buildCloudExportJobsUrl('https://live.threkir.com'),
		'https://live.threkir.com/v1/export/jobs',
	);
	assert.equal(
		buildCloudExportJobsUrl('https://live.threkir.com/'),
		'https://live.threkir.com/v1/export/jobs',
	);
	assert.equal(
		buildCloudExportJobsUrl('https://live.threkir.com//'),
		'https://live.threkir.com/v1/export/jobs',
	);
	assert.equal(
		buildCloudExportJobStatusUrl('https://live.threkir.com'),
		'https://live.threkir.com/v1/export/jobs/latest',
	);
	assert.equal(
		buildCloudExportJobStatusUrl('https://live.threkir.com///'),
		'https://live.threkir.com/v1/export/jobs/latest',
	);
});

test('cloudExportJobFromResponse — a ready job carries its URL and counts', () => {
	const job = cloudExportJobFromResponse({
		job_id: 'exp-1',
		status: 'ready',
		format: 'backup',
		url: 'https://signed.example/x',
		expires_in: 600,
		count: 5000,
		total: 7412,
		complete: false,
	});
	assert.equal(job.status, 'ready');
	assert.equal(job.url, 'https://signed.example/x');
	assert.deepEqual(cloudExportShortfall(job), { count: 5000, total: 7412 });
});

test('cloudExportJobFromResponse — a status this build does not know is terminal, not a poll forever', () => {
	// A client that keeps asking about a status it cannot interpret spins
	// until the tab closes; one that guesses `ready` offers a download it
	// has no URL for. Neither is acceptable, so an unknown token fails
	// closed and names itself.
	const job = cloudExportJobFromResponse({ status: 'compacting' });
	assert.equal(job.status, 'failed');
	assert.equal(job.error_code, 'compacting');
	assert.equal(isCloudExportJobActive(job.status), false);
});

test('cloudExportJobFromResponse — a ready job with no URL is a failure, not a dead button', () => {
	const job = cloudExportJobFromResponse({ status: 'ready', job_id: 'exp-1' });
	assert.equal(job.status, 'failed');
	assert.equal(job.error_code, 'no_url');
});

test('cloudExportJobFromResponse — an unreadable body claims nothing', () => {
	assert.equal(cloudExportJobFromResponse(null).status, 'failed');
	assert.equal(cloudExportJobFromResponse('nope').status, 'failed');
	assert.equal(cloudExportJobFromResponse({}).error_code, 'unknown_status');
});

test('cloudExportJobFromResponse — non-numeric counts are dropped rather than rendered', () => {
	const job = cloudExportJobFromResponse({
		status: 'ready',
		url: 'https://signed.example/x',
		count: 'lots',
		total: Number.NaN,
		complete: 'yes',
	});
	assert.equal(job.count, undefined);
	assert.equal(job.total, undefined);
	assert.equal(job.complete, undefined);
	// And with nothing known, no shortfall is claimed.
	assert.equal(cloudExportShortfall(job), null);
});

test('cloudExportShortfall — a job that says complete:false but knows no counts still discloses', () => {
	assert.deepEqual(cloudExportShortfall({ complete: false }), { count: 0, total: 0 });
});

test('isCloudExportJobActive — only queued and running keep the poll alive', () => {
	assert.equal(isCloudExportJobActive('queued'), true);
	assert.equal(isCloudExportJobActive('running'), true);
	for (const s of ['none', 'ready', 'failed', 'expired', 'stalled'] as const) {
		assert.equal(isCloudExportJobActive(s), false, s);
	}
});

test('cloudExportPollDelayMs — backs off from the floor to the cap and stays there', () => {
	assert.equal(cloudExportPollDelayMs(0), CLOUD_EXPORT_POLL_MIN_MS);
	assert.equal(cloudExportPollDelayMs(1), CLOUD_EXPORT_POLL_MIN_MS);
	assert.equal(cloudExportPollDelayMs(2), 4_000);
	assert.equal(cloudExportPollDelayMs(4), 8_000);
	assert.equal(cloudExportPollDelayMs(100), CLOUD_EXPORT_POLL_MAX_MS);
	// A nonsense attempt count must not produce a zero-delay hot loop.
	assert.equal(cloudExportPollDelayMs(-1), CLOUD_EXPORT_POLL_MIN_MS);
	assert.equal(cloudExportPollDelayMs(Number.NaN), CLOUD_EXPORT_POLL_MIN_MS);
});

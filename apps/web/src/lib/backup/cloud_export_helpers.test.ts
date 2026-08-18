import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	type CloudExportResponse,
	buildCloudExportBody,
	buildCloudExportUrl,
	cloudExportShortfall,
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

test('buildCloudExportUrl — clean base', () => {
	assert.equal(
		buildCloudExportUrl('https://live.threkir.com'),
		'https://live.threkir.com/v1/export',
	);
});

test('buildCloudExportUrl — strips a trailing slash', () => {
	assert.equal(
		buildCloudExportUrl('https://live.threkir.com/'),
		'https://live.threkir.com/v1/export',
	);
});

test('buildCloudExportUrl — strips multiple trailing slashes', () => {
	assert.equal(
		buildCloudExportUrl('https://live.threkir.com///'),
		'https://live.threkir.com/v1/export',
	);
});

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

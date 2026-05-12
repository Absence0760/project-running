import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildCloudExportBody,
	buildCloudExportUrl,
} from './cloud_export_helpers';

test('buildCloudExportUrl — clean base', () => {
	assert.equal(
		buildCloudExportUrl('https://live.runonward.com'),
		'https://live.runonward.com/v1/export',
	);
});

test('buildCloudExportUrl — strips a trailing slash', () => {
	assert.equal(
		buildCloudExportUrl('https://live.runonward.com/'),
		'https://live.runonward.com/v1/export',
	);
});

test('buildCloudExportUrl — strips multiple trailing slashes', () => {
	assert.equal(
		buildCloudExportUrl('https://live.runonward.com///'),
		'https://live.runonward.com/v1/export',
	);
});

test('buildCloudExportBody — csv shape', () => {
	assert.equal(buildCloudExportBody('csv'), '{"format":"csv"}');
});

test('buildCloudExportBody — gpx shape', () => {
	assert.equal(buildCloudExportBody('gpx'), '{"format":"gpx"}');
});

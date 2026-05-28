import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { parseStravaMediaPaths } from './strava_media';

test('parseStravaMediaPaths — pipe-separated media paths', () => {
	assert.deepEqual(
		parseStravaMediaPaths('media/123/a.jpg|media/123/b.png'),
		['media/123/a.jpg', 'media/123/b.png'],
	);
});

test('parseStravaMediaPaths — comma-separated (older exports) + trims', () => {
	assert.deepEqual(parseStravaMediaPaths('media/1/a.jpg, media/1/b.jpeg'), [
		'media/1/a.jpg',
		'media/1/b.jpeg',
	]);
});

test('parseStravaMediaPaths — drops non-image paths and empties', () => {
	assert.deepEqual(parseStravaMediaPaths('media/1/a.jpg|media/1/notes.txt|'), [
		'media/1/a.jpg',
	]);
	assert.deepEqual(parseStravaMediaPaths(''), []);
	assert.deepEqual(parseStravaMediaPaths(undefined), []);
});

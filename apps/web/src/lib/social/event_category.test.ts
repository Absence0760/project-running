import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EVENT_CATEGORIES, isAthleticCategory } from './event_category';

test('EVENT_CATEGORIES lists every category once in picker order', () => {
	assert.deepEqual([...EVENT_CATEGORIES], ['run', 'cycle', 'class', 'social']);
});

test('run and cycle are athletic', () => {
	assert.equal(isAthleticCategory('run'), true);
	assert.equal(isAthleticCategory('cycle'), true);
});

test('class and social are not athletic', () => {
	assert.equal(isAthleticCategory('class'), false);
	assert.equal(isAthleticCategory('social'), false);
});

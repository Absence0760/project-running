import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { nextTabIndex } from './tablist';

test('ArrowRight/ArrowDown advance and wrap', () => {
	assert.equal(nextTabIndex('ArrowRight', 0, 3), 1);
	assert.equal(nextTabIndex('ArrowRight', 2, 3), 0); // wrap to start
	assert.equal(nextTabIndex('ArrowDown', 1, 3), 2);
});

test('ArrowLeft/ArrowUp retreat and wrap', () => {
	assert.equal(nextTabIndex('ArrowLeft', 2, 3), 1);
	assert.equal(nextTabIndex('ArrowLeft', 0, 3), 2); // wrap to end
	assert.equal(nextTabIndex('ArrowUp', 1, 3), 0);
});

test('Home/End jump to ends', () => {
	assert.equal(nextTabIndex('Home', 2, 3), 0);
	assert.equal(nextTabIndex('End', 0, 3), 2);
});

test('non-navigation keys leave the index unchanged', () => {
	assert.equal(nextTabIndex('Enter', 1, 3), 1);
	assert.equal(nextTabIndex('a', 1, 3), 1);
	assert.equal(nextTabIndex(' ', 0, 3), 0);
});

test('empty / single tablist is a no-op', () => {
	assert.equal(nextTabIndex('ArrowRight', 0, 0), 0);
	assert.equal(nextTabIndex('ArrowRight', 0, 1), 0); // (0+1)%1 = 0
});

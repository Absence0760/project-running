process.env.TZ = 'America/New_York';

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseISO } from './training';

const SUNDAY_ISO = '2026-06-14';

test('parseISO renders a bare Sunday date as Sunday in a negative-UTC-offset timezone', () => {
	const label = parseISO(SUNDAY_ISO).toLocaleDateString('en-US', { weekday: 'short' });
	assert.equal(label, 'Sun');
});

test('parsing the bare date as UTC midnight would slip to the previous weekday (the bug this guards)', () => {
	const buggy = new Date(SUNDAY_ISO).toLocaleDateString('en-US', { weekday: 'short' });
	assert.equal(buggy, 'Sat');
});

test('parseISO gives the correct local weekday regardless of UTC offset', () => {
	assert.equal(parseISO(SUNDAY_ISO).getDay(), 0);
});

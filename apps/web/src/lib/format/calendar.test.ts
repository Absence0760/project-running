import { test } from 'node:test';
import assert from 'node:assert/strict';
import { monthName, monthNames, weekdayAbbrevs, leadingBlanks } from './calendar';

test('monthNames: localised long month names, 12 of them, 0-based', () => {
	assert.equal(monthNames('en').length, 12);
	assert.equal(monthName(0, 'en'), 'January');
	assert.equal(monthName(11, 'en'), 'December');
	assert.equal(monthName(0, 'de'), 'Januar');
	assert.equal(monthName(2, 'de'), 'März');
	assert.equal(monthName(5, 'de'), 'Juni');
	assert.equal(monthName(5, 'fr'), 'juin');
});

test('monthName: index wraps (month+1 overflow is harmless)', () => {
	assert.equal(monthName(12, 'en'), 'January');
	assert.equal(monthName(-1, 'en'), 'December');
});

test('weekdayAbbrevs: Monday-first order + localisation', () => {
	assert.deepEqual(weekdayAbbrevs('monday', 'en'), [
		'Mon',
		'Tue',
		'Wed',
		'Thu',
		'Fri',
		'Sat',
		'Sun',
	]);
	assert.deepEqual(weekdayAbbrevs('monday', 'de'), ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']);
});

test('weekdayAbbrevs: Sunday-first rotates the week, keeping localisation', () => {
	assert.deepEqual(weekdayAbbrevs('sunday', 'en'), [
		'Sun',
		'Mon',
		'Tue',
		'Wed',
		'Thu',
		'Fri',
		'Sat',
	]);
	assert.deepEqual(weekdayAbbrevs('sunday', 'de'), ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']);
});

test('leadingBlanks: maps Date.getDay() to the grid offset per week start', () => {
	// getDay(): 0=Sun … 6=Sat.
	// Monday-first: Mon→0, Sun→6.
	assert.equal(leadingBlanks(1, 'monday'), 0);
	assert.equal(leadingBlanks(0, 'monday'), 6);
	assert.equal(leadingBlanks(3, 'monday'), 2);
	// Sunday-first: Sun→0, Sat→6.
	assert.equal(leadingBlanks(0, 'sunday'), 0);
	assert.equal(leadingBlanks(6, 'sunday'), 6);
	assert.equal(leadingBlanks(1, 'sunday'), 1);
});

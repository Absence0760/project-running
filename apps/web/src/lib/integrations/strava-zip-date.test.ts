import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseStravaCsvDateToIso } from './strava-zip-date';

test('parses the documented no-zone format as UTC, not viewer-local', () => {
	// "Apr 15, 2026, 1:00:00 PM" is UTC per Strava's docs but carries no zone
	// designator. The instant must be 13:00:00Z regardless of the importer's
	// local timezone.
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 1:00:00 PM'), '2026-04-15T13:00:00.000Z');
});

test('a midnight no-zone run stays on the same UTC calendar day', () => {
	// The regression: a local-zone parse would roll this to the previous or
	// next day for viewers behind/ahead of UTC.
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 12:00:00 AM'), '2026-04-15T00:00:00.000Z');
});

test('12 PM noon stays at hour 12 UTC', () => {
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 12:00:00 PM'), '2026-04-15T12:00:00.000Z');
});

test('24-hour no-zone input is treated as UTC', () => {
	assert.equal(parseStravaCsvDateToIso('Apr 15, 2026, 19:45:30'), '2026-04-15T19:45:30.000Z');
});

test('long month name resolves via first-3-char slice', () => {
	assert.equal(parseStravaCsvDateToIso('April 9, 2026, 7:30:00 AM'), '2026-04-09T07:30:00.000Z');
});

test('month name is case-insensitive', () => {
	assert.equal(
		parseStravaCsvDateToIso('apr 9, 2026, 7:30:00 am'),
		parseStravaCsvDateToIso('APR 9, 2026, 7:30:00 AM'),
	);
});

test('an already-zoned ISO value is left untouched (not re-shifted)', () => {
	// Defers to the native parser, which honours the embedded offset.
	assert.equal(parseStravaCsvDateToIso('2026-04-09T07:30:00Z'), '2026-04-09T07:30:00.000Z');
	assert.equal(parseStravaCsvDateToIso('2026-04-09T07:30:00+02:00'), '2026-04-09T05:30:00.000Z');
});

test('returns null for empty / unparseable input', () => {
	assert.equal(parseStravaCsvDateToIso(''), null);
	assert.equal(parseStravaCsvDateToIso(null), null);
	assert.equal(parseStravaCsvDateToIso(undefined), null);
	assert.equal(parseStravaCsvDateToIso('not a date'), null);
});

test('returns null when the month name is unknown', () => {
	assert.equal(parseStravaCsvDateToIso('Xyz 1, 2026, 1:00:00 AM'), null);
});

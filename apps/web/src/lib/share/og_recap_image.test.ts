import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRecapOgSvg, type RecapOgInput } from './og_recap_image';

function input(over: Partial<RecapOgInput> = {}): RecapOgInput {
	return {
		year: 2026,
		totalDistanceM: 1_234_000,
		runCount: 142,
		longestRunM: 42195,
		bestStreakDays: 21,
		topWeekDistanceM: 95000,
		totalElevationM: 12345,
		displayName: 'Sam Runner',
		...over,
	};
}

test('renders a well-formed 1200x630 svg with the year kicker + hero distance', () => {
	const svg = buildRecapOgSvg(input());
	assert.ok(svg.startsWith('<svg'));
	assert.ok(svg.trimEnd().endsWith('</svg>'));
	assert.ok(svg.includes('viewBox="0 0 1200 630"'));
	assert.ok(svg.includes('MY 2026 IN RUNNING'));
	assert.ok(svg.includes('1234 km'));
});

test('shows the run count + attribution in the subhead', () => {
	const svg = buildRecapOgSvg(input());
	assert.ok(svg.includes('142 runs'));
	assert.ok(svg.includes('Sam Runner'));
});

test('falls back to "across N runs" with no display name', () => {
	const svg = buildRecapOgSvg(input({ displayName: null }));
	assert.ok(svg.includes('across 142 runs'));
});

test('a periodLabel renders a monthly kicker', () => {
	const svg = buildRecapOgSvg(input({ periodLabel: 'March 2026', month: 3 }));
	assert.ok(svg.includes('MY MARCH 2026 IN RUNNING'));
});

test('the three headline cells render labels + values', () => {
	const svg = buildRecapOgSvg(input());
	assert.ok(svg.includes('LONGEST'));
	assert.ok(svg.includes('BEST STREAK'));
	assert.ok(svg.includes('TOP WEEK'));
	assert.ok(svg.includes('21 days'));
});

test('honours the mi unit', () => {
	const svg = buildRecapOgSvg(input(), 'mi');
	assert.ok(svg.includes('767 mi'));
	assert.ok(!svg.includes(' km'));
});

test('xml-escapes a display name with special characters', () => {
	const svg = buildRecapOgSvg(input({ displayName: 'A & B <x>' }));
	assert.ok(svg.includes('A &amp; B &lt;x&gt;'));
	assert.ok(!svg.includes('A & B <x>'));
});

test('zeroed / missing fields stay valid (no NaN, no throw)', () => {
	const svg = buildRecapOgSvg({});
	assert.ok(svg.includes('0 km'));
	assert.ok(svg.includes('across 0 runs'));
	assert.ok(svg.includes('MY YEAR IN RUNNING'));
	assert.ok(!svg.includes('NaN'));
});

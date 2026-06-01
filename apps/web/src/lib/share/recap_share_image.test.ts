import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildRecapShareSvg } from './recap_share_image';
import type { YearInRunningRecap } from '../runs/recap';

function recap(over: Partial<YearInRunningRecap> = {}): YearInRunningRecap {
	return {
		year: 2026,
		runCount: 142,
		totalDistanceM: 1_234_000,
		totalDurationS: 3600 * 110,
		totalElevationM: 12345,
		longestRunM: 42195,
		fastestPaceSecPerKm: 270,
		bestStreakDays: 21,
		currentStreakDays: 4,
		earliestStartLocal: '05:30',
		latestStartLocal: '21:10',
		monthly: Array.from({ length: 12 }, (_, i) => ({
			month: i + 1,
			distanceM: i < 9 ? 100000 : 0,
			runCount: i < 9 ? 12 : 0,
			durationS: i < 9 ? 36000 : 0,
		})),
		topWeek: { weekStart: '2026-03-09', distanceM: 95000, runCount: 6 },
		uniqueRouteCount: 18,
		mostUsedActivity: 'run',
		photoCount: 0,
		personalRecordCount: 0,
		badges: [],
		...over,
	};
}

test('renders a well-formed svg with the year and headline distance', () => {
	const svg = buildRecapShareSvg(recap(), 'km');
	assert.ok(svg.startsWith('<svg'));
	assert.ok(svg.trimEnd().endsWith('</svg>'));
	assert.ok(svg.includes('viewBox="0 0 1080 1080"'));
	assert.ok(svg.includes('MY 2026 IN RUNNING'));
	assert.ok(svg.includes('1234 km'));
	assert.ok(svg.includes('across 142 runs'));
});

test('honours the mi unit on every distance field', () => {
	const svg = buildRecapShareSvg(recap(), 'mi');
	assert.ok(svg.includes('767 mi')); // 1_234_000 m / 1609.344
	assert.ok(svg.includes('26 mi')); // 42195 m longest run
	assert.ok(!svg.includes(' km'));
});

test('singularises a single-run year', () => {
	const svg = buildRecapShareSvg(recap({ runCount: 1 }), 'km');
	assert.ok(svg.includes('across 1 run'));
	assert.ok(!svg.includes('across 1 runs'));
});

test('shows active-month count out of twelve', () => {
	const svg = buildRecapShareSvg(recap(), 'km');
	assert.ok(svg.includes('9 / 12'));
});

test('escapes nothing dangerous but stays valid with zeroed data', () => {
	const svg = buildRecapShareSvg(
		recap({
			runCount: 0,
			totalDistanceM: 0,
			longestRunM: 0,
			topWeek: null,
			totalElevationM: 0,
			bestStreakDays: 0,
		}),
		'km',
	);
	assert.ok(svg.includes('0 km'));
	assert.ok(svg.includes('across 0 runs'));
	assert.ok(svg.includes('0 days'));
});

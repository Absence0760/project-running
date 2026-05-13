import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	daysUntilRace,
	evenSplitPacing,
	negativeSplitPacing,
	raceChecklist,
	fmtSplitTime,
} from './race_day';

// ─────────── daysUntilRace ───────────

test('daysUntilRace: race today → 0', () => {
	const today = new Date(2026, 4, 13, 12);
	assert.equal(daysUntilRace('2026-05-13', today), 0);
});

test('daysUntilRace: race tomorrow → 1', () => {
	const today = new Date(2026, 4, 13, 12);
	assert.equal(daysUntilRace('2026-05-14', today), 1);
});

test('daysUntilRace: race two months out', () => {
	const today = new Date(2026, 4, 13, 12);
	// May 13 to July 13 = 61 days.
	assert.equal(daysUntilRace('2026-07-13', today), 61);
});

test('daysUntilRace: race in the past is negative', () => {
	const today = new Date(2026, 4, 13, 12);
	assert.equal(daysUntilRace('2026-04-13', today), -30);
});

// ─────────── evenSplitPacing ───────────

test('evenSplitPacing: 5k at 25:00 → 5:00/km each', () => {
	const s = evenSplitPacing(5000, 1500);
	assert.equal(s.splitsSec.length, 5);
	for (const sp of s.splitsSec) assert.equal(sp, 300);
	assert.equal(Math.round(s.avgSecPerKm), 300);
});

test('evenSplitPacing: 10.5 km gives 11 splits, last one partial', () => {
	const s = evenSplitPacing(10_500, 3150); // 5:00/km
	assert.equal(s.splitsSec.length, 11);
	// First 10 are full km splits.
	for (let i = 0; i < 10; i++) assert.equal(s.splitsSec[i], 300);
	// Last is 0.5 km at 5:00/km = 150 s.
	assert.equal(s.splitsSec[10], 150);
});

test('evenSplitPacing: marathon at 3:30:00 → 4:58/km', () => {
	const total = 3 * 3600 + 30 * 60; // 12600
	const s = evenSplitPacing(42195, total);
	assert.equal(s.splitsSec.length, 43);
	// avgSecPerKm = 12600 / 42.195 = ~298.65 s/km
	assert.ok(Math.abs(s.avgSecPerKm - 298.65) < 0.5);
});

test('evenSplitPacing: zero / negative input → empty', () => {
	assert.deepEqual(evenSplitPacing(0, 1500).splitsSec, []);
	assert.deepEqual(evenSplitPacing(5000, 0).splitsSec, []);
});

// ─────────── negativeSplitPacing ───────────

test('negativeSplitPacing: first half slower, second half faster', () => {
	const s = negativeSplitPacing(10_000, 3000, 2); // 5:00 avg, 2% delta
	assert.equal(s.splitsSec.length, 10);
	// First half splits are slower than avg, second half faster.
	const avg = 300;
	for (let i = 0; i < 5; i++) {
		assert.ok(s.splitsSec[i] > avg, `split ${i} should be > avg`);
	}
	for (let i = 5; i < 10; i++) {
		assert.ok(s.splitsSec[i] < avg, `split ${i} should be < avg`);
	}
});

test('negativeSplitPacing: sum of splits ≈ total time', () => {
	const s = negativeSplitPacing(10_000, 3000, 2);
	const sum = s.splitsSec.reduce((a, b) => a + b, 0);
	// 5 km @ (300+6) + 5 km @ (300-6) = 1530 + 1470 = 3000.
	assert.ok(Math.abs(sum - 3000) <= 10);
});

test('negativeSplitPacing: 0% delta → even splits', () => {
	const s = negativeSplitPacing(5000, 1500, 0);
	for (const sp of s.splitsSec) assert.equal(sp, 300);
});

// ─────────── raceChecklist ───────────

test('raceChecklist: 5k has no gels in fuel', () => {
	const c = raceChecklist(5000);
	const fuel = c.find((s) => s.title === 'Fueling');
	assert.ok(fuel);
	const fuelText = fuel!.items.map((i) => i.name).join(' ');
	assert.doesNotMatch(fuelText, /gel/i);
});

test('raceChecklist: half marathon prescribes 1-2 gels', () => {
	const c = raceChecklist(21097);
	const fuel = c.find((s) => s.title === 'Fueling');
	const fuelText = fuel!.items.map((i) => i.name).join(' ');
	assert.match(fuelText, /1-2 gels/);
});

test('raceChecklist: marathon prescribes 4-6 gels + carb load', () => {
	const c = raceChecklist(42195);
	const fuel = c.find((s) => s.title === 'Fueling');
	const fuelText = fuel!.items.map((i) => i.name).join(' ');
	assert.match(fuelText, /4-6 gels/);
	assert.match(fuelText, /Carb load/i);
});

test('raceChecklist: always includes Morning of + Gear + Fueling sections', () => {
	const c = raceChecklist(10000);
	const titles = c.map((s) => s.title);
	assert.ok(titles.includes('Morning of'));
	assert.ok(titles.includes('Gear'));
	assert.ok(titles.includes('Fueling'));
});

test('raceChecklist: marathon adds the toilet-plan item', () => {
	const c = raceChecklist(42195);
	const gear = c.find((s) => s.title === 'Gear');
	const gearText = gear!.items.map((i) => i.name).join(' ');
	assert.match(gearText, /Toilet plan/i);
});

// ─────────── fmtSplitTime ───────────

test('fmtSplitTime: under an hour formats as M:SS', () => {
	assert.equal(fmtSplitTime(305), '5:05');
	assert.equal(fmtSplitTime(60), '1:00');
});

test('fmtSplitTime: over an hour formats as H:MM:SS', () => {
	assert.equal(fmtSplitTime(3725), '1:02:05');
	assert.equal(fmtSplitTime(3 * 3600 + 30 * 60), '3:30:00');
});

test('fmtSplitTime: rounds to nearest second', () => {
	assert.equal(fmtSplitTime(305.6), '5:06');
});

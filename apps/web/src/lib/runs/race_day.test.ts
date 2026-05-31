import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	daysUntilRace,
	evenSplitPacing,
	MILE_METRES,
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

// ─────────── evenSplitPacing — unitMetres (mi mode) ───────────

test('evenSplitPacing: 5k at 25:00 with unitMetres=MILE_METRES → 4 splits, ~8:03/mi', () => {
	// 5k ≈ 3.107 miles → ceil(3.107) = 4 splits, last one partial.
	// avgPerMile = 1500 / 3.107 ≈ 483 sec/mi.
	const s = evenSplitPacing(5000, 1500, MILE_METRES);
	assert.equal(s.splitsSec.length, 4);
	// First 3 are full-mile splits (~483 s).
	for (let i = 0; i < 3; i++) {
		assert.ok(
			Math.abs(s.splitsSec[i] - 483) <= 1,
			`split ${i} should be ~483s, got ${s.splitsSec[i]}`,
		);
	}
	// avgSecPerKm field stays in per-km units regardless of split unit,
	// so callers that want a single average pace string can still use
	// the existing formatPace(secPerKm) without branching.
	assert.equal(Math.round(s.avgSecPerKm), 300);
});

test('evenSplitPacing: mile-mode avgSecPerKm stays in per-km units', () => {
	// avgSecPerKm is documented as "always in per-km" so callers can
	// feed it to the existing formatPace helper without branching on
	// the unit. Pin that switching the split unit doesn't accidentally
	// flip the avgSecPerKm scale (which would emit "5 min per km"
	// while the splits are mile splits — silently misleading).
	const total = 3 * 3600 + 30 * 60; // 3:30:00 marathon
	const km = evenSplitPacing(42195, total);
	const mi = evenSplitPacing(42195, total, MILE_METRES);
	assert.ok(
		Math.abs(km.avgSecPerKm - mi.avgSecPerKm) < 0.01,
		`avgSecPerKm should be unit-agnostic; km=${km.avgSecPerKm} mi=${mi.avgSecPerKm}`,
	);
});

test('evenSplitPacing: split count derives from unitMetres', () => {
	// Same distance, two unit modes, different split counts. Pin the
	// shape so a regression that ignored unitMetres (and always used
	// 1000) would visibly fail.
	const km = evenSplitPacing(10_000, 3000);
	const mi = evenSplitPacing(10_000, 3000, MILE_METRES);
	assert.equal(km.splitsSec.length, 10);
	// 10_000 m / 1609.344 = 6.214 → ceil = 7 splits.
	assert.equal(mi.splitsSec.length, 7);
});

// ─────────── negativeSplitPacing — unitMetres (mi mode) ───────────

test('negativeSplitPacing: mile-mode preserves first-slow / second-fast', () => {
	const s = negativeSplitPacing(10_000, 3000, 2, MILE_METRES);
	assert.equal(s.splitsSec.length, 7); // ceil(10000 / 1609.344) = 7
	// Halves are by distance, not split count — mid-mile splits
	// straddle the halfway mark. First 3 fully in the first half,
	// last 3 fully in the second half; the middle split is at the
	// boundary and can land either side. Pin only the unambiguous
	// extremes.
	const avgMi = 3000 / (10_000 / MILE_METRES);
	assert.ok(
		s.splitsSec[0] > avgMi,
		`first split should be slower than mile avg ${avgMi}`,
	);
	assert.ok(
		s.splitsSec[s.splitsSec.length - 1] < avgMi,
		`last split should be faster than mile avg ${avgMi}`,
	);
});

test('negativeSplitPacing: mile-mode 0% delta yields even splits', () => {
	const s = negativeSplitPacing(10_000, 3000, 0, MILE_METRES);
	// All 7 splits should be ~the avg per mile (last is partial).
	const avgMi = 3000 / (10_000 / MILE_METRES); // ~482.8
	for (let i = 0; i < s.splitsSec.length - 1; i++) {
		assert.ok(
			Math.abs(s.splitsSec[i] - avgMi) <= 1,
			`split ${i}: ${s.splitsSec[i]} should be ~${avgMi}`,
		);
	}
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

// ─────────── Round 3 edge cases ───────────

test('evenSplitPacing: exact whole-km distance has no partial-km tail', () => {
	const s = evenSplitPacing(5000, 1500);
	// 5 km at 5:00/km — every split exactly 300s, no remainder.
	assert.equal(s.splitsSec.length, 5);
	for (const sp of s.splitsSec) assert.equal(sp, 300);
});

test('negativeSplitPacing: large delta still preserves total within rounding', () => {
	// 10% delta is aggressive — 4:00/km first half vs 4:00 second.
	// Total must still hit the target inside +/- a few seconds.
	const s = negativeSplitPacing(10_000, 3000, 10);
	const sum = s.splitsSec.reduce((a, b) => a + b, 0);
	assert.ok(Math.abs(sum - 3000) <= 10, `total drifted: ${sum}`);
	// First-km split is slower than the last-km split by ~2× delta.
	assert.ok(s.splitsSec[0] > s.splitsSec[9]);
	assert.ok(s.splitsSec[0] - s.splitsSec[9] >= 50, 'expected meaningful delta');
});

test('daysUntilRace: same UTC instant on different sides of midnight', () => {
	// 23:30 local vs 00:30 next-day local should still register the
	// correct day-delta. The helper compares calendar dates, not wall
	// clocks.
	const today = new Date(2026, 4, 13, 23, 30);
	assert.equal(daysUntilRace('2026-05-14', today), 1);
	assert.equal(daysUntilRace('2026-05-13', today), 0);
});

test('raceChecklist: 10k boundary is on the short side', () => {
	// 10.5 km is the threshold between "short" and "half". 10000 m
	// must NOT prescribe gels (it's short); 11000 m must.
	const c10k = raceChecklist(10000);
	const fuel10k = c10k.find((s) => s.title === 'Fueling')!.items
		.map((i) => i.name).join(' ');
	assert.doesNotMatch(fuel10k, /gel/i);

	const c11k = raceChecklist(11000);
	const fuel11k = c11k.find((s) => s.title === 'Fueling')!.items
		.map((i) => i.name).join(' ');
	assert.match(fuel11k, /1-2 gels/);
});

test('raceChecklist: gear section always has the core 5 items', () => {
	const c = raceChecklist(5000);
	const gear = c.find((s) => s.title === 'Gear')!.items
		.map((i) => i.name).join(' ');
	assert.match(gear, /Race-day shoes/);
	assert.match(gear, /Watch/);
	assert.match(gear, /Race bib/);
	assert.match(gear, /[Aa]nti-chafe/);
	assert.match(gear, /Socks/);
});

test('fmtSplitTime: zero and very-small inputs', () => {
	assert.equal(fmtSplitTime(0), '0:00');
	assert.equal(fmtSplitTime(0.4), '0:00');
	assert.equal(fmtSplitTime(0.5), '0:01');
});

test('evenSplitPacing: marathon distance (42.195 km) has 43 splits, last partial', () => {
	const s = evenSplitPacing(42195, 12000); // ~4:44/km
	assert.equal(s.splitsSec.length, 43);
	// The 43rd (index 42) is the 0.195 km partial.
	const partial = s.splitsSec[42];
	const fullKm = s.splitsSec[0];
	assert.ok(partial < fullKm, `partial ${partial} should be shorter than full ${fullKm}`);
});

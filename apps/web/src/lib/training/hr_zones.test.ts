import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
	MAX_HR_BPM_MAX,
	MAX_HR_BPM_MIN,
	RESTING_HR_BPM_MAX,
	RESTING_HR_BPM_MIN,
	TANAKA_AGE_MAX,
	TANAKA_AGE_MIN,
	defaultZoneCutoffs,
	isUsableMaxHrBpm,
	isUsableRestingHrBpm,
	tanakaMaxHr,
	zoneCutoffsFromMaxHr
} from './hr_zones';

test('tanakaMaxHr applies 208 − 0.7×age, rounded', () => {
	assert.equal(tanakaMaxHr(20), 194); // 208 − 14
	assert.equal(tanakaMaxHr(36), 183); // 182.8 → 183
	assert.equal(tanakaMaxHr(60), 166); // 208 − 42
});

test('zoneCutoffsFromMaxHr is 60/70/80/90/100 % rounded', () => {
	assert.deepEqual(zoneCutoffsFromMaxHr(190), [114, 133, 152, 171, 190]);
	assert.deepEqual(zoneCutoffsFromMaxHr(200), [120, 140, 160, 180, 200]);
});

test('defaultZoneCutoffs prefers an explicit max-HR override', () => {
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: 200, ageYears: 60 }), [
		120, 140, 160, 180, 200,
	]);
});

test('defaultZoneCutoffs derives from age (Tanaka) when no override', () => {
	// age 60 → Tanaka 166 → lower ceiling than the legacy 190.
	assert.deepEqual(defaultZoneCutoffs({ ageYears: 60 }), zoneCutoffsFromMaxHr(166));
	// A masters runner's top zone is well below the old 190 default.
	assert.ok(defaultZoneCutoffs({ ageYears: 60 })[4] < 190);
});

test('defaultZoneCutoffs falls back to the legacy 190 ladder', () => {
	assert.deepEqual(defaultZoneCutoffs({}), [114, 133, 152, 171, 190]);
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: null, ageYears: null }), [
		114, 133, 152, 171, 190,
	]);
});

test('defaultZoneCutoffs ignores out-of-range inputs', () => {
	// implausible max HR (sensor-bag garbage) → fall through to age
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: 40, ageYears: 30 }), zoneCutoffsFromMaxHr(tanakaMaxHr(30)));
	// implausible age → fall through to legacy default
	assert.deepEqual(defaultZoneCutoffs({ ageYears: 200 }), [114, 133, 152, 171, 190]);
});

// The bounds are the part the THIRD rail shares — the Wear OS
// `resolveZoneCutoffs` applied `max_hr_bpm` flat until decisions § 1245, so a
// mistyped 300 gave the same run different zones on the watch and the phone.
// `max_hr_bpm` is a jsonb prefs key with no CHECK, so nothing but these reads
// stands between a typo and a zone ladder.
test('the usable ranges are the bounds defaultZoneCutoffs applies', () => {
	assert.equal(defaultZoneCutoffs({ maxHrBpm: MAX_HR_BPM_MIN })[4], MAX_HR_BPM_MIN);
	assert.equal(defaultZoneCutoffs({ maxHrBpm: MAX_HR_BPM_MAX })[4], MAX_HR_BPM_MAX);
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: MAX_HR_BPM_MIN - 1 }), [114, 133, 152, 171, 190]);
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: MAX_HR_BPM_MAX + 1 }), [114, 133, 152, 171, 190]);

	assert.deepEqual(
		defaultZoneCutoffs({ ageYears: TANAKA_AGE_MIN }),
		zoneCutoffsFromMaxHr(tanakaMaxHr(TANAKA_AGE_MIN))
	);
	assert.deepEqual(
		defaultZoneCutoffs({ ageYears: TANAKA_AGE_MAX }),
		zoneCutoffsFromMaxHr(tanakaMaxHr(TANAKA_AGE_MAX))
	);
	assert.deepEqual(defaultZoneCutoffs({ ageYears: TANAKA_AGE_MIN - 1 }), [114, 133, 152, 171, 190]);
	assert.deepEqual(defaultZoneCutoffs({ ageYears: TANAKA_AGE_MAX + 1 }), [114, 133, 152, 171, 190]);
});

// 0 survives every `!= null` check and is exactly what an emptied number input
// posts. Applied flat it yields an all-zero ladder that puts every real sample
// above Z5 — the shape the watch rail had.
test('a zero max HR is ignored, not applied as a ceiling', () => {
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: 0 }), [114, 133, 152, 171, 190]);
	assert.deepEqual(defaultZoneCutoffs({ maxHrBpm: -1 }), [114, 133, 152, 171, 190]);
});

// The write side's gate and the read side's fallthrough are now the SAME
// call, so they cannot disagree by construction — which is why this pins the
// COMPOSITION rather than sweeping values, a sweep here being a tautology.
// What can still regress is a write path quietly going back to storing a raw
// parseInt: before decisions § 1407 both did, so a typed 300 was saved, then
// silently ignored by all three readers, leaving the runner on age-estimated
// zones with nothing on screen explaining why.
test('both web max_hr_bpm write paths gate on the shared predicate', () => {
	const pages = [
		'../../routes/settings/account/+page.svelte',
		'../../routes/settings/preferences/+page.svelte'
	];
	for (const rel of pages) {
		const src = readFileSync(new URL(rel, import.meta.url), 'utf8');
		assert.match(src, /isUsableMaxHrBpm/, `${rel} no longer gates max_hr_bpm`);
		assert.doesNotMatch(
			src,
			/max_hr_bpm\s*[:=][^;\n]*parseInt/,
			`${rel} writes max_hr_bpm from a raw parseInt again`
		);
		// The advisory min/max attributes disagreed with the real bound
		// (100/230 against 80/240) for as long as they were literals.
		assert.doesNotMatch(src, /bind:value=\{maxHr\}[^>]*min="/, `${rel} hardcodes a max-HR bound`);
	}
});

// A number input yields '' when emptied and NaN from Number.parseInt on any
// non-numeric text; both write paths route those through this predicate, so
// neither may read as usable. 0 is what an emptied field posted before § 1245.
test('isUsableMaxHrBpm rejects the absent and unparseable inputs', () => {
	assert.equal(isUsableMaxHrBpm(null), false);
	assert.equal(isUsableMaxHrBpm(undefined), false);
	assert.equal(isUsableMaxHrBpm(Number.NaN), false);
	assert.equal(isUsableMaxHrBpm(Number.POSITIVE_INFINITY), false);
	assert.equal(isUsableMaxHrBpm(0), false);
	assert.equal(isUsableMaxHrBpm(MAX_HR_BPM_MIN), true);
	assert.equal(isUsableMaxHrBpm(MAX_HR_BPM_MAX), true);
});

// resting_hr_bpm carried the identical write-side gap max_hr_bpm had: a jsonb
// key with no CHECK, an advisory min/max on both inputs that constraint
// validation never reaches, and `parseInt(x, 10) || null` behind them — so a
// typed 300 or 3 was stored and the TRIMP calibration quietly changed what it
// did about it. Same three assertions as the max-HR pair above, one field over.
test('both web resting_hr_bpm write paths gate on the shared predicate', () => {
	const pages = [
		'../../routes/settings/account/+page.svelte',
		'../../routes/settings/preferences/+page.svelte'
	];
	for (const rel of pages) {
		const src = readFileSync(new URL(rel, import.meta.url), 'utf8');
		assert.match(src, /isUsableRestingHrBpm/, `${rel} no longer gates resting_hr_bpm`);
		assert.doesNotMatch(
			src,
			/resting_hr_bpm\s*[:=][^;\n]*parseInt/,
			`${rel} writes resting_hr_bpm from a raw parseInt again`
		);
		assert.doesNotMatch(
			src,
			/bind:value=\{restingHr\}[^>]*min="/,
			`${rel} hardcodes a resting-HR bound`
		);
	}
});

test('isUsableRestingHrBpm rejects the absent and unparseable inputs', () => {
	assert.equal(isUsableRestingHrBpm(null), false);
	assert.equal(isUsableRestingHrBpm(undefined), false);
	assert.equal(isUsableRestingHrBpm(Number.NaN), false);
	assert.equal(isUsableRestingHrBpm(Number.POSITIVE_INFINITY), false);
	assert.equal(isUsableRestingHrBpm(0), false);
	assert.equal(isUsableRestingHrBpm(RESTING_HR_BPM_MIN), true);
	assert.equal(isUsableRestingHrBpm(RESTING_HR_BPM_MAX), true);
	assert.equal(isUsableRestingHrBpm(RESTING_HR_BPM_MIN - 1), false);
	assert.equal(isUsableRestingHrBpm(RESTING_HR_BPM_MAX + 1), false);
});

// The range is the WIDER of the two the tree already shipped, so it cannot
// refuse a figure the mobile picker was writing before it was named. Pinning
// the containment rather than the literals keeps the reason legible if either
// number ever moves.
test('the named resting-HR range contains the advisory web pair', () => {
	assert.ok(RESTING_HR_BPM_MIN <= 30 && RESTING_HR_BPM_MAX >= 120);
});

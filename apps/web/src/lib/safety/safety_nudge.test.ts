import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	isNightWindow,
	isSunDown,
	isDarkOutside,
	nudgeThrottled,
	shouldNudgeSoloSafety,
	shouldSurfaceSoloSafetyNudge,
	SAFETY_NUDGE_DUSK_MINUTES,
	SAFETY_NUDGE_DAWN_MINUTES,
	SAFETY_NUDGE_THROTTLE_MS,
} from './safety_nudge';

const NOW = 1_700_000_000_000;

// A December day (mid-winter, northern hemisphere) and a June day.
const DEC_21 = 355;
const JUN_21 = 172;

function nudgeAt(minutes: number, over: Partial<Parameters<typeof shouldNudgeSoloSafety>[0]> = {}) {
	return shouldNudgeSoloSafety({
		nowLocalMinutes: minutes,
		latitude: null,
		dayOfYear: null,
		autoLiveShareOn: false,
		isBroadcast: false,
		nudgeDismissed: false,
		...over,
	});
}

test('midday is not night', () => {
	assert.equal(isNightWindow(12 * 60), false);
});

test('dusk boundary is inclusive, one minute before is not night', () => {
	assert.equal(isNightWindow(SAFETY_NUDGE_DUSK_MINUTES), true, 'exactly 20:00 is night');
	assert.equal(isNightWindow(SAFETY_NUDGE_DUSK_MINUTES - 1), false, '19:59 is still daylight');
});

test('dawn boundary is exclusive, one minute before is still night', () => {
	assert.equal(isNightWindow(SAFETY_NUDGE_DAWN_MINUTES - 1), true, '05:59 is night');
	assert.equal(isNightWindow(SAFETY_NUDGE_DAWN_MINUTES), false, 'exactly 06:00 is daylight');
});

test('the window wraps midnight', () => {
	assert.equal(isNightWindow(0), true, 'midnight is night');
	assert.equal(isNightWindow(23 * 60), true, '23:00 is night');
	assert.equal(isNightWindow(2 * 60), true, '02:00 is night');
});

test('out-of-range minutes normalise into the day', () => {
	assert.equal(isNightWindow(24 * 60), true, '1440 wraps to 00:00, night');
	assert.equal(isNightWindow(24 * 60 + 12 * 60), false, '36:00 wraps to noon');
	assert.equal(isNightWindow(-1), true, '-1 wraps to 23:59, night');
});

test('never-acted-on nudge is not throttled', () => {
	assert.equal(nudgeThrottled(null, NOW), false);
});

test('throttle window is exclusive at its far edge', () => {
	assert.equal(nudgeThrottled(NOW - (SAFETY_NUDGE_THROTTLE_MS - 1), NOW), true, 'just inside stays suppressed');
	assert.equal(nudgeThrottled(NOW - SAFETY_NUDGE_THROTTLE_MS, NOW), false, 'exactly at the window can resurface');
});

test('a future-dated stamp (clock skew) throttles rather than spams', () => {
	assert.equal(nudgeThrottled(NOW + 5_000, NOW), true);
});

test('nudges a solo after-dark run with no live share and no throttle', () => {
	assert.equal(nudgeAt(22 * 60), true);
});

test('does not nudge during daylight', () => {
	assert.equal(nudgeAt(12 * 60), false);
});

test('auto-live-share on suppresses the nudge even after dark', () => {
	assert.equal(nudgeAt(22 * 60, { autoLiveShareOn: true }), false);
});

test('an already-broadcasting run is not nudged', () => {
	assert.equal(nudgeAt(22 * 60, { isBroadcast: true }), false);
});

test('a throttled (recently acted-on) nudge stays suppressed', () => {
	assert.equal(nudgeAt(22 * 60, { nudgeDismissed: true }), false);
});

test('every suppressor is independent — daylight alone suppresses', () => {
	assert.equal(nudgeAt(9 * 60, { autoLiveShareOn: false, isBroadcast: false }), false);
});

function surfaceAt(
	minutes: number,
	over: Partial<Parameters<typeof shouldSurfaceSoloSafetyNudge>[0]> = {},
) {
	return shouldSurfaceSoloSafetyNudge({
		nowLocalMinutes: minutes,
		latitude: null,
		dayOfYear: null,
		autoLiveShareOn: false,
		isBroadcast: false,
		lastActedAtMs: null,
		nowMs: NOW,
		...over,
	});
}

test('surfaces a solo after-dark run never acted on', () => {
	assert.equal(surfaceAt(22 * 60), true);
});

test('a nudge acted on within the window stays suppressed', () => {
	assert.equal(
		surfaceAt(22 * 60, { lastActedAtMs: NOW - (SAFETY_NUDGE_THROTTLE_MS - 1) }),
		false,
	);
});

test('a nudge acted on longer ago than the window resurfaces', () => {
	assert.equal(
		surfaceAt(22 * 60, { lastActedAtMs: NOW - SAFETY_NUDGE_THROTTLE_MS }),
		true,
	);
});

test('a future-dated acted-on stamp (clock skew) stays suppressed', () => {
	assert.equal(surfaceAt(22 * 60, { lastActedAtMs: NOW + 5_000 }), false);
});

test('daylight / broadcast / auto-share each suppress the surface decision', () => {
	assert.equal(surfaceAt(12 * 60), false);
	assert.equal(surfaceAt(22 * 60, { isBroadcast: true }), false);
	assert.equal(surfaceAt(22 * 60, { autoLiveShareOn: true }), false);
});

test('the surface decision inherits the seasonal darkness', () => {
	assert.equal(surfaceAt(7 * 60, { latitude: 60, dayOfYear: DEC_21 }), true);
	assert.equal(surfaceAt(6 * 60 + 30, { latitude: 60, dayOfYear: JUN_21 }), false);
});

test('winter pre-dawn at high latitude is dark (sun still down)', () => {
	assert.equal(isSunDown(7 * 60, 60, DEC_21), true, '07:00 at 60°N in December is before sunrise');
});

test('winter midday at high latitude is light', () => {
	assert.equal(isSunDown(12 * 60, 60, DEC_21), false, 'the sun is up at solar noon even in deep winter');
});

test('summer 06:30 at high latitude is already light', () => {
	assert.equal(isSunDown(6 * 60 + 30, 60, JUN_21), false, 'high-latitude summer sun rises well before 06:30');
});

test('polar night is always dark', () => {
	assert.equal(isSunDown(12 * 60, 80, DEC_21), true, 'the sun never rises at 80°N in December');
});

test('polar day (midnight sun) is never dark', () => {
	assert.equal(isSunDown(0, 80, JUN_21), false, 'the sun never sets at 80°N in June');
});

test('isDarkOutside falls back to the fixed window when latitude is unknown', () => {
	assert.equal(isDarkOutside(22 * 60, null, null), true, 'the fixed dusk window still fires');
	assert.equal(isDarkOutside(12 * 60, null, null), false, 'midday with no fix is not dark');
});

test('isDarkOutside adds seasonal darkness the fixed window misses', () => {
	assert.equal(isDarkOutside(7 * 60, 60, DEC_21), true, 'a dark winter pre-dawn run is now dark');
	assert.equal(isDarkOutside(6 * 60 + 30, 60, JUN_21), false, 'a bright summer dawn run is not');
});

test('nudges a dark winter pre-7am run at high latitude (the issue #265 case)', () => {
	assert.equal(nudgeAt(7 * 60, { latitude: 60, dayOfYear: DEC_21 }), true);
});

test('does not nudge a bright summer 06:30 run at high latitude', () => {
	assert.equal(nudgeAt(6 * 60 + 30, { latitude: 60, dayOfYear: JUN_21 }), false);
});

test('a covered runner is not nudged even in winter darkness', () => {
	assert.equal(nudgeAt(7 * 60, { latitude: 60, dayOfYear: DEC_21, autoLiveShareOn: true }), false);
});

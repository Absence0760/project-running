import { test } from 'node:test';
import assert from 'node:assert/strict';
import { effective, type LoadedSettings } from './settings_overlay';

const empty: LoadedSettings = { universal: {}, device: {} };

test('effective — returns the fallback when neither bag has the key', () => {
	assert.equal(effective<number>(empty, 'weekly_mileage_goal_m', 50000), 50000);
	assert.equal(effective<number>(empty, 'missing'), undefined);
});

test('effective — universal value wins over the fallback', () => {
	const s: LoadedSettings = { universal: { preferred_unit: 'mi' }, device: {} };
	assert.equal(effective<string>(s, 'preferred_unit', 'km'), 'mi');
});

test('effective — device value overrides the universal value', () => {
	const s: LoadedSettings = {
		universal: { preferred_unit: 'mi' },
		device: { preferred_unit: 'km' },
	};
	assert.equal(effective<string>(s, 'preferred_unit'), 'km');
});

test('effective — device null falls through to universal (not treated as concrete)', () => {
	const s: LoadedSettings = {
		universal: { weekly_mileage_goal_m: 50000 },
		device: { weekly_mileage_goal_m: null },
	};
	assert.equal(effective<number>(s, 'weekly_mileage_goal_m'), 50000);
});

test('effective — device undefined falls through to universal', () => {
	const s: LoadedSettings = {
		universal: { weekly_mileage_goal_m: 50000 },
		device: { weekly_mileage_goal_m: undefined },
	};
	assert.equal(effective<number>(s, 'weekly_mileage_goal_m'), 50000);
});

test('effective — universal null with no device value returns the fallback', () => {
	const s: LoadedSettings = { universal: { weekly_mileage_goal_m: null }, device: {} };
	assert.equal(effective<number>(s, 'weekly_mileage_goal_m', 30000), 30000);
});

test('effective — falsy-but-concrete values win (0, "", false are NOT treated as missing)', () => {
	const zero: LoadedSettings = { universal: {}, device: { voice_feedback_interval_km: 0 } };
	assert.equal(effective<number>(zero, 'voice_feedback_interval_km', 1.0), 0);

	const empty: LoadedSettings = { universal: {}, device: { activity_type: '' } };
	assert.equal(effective<string>(empty, 'activity_type', 'run'), '');

	const off: LoadedSettings = { universal: {}, device: { audio_cues: false } };
	assert.equal(effective<boolean>(off, 'audio_cues', true), false);
});

test('effective — bag value of object / array round-trips', () => {
	const zones = [{ lat: 0, lng: 0, radius: 100 }];
	const s: LoadedSettings = { universal: { privacy_zones: zones }, device: {} };
	assert.deepEqual(effective<typeof zones>(s, 'privacy_zones'), zones);
});

test('effective — generic type parameter is a viewer hint, no runtime cast', () => {
	// This is a type-only smoke test: caller asserts <number>, value is
	// stored as a number, returned as a number. The function does not
	// actually validate the type at runtime — it only handles
	// null/undefined fall-through. Passing a string under <number>
	// returns the string; the caller is responsible for not lying.
	const s: LoadedSettings = { universal: { preferred_unit: 'mi' }, device: {} };
	const out = effective<number>(s, 'preferred_unit');
	assert.equal(out, 'mi' as unknown as number);
});

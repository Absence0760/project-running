import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	VOICE_CUE_IDS,
	isVoiceCueEnabled,
	readVoiceCueMap,
	setVoiceCueEnabled,
} from './voice_cues';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('an absent id is on — a sparse map never silences a cue', () => {
	assert.equal(isVoiceCueEnabled({}, 'splits'), true);
	assert.equal(isVoiceCueEnabled({ off_route: false }, 'splits'), true);
	assert.equal(isVoiceCueEnabled({}, 'a_cue_type_that_does_not_exist_yet'), true);
});

test('an explicit false suppresses, an explicit true speaks', () => {
	assert.equal(isVoiceCueEnabled({ splits: false }, 'splits'), false);
	assert.equal(isVoiceCueEnabled({ splits: true }, 'splits'), true);
});

test('setVoiceCueEnabled preserves ids this build does not know about', () => {
	const stored = { some_future_cue: false, splits: false };
	const next = setVoiceCueEnabled(stored, 'splits', true);
	assert.equal(next.splits, true);
	assert.equal(next.some_future_cue, false);
});

test('setVoiceCueEnabled does not mutate the input map', () => {
	const stored = { splits: true };
	const next = setVoiceCueEnabled(stored, 'splits', false);
	assert.equal(stored.splits, true);
	assert.equal(next.splits, false);
});

test('readVoiceCueMap keeps booleans and drops everything else', () => {
	assert.deepEqual(
		readVoiceCueMap({ splits: false, off_route: 'no', pace_alerts: 0, workout_steps: true }),
		{ splits: false, workout_steps: true },
	);
});

test('readVoiceCueMap fails open on a non-object bag value', () => {
	assert.deepEqual(readVoiceCueMap(null), {});
	assert.deepEqual(readVoiceCueMap(undefined), {});
	assert.deepEqual(readVoiceCueMap('splits'), {});
	assert.deepEqual(readVoiceCueMap(['splits']), {});
	assert.deepEqual(readVoiceCueMap(7), {});
});

test('the cue ids match the Dart VoiceCue wire contract exactly', () => {
	// The phone is what actually speaks these. If the two id lists drift, a
	// web toggle writes a key the recorder never reads and silently does
	// nothing — the exact failure this surface exists to avoid.
	const dart = readFileSync(
		resolve(__dirname, '../../../../mobile_android/lib/preferences.dart'),
		'utf-8',
	);
	const body = dart.match(/class VoiceCue \{([\s\S]*?)\n\}/);
	assert.ok(body, 'VoiceCue class not found in preferences.dart');
	const ids = [...body[1].matchAll(/static const \w+ = '([a-z_]+)';/g)].map((mt) => mt[1]);
	assert.deepEqual(ids, [...VOICE_CUE_IDS]);

	const all = body[1].match(/static const all = \[([\s\S]*?)\];/);
	assert.ok(all, 'VoiceCue.all not found in preferences.dart');
	assert.equal(
		all[1].split(',').filter((s) => s.trim().length > 0).length,
		VOICE_CUE_IDS.length,
		'VoiceCue.all does not list every declared cue id',
	);
});

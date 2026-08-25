import { test } from 'node:test';
import assert from 'node:assert/strict';
import { healthUseDob, healthUseDobState } from './health_consent';

const CONSENTED = { date_of_birth: '1978-04-09', health_data_consent_at: '2026-08-01T09:00:00Z' };
const NO_CONSENT = { date_of_birth: '1978-04-09', health_data_consent_at: null };

test('a date on record under consent is usable', () => {
	assert.equal(healthUseDobState(CONSENTED), 'usable');
	assert.equal(healthUseDob(CONSENTED), '1978-04-09');
});

test('a date on record without the Art 9 stamp is withheld from health use', () => {
	// The column is still populated — the under-18 search floor depends on it
	// (§ 718) — but a masters calibration or an age grade is an Art 9 use.
	assert.equal(healthUseDobState(NO_CONSENT), 'consent_withheld');
	assert.equal(healthUseDob(NO_CONSENT), null);
});

test('consent_withheld is a distinct state so a surface can say why', () => {
	// Not folded into `absent`: "you never told us" and "you told us and asked
	// us not to use it" are different sentences to show the runner.
	assert.notEqual(healthUseDobState(NO_CONSENT), healthUseDobState({ date_of_birth: null }));
});

test('no date on record grades absent, consented or not', () => {
	assert.equal(healthUseDobState({ date_of_birth: null }), 'absent');
	assert.equal(
		healthUseDobState({ date_of_birth: null, health_data_consent_at: '2026-08-01T09:00:00Z' }),
		'absent',
	);
	assert.equal(healthUseDob({ date_of_birth: null }), null);
});

test('a missing row grades absent and yields no date', () => {
	assert.equal(healthUseDobState(null), 'absent');
	assert.equal(healthUseDobState(undefined), 'absent');
	assert.equal(healthUseDob(null), null);
});

test('a full timestamp normalises to the leading YYYY-MM-DD', () => {
	// `ageOnDate` reads only the leading date; handing it a timestamp would
	// still work, but both platforms return the same 10 characters so a
	// divergence in the column's rendering can never become a divergence here.
	assert.equal(
		healthUseDob({ date_of_birth: '1978-04-09T00:00:00.000Z', health_data_consent_at: 'x' }),
		'1978-04-09',
	);
});

test('an empty consent stamp is not consent', () => {
	assert.equal(healthUseDobState({ ...NO_CONSENT, health_data_consent_at: '' }), 'consent_withheld');
	assert.equal(healthUseDob({ ...NO_CONSENT, health_data_consent_at: '' }), null);
});

test('a value too short to be a date grades absent', () => {
	assert.equal(healthUseDobState({ date_of_birth: '1978', health_data_consent_at: 'x' }), 'absent');
	assert.equal(healthUseDob({ date_of_birth: '1978', health_data_consent_at: 'x' }), null);
});

test('a row that is not an object grades absent', () => {
	for (const row of ['1978-04-09', 42, true]) {
		assert.equal(healthUseDobState(row), 'absent');
		assert.equal(healthUseDob(row), null);
	}
});

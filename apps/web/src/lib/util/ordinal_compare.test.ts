import { test } from 'node:test';
import assert from 'node:assert/strict';
import { compareOrdinal } from './ordinal_compare';

test('compareOrdinal: orders ISO timestamps chronologically', () => {
	assert.equal(compareOrdinal('2026-01-05T18:00:00Z', '2026-01-05T18:00:01Z'), -1);
	assert.equal(compareOrdinal('2026-01-05T18:00:01Z', '2026-01-05T18:00:00Z'), 1);
	assert.equal(compareOrdinal('2026-01-05', '2026-01-05'), 0);
});

// The pair the whole module exists for. Postgres trims a zero fractional
// part, so two rows stamped in the same second differ at the character after
// the seconds — `+` against `.` — and the CLDR root orders those two the
// opposite way round from their code points. Asserting the disagreement
// itself, rather than only our answer, is what makes this test fail if
// someone reverts `compareOrdinal` to a collation.
const ON_THE_SECOND = '2026-01-05T18:00:00+00:00';
const WITH_FRACTION = '2026-01-05T18:00:00.482000+00:00';

test('compareOrdinal: disagrees with localeCompare on the Postgres timestamptz shape', () => {
	assert.ok(
		new Date(ON_THE_SECOND) < new Date(WITH_FRACTION),
		'fixture precondition: the on-the-second row is genuinely earlier',
	);
	assert.equal(compareOrdinal(ON_THE_SECOND, WITH_FRACTION), -1);
	assert.ok(
		Math.sign(ON_THE_SECOND.localeCompare(WITH_FRACTION)) === 1,
		'fixture precondition: this host\'s collation calls the earlier row later',
	);
});

test('compareOrdinal: a newest-first sort puts the later row first', () => {
	const desc = [ON_THE_SECOND, WITH_FRACTION].sort((a, b) => compareOrdinal(b, a));
	assert.deepEqual(desc, [WITH_FRACTION, ON_THE_SECOND]);

	const byCollation = [ON_THE_SECOND, WITH_FRACTION].sort((a, b) => b.localeCompare(a));
	assert.deepEqual(
		byCollation,
		[ON_THE_SECOND, WITH_FRACTION],
		'the defect being fixed: the collation puts the older row on top',
	);
});

test('compareOrdinal: locale tags resolve independently of host ICU data', () => {
	assert.equal(compareOrdinal('pt-BR', 'pt-PT'), -1);
	assert.equal(compareOrdinal('en', 'en-GB'), -1);
});

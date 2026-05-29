import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseChipTimingCsv, parseDurationToSeconds } from './event_results_csv';

const D = 10000; // event distance fallback (10k)

test('parseDurationToSeconds handles HH:MM:SS, MM:SS, bare seconds', () => {
	assert.equal(parseDurationToSeconds('1:00:00'), 3600);
	assert.equal(parseDurationToSeconds('40:00'), 2400);
	assert.equal(parseDurationToSeconds('2400'), 2400);
	assert.equal(parseDurationToSeconds('40:30'), 2430);
	assert.equal(parseDurationToSeconds('  00:45  '), 45);
});

test('parseDurationToSeconds rejects garbage', () => {
	assert.equal(parseDurationToSeconds('abc'), null);
	assert.equal(parseDurationToSeconds(''), null);
	assert.equal(parseDurationToSeconds(undefined), null);
	assert.equal(parseDurationToSeconds('1:2:3:4'), null);
	assert.equal(parseDurationToSeconds('-5'), null);
});

test('parses a clean chip-timing CSV', () => {
	const csv = 'Bib,Name,Time\n101,Alice Anon,00:24:00\n102,Bob Bibonly,00:27:00\n';
	const { rows, errors } = parseChipTimingCsv(csv, D);
	assert.deepEqual(errors, []);
	assert.equal(rows.length, 2);
	assert.deepEqual(rows[0], {
		bib: '101',
		finisherName: 'Alice Anon',
		durationS: 1440,
		distanceM: D,
		finisherStatus: 'finished'
	});
	assert.equal(rows[1].bib, '102');
	assert.equal(rows[1].durationS, 1620);
});

test('header aliases + quoted names with commas', () => {
	const csv = 'Race Number,Finisher,Net Time\n7,"Smith, John",1:05:30\n';
	const { rows, errors } = parseChipTimingCsv(csv, D);
	assert.deepEqual(errors, []);
	assert.equal(rows[0].bib, '7');
	assert.equal(rows[0].finisherName, 'Smith, John');
	assert.equal(rows[0].durationS, 3930);
});

test('DNF/DNS rows carry a zero duration and skip time parsing', () => {
	const csv = 'bib,name,time,status\n5,Did Not Finish,,dnf\n6,Did Not Start,,DNS\n';
	const { rows, errors } = parseChipTimingCsv(csv, D);
	assert.deepEqual(errors, []);
	assert.equal(rows[0].finisherStatus, 'dnf');
	assert.equal(rows[0].durationS, 0);
	assert.equal(rows[1].finisherStatus, 'dns');
});

test('distance column in km is converted to metres; bare distance is metres', () => {
	const km = parseChipTimingCsv('bib,name,time,distance km\n1,A,20:00,5\n', D);
	assert.equal(km.rows[0].distanceM, 5000);
	const m = parseChipTimingCsv('bib,name,time,distance m\n1,A,20:00,5000\n', D);
	assert.equal(m.rows[0].distanceM, 5000);
});

test('missing required columns report errors and no rows', () => {
	const { rows, errors } = parseChipTimingCsv('name,time\nAlice,20:00\n', D);
	assert.equal(rows.length, 0);
	assert.ok(errors.some((e) => e.includes('bib')));
});

test('per-row problems are reported with line numbers; good rows still parse', () => {
	const csv = 'bib,name,time\n101,Alice,24:00\n,Orphan,25:00\n102,,26:00\n103,Carol,notatime\n104,Dave,27:00\n';
	const { rows, errors } = parseChipTimingCsv(csv, D);
	assert.deepEqual(
		rows.map((r) => r.bib),
		['101', '104']
	);
	assert.ok(errors.some((e) => e.includes('Row 3') && e.includes('missing bib')));
	assert.ok(errors.some((e) => e.includes('Row 4') && e.includes('missing name')));
	assert.ok(errors.some((e) => e.includes('Row 5') && e.includes('unparseable')));
});

test('duplicate bib within the file is rejected after the first occurrence', () => {
	const csv = 'bib,name,time\n101,Alice,24:00\n101,Alice Dup,25:00\n';
	const { rows, errors } = parseChipTimingCsv(csv, D);
	assert.equal(rows.length, 1);
	assert.ok(errors.some((e) => e.includes('duplicate bib 101')));
});

test('empty file reports an error', () => {
	const { rows, errors } = parseChipTimingCsv('\n\n', D);
	assert.equal(rows.length, 0);
	assert.ok(errors.length > 0);
});

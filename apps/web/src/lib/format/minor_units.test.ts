import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { currencyFractionDigits, fromMinorUnits, toMinorUnits } from './minor_units.js';

test('currencyFractionDigits: two-decimal currencies', () => {
	assert.equal(currencyFractionDigits('USD'), 2);
	assert.equal(currencyFractionDigits('EUR'), 2);
	assert.equal(currencyFractionDigits('GBP'), 2);
});

test('currencyFractionDigits: Stripe zero-decimal currencies carry no minor unit', () => {
	for (const code of ['JPY', 'KRW', 'VND', 'CLP', 'ISK', 'XOF', 'UGX', 'PYG']) {
		assert.equal(currencyFractionDigits(code), 0, `${code} must be zero-decimal`);
	}
});

test('currencyFractionDigits: Stripe three-decimal currencies', () => {
	for (const code of ['BHD', 'JOD', 'KWD', 'OMR', 'TND']) {
		assert.equal(currencyFractionDigits(code), 3, `${code} must be three-decimal`);
	}
});

test('currencyFractionDigits: case- and whitespace-insensitive (rows store lowercase)', () => {
	assert.equal(currencyFractionDigits('jpy'), 0);
	assert.equal(currencyFractionDigits(' usd '), 2);
});

test('currencyFractionDigits: an unusable code falls back to two decimals, never throws', () => {
	assert.equal(currencyFractionDigits('ZZ'), 2);
	assert.equal(currencyFractionDigits(''), 2);
});

test('fromMinorUnits: a two-decimal amount divides by 100', () => {
	assert.equal(fromMinorUnits(1999, 'USD'), 19.99);
	assert.equal(fromMinorUnits(500_000, 'usd'), 5000);
});

test('fromMinorUnits: a zero-decimal amount is already the base unit', () => {
	// A ¥1,000 donation arrives from Stripe as 1000. Dividing by 100 would
	// render it as ¥10 — a hundredfold understatement on a public feed.
	assert.equal(fromMinorUnits(1000, 'JPY'), 1000);
	assert.equal(fromMinorUnits(50_000, 'KRW'), 50_000);
	assert.equal(fromMinorUnits(250_000, 'VND'), 250_000);
});

test('fromMinorUnits: a three-decimal amount divides by 1000', () => {
	assert.equal(fromMinorUnits(1500, 'KWD'), 1.5);
	assert.equal(fromMinorUnits(25_000, 'BHD'), 25);
});

test('toMinorUnits: a two-decimal amount multiplies by 100', () => {
	assert.equal(toMinorUnits(19.99, 'USD'), 1999);
	assert.equal(toMinorUnits(5000, 'usd'), 500_000);
});

test('toMinorUnits: a zero-decimal amount is stored as entered', () => {
	assert.equal(toMinorUnits(1000, 'JPY'), 1000);
	assert.equal(toMinorUnits(50_000, 'KRW'), 50_000);
});

test('toMinorUnits: a three-decimal amount stays a multiple of 10, as Stripe requires', () => {
	assert.equal(toMinorUnits(1.5, 'KWD'), 1500);
	assert.equal(toMinorUnits(1.234, 'KWD'), 1230);
	assert.equal(toMinorUnits(1.239, 'KWD'), 1240);
});

test('round trip: every currency class survives minor → major → minor', () => {
	for (const [minor, code] of [
		[1999, 'USD'],
		[1000, 'JPY'],
		[1500, 'KWD']
	] as const) {
		assert.equal(toMinorUnits(fromMinorUnits(minor, code), code), minor);
	}
});

function sourceFiles(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const path = join(dir, entry);
		if (statSync(path).isDirectory()) {
			out.push(...sourceFiles(path));
		} else if (/\.(ts|svelte)$/.test(entry) && !/\.test\.ts$/.test(entry)) {
			out.push(path);
		}
	}
	return out;
}

test('source guard: no money surface hard-codes a 100 conversion', () => {
	// Reason: 100 is not the minor-unit scale of every currency. A ¥1,000
	// donation is stored as 1000, so `/ 100` renders it as ¥10 on a public
	// feed and `* 100` charges a host a hundredfold. Every conversion goes
	// through fromMinorUnits / toMinorUnits, which read the scale off the
	// currency.
	const MONEY = '(?:_cents|[a-z]Cents|\\bcents\\b)';
	const scaledDown = new RegExp(`${MONEY}\\s*/\\s*100\\b`);
	const scaledUp = new RegExp(`${MONEY}\\s*[:=][^;]*\\*\\s*100\\b`);
	const offenders: string[] = [];
	for (const file of sourceFiles(resolve('src'))) {
		readFileSync(file, 'utf-8')
			.split('\n')
			.forEach((line, i) => {
				if (scaledDown.test(line) || scaledUp.test(line)) {
					offenders.push(`${file}:${i + 1}: ${line.trim()}`);
				}
			});
	}
	assert.deepEqual(offenders, [], `use fromMinorUnits / toMinorUnits instead:\n${offenders.join('\n')}`);
});

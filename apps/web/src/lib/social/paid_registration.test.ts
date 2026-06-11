import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	applicationFeeCents,
	salesCloseAt,
	registrationOpen,
	resolveRefundEligibility,
} from './paid_registration';

test('applicationFeeCents: 0 bps yields no fee', () => {
	assert.equal(applicationFeeCents(2200, 0), 0);
});

test('applicationFeeCents: typical take rate floors', () => {
	// 2200 * 1000bps (10%) = 220.0 -> 220
	assert.equal(applicationFeeCents(2200, 1000), 220);
	// 2199 * 1000bps = 219.9 -> floor 219 (never round up = never skim more)
	assert.equal(applicationFeeCents(2199, 1000), 219);
	// 333 * 500bps (5%) = 16.65 -> 16
	assert.equal(applicationFeeCents(333, 500), 16);
});

test('applicationFeeCents: never exceeds the charge, never negative', () => {
	// 100% fee clamps to the amount (would otherwise zero the payout AND
	// trip a Stripe error).
	assert.equal(applicationFeeCents(2200, 10000), 2200);
	// >100% still clamps to the amount.
	assert.equal(applicationFeeCents(2200, 20000), 2200);
	// guards
	assert.equal(applicationFeeCents(-100, 1000), 0);
	assert.equal(applicationFeeCents(2200, -50), 0);
	assert.equal(applicationFeeCents(NaN, 1000), 0);
});

test('salesCloseAt: offset subtracts minutes from start; 0 == start', () => {
	const start = '2026-07-01T18:00:00.000Z';
	assert.equal(salesCloseAt(start, 0), start);
	assert.equal(salesCloseAt(start, 60), '2026-07-01T17:00:00.000Z');
	assert.equal(salesCloseAt('not-a-date', 60), null);
});

const START = '2026-07-01T18:00:00.000Z';

test('registrationOpen: open before close, with capacity headroom', () => {
	const now = new Date('2026-07-01T12:00:00.000Z');
	assert.equal(registrationOpen(now, START, 0, 10, 3, false), 'open');
});

test('registrationOpen: sales window boundary minute', () => {
	// offset 30m -> closes 17:30. One ms before is open; exactly at close
	// is sales_closed.
	const justBefore = new Date('2026-07-01T17:29:59.999Z');
	const atClose = new Date('2026-07-01T17:30:00.000Z');
	assert.equal(registrationOpen(justBefore, START, 30, 10, 0, false), 'open');
	assert.equal(registrationOpen(atClose, START, 30, 10, 0, false), 'sales_closed');
});

test('registrationOpen: sold-out when going >= capacity', () => {
	const now = new Date('2026-07-01T12:00:00.000Z');
	assert.equal(registrationOpen(now, START, 0, 10, 10, false), 'sold_out');
	assert.equal(registrationOpen(now, START, 0, 10, 11, false), 'sold_out');
	// null / 0 capacity = unlimited
	assert.equal(registrationOpen(now, START, 0, null, 999, false), 'open');
	assert.equal(registrationOpen(now, START, 0, 0, 999, false), 'open');
});

test('registrationOpen: already-registered outranks sold-out AND sales-closed', () => {
	const afterClose = new Date('2026-07-02T00:00:00.000Z');
	// Sold out AND past close, but the viewer holds a paid slot.
	assert.equal(
		registrationOpen(afterClose, START, 0, 10, 10, true),
		'already_registered',
	);
});

test('resolveRefundEligibility: no_refund is never eligible', () => {
	const now = new Date('2026-06-01T00:00:00.000Z');
	assert.deepEqual(resolveRefundEligibility('no_refund', now, START), {
		eligible: false,
		fullRefund: false,
	});
});

test('resolveRefundEligibility: full_until_start', () => {
	const before = new Date('2026-07-01T17:59:00.000Z');
	const atStart = new Date('2026-07-01T18:00:00.000Z');
	const after = new Date('2026-07-01T19:00:00.000Z');
	assert.deepEqual(resolveRefundEligibility('full_until_start', before, START), {
		eligible: true,
		fullRefund: true,
	});
	assert.equal(resolveRefundEligibility('full_until_start', atStart, START).eligible, false);
	assert.equal(resolveRefundEligibility('full_until_start', after, START).eligible, false);
});

test('resolveRefundEligibility: full_until_24h cutoff', () => {
	// cutoff = start - 24h = 2026-06-30T18:00.
	const wayBefore = new Date('2026-06-29T00:00:00.000Z');
	const within24h = new Date('2026-06-30T20:00:00.000Z');
	const afterStart = new Date('2026-07-01T19:00:00.000Z');
	assert.equal(resolveRefundEligibility('full_until_24h', wayBefore, START).eligible, true);
	assert.equal(resolveRefundEligibility('full_until_24h', within24h, START).eligible, false);
	assert.equal(resolveRefundEligibility('full_until_24h', afterStart, START).eligible, false);
});

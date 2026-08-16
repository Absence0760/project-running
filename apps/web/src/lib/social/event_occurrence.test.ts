import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	isOccurrenceCancelled,
	nextLiveInstance,
	upcomingCancelledOccurrences
} from './event_occurrence';
import type { Event } from '../types';

function ev(partial: Partial<Event>): Event {
	return partial as unknown as Event;
}

// A weekly Wednesday 08:00 series. Instances: Apr 1, 8, 15, 22, 29.
const weekly = ev({
	starts_at: '2026-04-01T08:00:00Z',
	recurrence_freq: 'weekly',
	timezone: 'UTC'
});

const beforeSeries = new Date('2026-03-30T00:00:00Z');

test('isOccurrenceCancelled — matches across the two ISO renderings of one instant', () => {
	// PostgREST serialises timestamptz as '+00:00'; a client Date renders
	// '.000Z'. String equality is false for both spellings of one instant.
	assert.equal(isOccurrenceCancelled(['2026-04-08T08:00:00+00:00'], '2026-04-08T08:00:00.000Z'), true);
	assert.equal(isOccurrenceCancelled(['2026-04-08T08:00:00.000Z'], '2026-04-08T08:00:00+00:00'), true);
});

test('isOccurrenceCancelled — a different instant, an empty list, and a null are all not cancelled', () => {
	assert.equal(isOccurrenceCancelled(['2026-04-08T08:00:00Z'], '2026-04-15T08:00:00Z'), false);
	assert.equal(isOccurrenceCancelled([], '2026-04-08T08:00:00Z'), false);
	assert.equal(isOccurrenceCancelled(['2026-04-08T08:00:00Z'], null), false);
	assert.equal(isOccurrenceCancelled(['2026-04-08T08:00:00Z'], undefined), false);
});

test('isOccurrenceCancelled — an unparseable cancelled instant never matches', () => {
	assert.equal(isOccurrenceCancelled(['not-a-date'], '2026-04-08T08:00:00Z'), false);
});

test('nextLiveInstance — nothing cancelled gives the next occurrence', () => {
	const next = nextLiveInstance(weekly, [], beforeSeries);
	assert.equal(next?.toISOString(), '2026-04-01T08:00:00.000Z');
});

test('nextLiveInstance — skips the cancelled next occurrence', () => {
	const next = nextLiveInstance(weekly, ['2026-04-01T08:00:00+00:00'], beforeSeries);
	assert.equal(next?.toISOString(), '2026-04-08T08:00:00.000Z');
});

test('nextLiveInstance — skips a run of consecutive cancellations', () => {
	const next = nextLiveInstance(
		weekly,
		['2026-04-01T08:00:00Z', '2026-04-08T08:00:00Z', '2026-04-15T08:00:00Z'],
		beforeSeries
	);
	assert.equal(next?.toISOString(), '2026-04-22T08:00:00.000Z');
});

test('nextLiveInstance — a cancellation further out does not disturb the next occurrence', () => {
	const next = nextLiveInstance(weekly, ['2026-04-22T08:00:00Z'], beforeSeries);
	assert.equal(next?.toISOString(), '2026-04-01T08:00:00.000Z');
});

test('nextLiveInstance — already-past cancellations do not eat the search budget', () => {
	// Three cancellations, all behind `after`. The budget is derived from the
	// cancelled COUNT, so the live Apr 22 occurrence must still be found.
	const next = nextLiveInstance(
		weekly,
		['2026-04-01T08:00:00Z', '2026-04-08T08:00:00Z', '2026-04-15T08:00:00Z'],
		new Date('2026-04-20T00:00:00Z')
	);
	assert.equal(next?.toISOString(), '2026-04-22T08:00:00.000Z');
});

test('nextLiveInstance — every remaining occurrence cancelled returns null', () => {
	const bounded = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_count: 2,
		timezone: 'UTC'
	});
	const next = nextLiveInstance(
		bounded,
		['2026-04-01T08:00:00Z', '2026-04-08T08:00:00Z'],
		beforeSeries
	);
	assert.equal(next, null);
});

test('nextLiveInstance — an exhausted series returns null whether or not anything was cancelled', () => {
	const bounded = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_count: 1,
		timezone: 'UTC'
	});
	const after = new Date('2026-05-01T00:00:00Z');
	assert.equal(nextLiveInstance(bounded, [], after), null);
	assert.equal(nextLiveInstance(bounded, ['2026-04-01T08:00:00Z'], after), null);
});

test('nextLiveInstance — a one-off event cancelled has no live instance', () => {
	const oneOff = ev({ starts_at: '2026-04-01T08:00:00Z' });
	assert.equal(
		nextLiveInstance(oneOff, ['2026-04-01T08:00:00Z'], beforeSeries),
		null
	);
	assert.equal(
		nextLiveInstance(oneOff, [], beforeSeries)?.toISOString(),
		'2026-04-01T08:00:00.000Z'
	);
});

test('upcomingCancelledOccurrences — keeps only future ones, oldest first', () => {
	const out = upcomingCancelledOccurrences(
		['2026-04-22T08:00:00Z', '2026-04-01T08:00:00Z', '2026-04-15T08:00:00Z'],
		new Date('2026-04-10T00:00:00Z')
	);
	assert.deepEqual(out, ['2026-04-15T08:00:00Z', '2026-04-22T08:00:00Z']);
});

test('upcomingCancelledOccurrences — an unparseable instant is dropped, not sorted to an edge', () => {
	const out = upcomingCancelledOccurrences(
		['not-a-date', '2026-04-15T08:00:00Z'],
		new Date('2026-04-10T00:00:00Z')
	);
	assert.deepEqual(out, ['2026-04-15T08:00:00Z']);
});

test('upcomingCancelledOccurrences — an occurrence starting exactly now still counts as ahead', () => {
	const now = new Date('2026-04-15T08:00:00Z');
	assert.deepEqual(upcomingCancelledOccurrences(['2026-04-15T08:00:00Z'], now), [
		'2026-04-15T08:00:00Z'
	]);
});

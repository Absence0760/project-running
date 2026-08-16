import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	motionFor,
	MOTION_MAX_GAP_MS,
	MOTION_MIN_WINDOW_MS,
	MOTION_STOPPED_DISTANCE_M,
	type MotionSample,
} from './live_motion';

const T0 = 1_700_000_000_000;

/// `count` pings at `stepMs` apart, each advancing the odometer by `stepM`.
function ramp(count: number, stepMs: number, stepM: number, startM = 0): MotionSample[] {
	return Array.from({ length: count }, (_, i) => ({
		distanceM: startM + i * stepM,
		atMs: T0 + i * stepMs,
	}));
}

test('a stale fix is unknown, never stopped', () => {
	// Ten minutes of pings from the exact same spot — the strongest
	// possible "stopped" evidence — but the fix is stale, so the runner
	// may have walked out of signal minutes ago.
	const m = motionFor({ samples: ramp(120, 5_000, 0), stale: true });
	assert.equal(m.state, 'unknown');
	assert.equal(m.stoppedForMs, null);
	assert.equal(m.windowMs, null);
});

test('fewer than two samples is unknown', () => {
	assert.equal(motionFor({ samples: [], stale: false }).state, 'unknown');
	assert.equal(
		motionFor({ samples: [{ distanceM: 100, atMs: T0 }], stale: false }).state,
		'unknown',
	);
});

test('a window shorter than the minimum is unknown, however still the runner', () => {
	// 20 s of standing at a road crossing must not read as stopped.
	const m = motionFor({ samples: ramp(5, 5_000, 0), stale: false });
	assert.equal(m.state, 'unknown');
	assert.equal(m.windowMs, null);
});

test('a window exactly at the minimum with no ground covered is stopped', () => {
	// Contiguous 5 s pings spanning exactly the minimum. Two pings three
	// minutes apart would NOT do — see the gap cases below.
	const samples = ramp(MOTION_MIN_WINDOW_MS / 5_000 + 1, 5_000, 0, 5_000);
	const m = motionFor({ samples, stale: false });
	assert.equal(m.state, 'stopped');
	assert.equal(m.stoppedForMs, MOTION_MIN_WINDOW_MS);
	assert.equal(m.windowMs, MOTION_MIN_WINDOW_MS);
	assert.equal(m.windowDistanceM, 0);
});

test('a runner covering ground is moving', () => {
	// 5 min of pings at 5 s, 8 m each -> ~1.6 m/s.
	const m = motionFor({ samples: ramp(60, 5_000, 8), stale: false });
	assert.equal(m.state, 'moving');
	assert.equal(m.stoppedForMs, null);
	assert.equal(m.windowMs, 59 * 5_000);
	assert.equal(m.windowDistanceM, 59 * 8);
});

test('GPS jitter inside the stopped radius still reads as stopped', () => {
	// A stationary phone wanders; the odometer creeps but never clears the
	// floor across the whole window.
	const samples: MotionSample[] = Array.from({ length: 60 }, (_, i) => ({
		distanceM: 5_000 + (i % 2 === 0 ? 0 : MOTION_STOPPED_DISTANCE_M - 5),
		atMs: T0 + i * 5_000,
	}));
	const m = motionFor({ samples, stale: false });
	assert.equal(m.state, 'stopped');
});

test('creeping just past the stopped radius is moving', () => {
	// Same cadence, but the odometer clears the floor within the window.
	const samples: MotionSample[] = Array.from({ length: 60 }, (_, i) => ({
		distanceM: 5_000 + i * (MOTION_STOPPED_DISTANCE_M + 1),
		atMs: T0 + i * 5_000,
	}));
	const m = motionFor({ samples, stale: false });
	assert.equal(m.state, 'moving');
});

test('a stop shorter than the minimum inside a longer moving window is moving', () => {
	// 8 min of running, then 2 min standing still. The stop has not yet
	// earned a claim.
	const moving = ramp(96, 5_000, 8);
	const last = moving[moving.length - 1];
	const paused: MotionSample[] = Array.from({ length: 24 }, (_, i) => ({
		distanceM: last.distanceM,
		atMs: last.atMs + (i + 1) * 5_000,
	}));
	const m = motionFor({ samples: [...moving, ...paused], stale: false });
	assert.equal(m.state, 'moving');
	assert.equal(m.stoppedForMs, null);
});

test('a stop past the minimum at the end of a moving window is reported without at-least', () => {
	// 5 min of running, then 5 min standing still: the stop is bounded
	// inside the buffer, so the duration is a figure, not a floor.
	const moving = ramp(60, 5_000, 8);
	const last = moving[moving.length - 1];
	const paused: MotionSample[] = Array.from({ length: 60 }, (_, i) => ({
		distanceM: last.distanceM,
		atMs: last.atMs + (i + 1) * 5_000,
	}));
	const m = motionFor({ samples: [...moving, ...paused], stale: false });
	assert.equal(m.state, 'stopped');
	assert.equal(m.atLeast, false);
	// The span reaches back past the stop into the approach: the last three
	// moving samples (8/16/24 m out) are still inside the 25 m radius. The
	// claim is "has not left this spot", so counting the final metres of
	// the approach is the definition working, not drift — it is bounded by
	// the time it takes to cover MOTION_STOPPED_DISTANCE_M.
	assert.equal(m.stoppedForMs, 63 * 5_000);
});

test('a stop filling the whole buffer is reported as a floor', () => {
	const m = motionFor({ samples: ramp(120, 5_000, 0, 5_000), stale: false });
	assert.equal(m.state, 'stopped');
	assert.equal(m.atLeast, true);
	assert.equal(m.stoppedForMs, 119 * 5_000);
});

test('out-of-order samples are sorted, not trusted as given', () => {
	const inOrder = ramp(60, 5_000, 8);
	const shuffled = [...inOrder].reverse();
	assert.deepEqual(
		motionFor({ samples: shuffled, stale: false }),
		motionFor({ samples: inOrder, stale: false }),
	);
});

test('non-finite samples are dropped rather than poisoning the window', () => {
	const samples: MotionSample[] = [
		{ distanceM: Number.NaN, atMs: T0 - 10_000 },
		...ramp(60, 5_000, 8),
		{ distanceM: 9_999, atMs: Number.NaN },
	];
	const m = motionFor({ samples, stale: false });
	assert.equal(m.state, 'moving');
	assert.equal(m.windowMs, 59 * 5_000);
});

test('an outage inside the buffer is not counted as stillness', () => {
	// The dangerous shape: an hour of silence between two pings from the
	// same place. The runner was NOT observed standing there — they could
	// have run out and back — so the whole outage must be discarded, not
	// reported as "at least 60 min in the same spot".
	const before = ramp(12, 5_000, 0, 5_000);
	const last = before[before.length - 1];
	const after = [{ distanceM: 5_000, atMs: last.atMs + 60 * 60 * 1000 }];
	const m = motionFor({ samples: [...before, ...after], stale: false });
	assert.equal(m.state, 'unknown');
	assert.equal(m.stoppedForMs, null);
});

test('a claim resumes once enough contiguous pings land after an outage', () => {
	const before = ramp(12, 5_000, 0, 5_000);
	const last = before[before.length - 1];
	// Four minutes of fresh, contiguous, stationary pings after the gap.
	const after: MotionSample[] = Array.from({ length: 49 }, (_, i) => ({
		distanceM: 5_000,
		atMs: last.atMs + 60 * 60 * 1000 + i * 5_000,
	}));
	const m = motionFor({ samples: [...before, ...after], stale: false });
	assert.equal(m.state, 'stopped');
	// Measured from the far side of the gap only, never through it.
	assert.equal(m.stoppedForMs, 48 * 5_000);
	assert.equal(m.atLeast, true);
});

test('a gap at the accepted limit is vouched for, one millisecond past it is not', () => {
	const spanning = (gapMs: number): MotionSample[] => {
		const base = ramp(MOTION_MIN_WINDOW_MS / 5_000 + 1, 5_000, 0, 5_000);
		const last = base[base.length - 1];
		return [...base, { distanceM: 5_000, atMs: last.atMs + gapMs }];
	};
	assert.equal(motionFor({ samples: spanning(MOTION_MAX_GAP_MS), stale: false }).state, 'stopped');
	// Past the limit the vouched window is the single trailing ping.
	assert.equal(
		motionFor({ samples: spanning(MOTION_MAX_GAP_MS + 1), stale: false }).state,
		'unknown',
	);
});

test('only the gap nearest the newest ping bounds the window', () => {
	// Two outages. The vouched window starts after the LATER one, so the
	// earlier stretch cannot leak back into the claim.
	const samples: MotionSample[] = [
		{ distanceM: 1_000, atMs: T0 },
		{ distanceM: 1_000, atMs: T0 + 30 * 60 * 1000 },
		...Array.from({ length: 49 }, (_, i) => ({
			distanceM: 1_000,
			atMs: T0 + 60 * 60 * 1000 + i * 5_000,
		})),
	];
	const m = motionFor({ samples, stale: false });
	assert.equal(m.state, 'stopped');
	assert.equal(m.stoppedForMs, 48 * 5_000);
});

test('a rewound odometer cannot manufacture a stopped verdict', () => {
	// A re-armed recorder resets distance to 0 mid-stream; the naive delta
	// is a large negative number, which must not read as "covered no
	// ground". Contiguous cadence throughout, so the gap rule is not what
	// is under test here.
	const samples: MotionSample[] = [
		...ramp(18, 5_000, 10, 12_000),
		...ramp(19, 5_000, 10, 0).map((s) => ({ ...s, atMs: s.atMs + 18 * 5_000 })),
	];
	const m = motionFor({ samples, stale: false });
	assert.equal(m.state, 'moving');
	assert.ok((m.windowDistanceM ?? 0) > 0);
});

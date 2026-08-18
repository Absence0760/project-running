import 'package:flutter_test/flutter_test.dart';

import '../lib/live_motion.dart';

const int t0 = 1700000000000;

/// [count] pings at [stepMs] apart, each advancing the odometer by [stepM].
List<MotionSample> ramp(int count, int stepMs, double stepM,
    [double startM = 0]) {
  return [
    for (var i = 0; i < count; i++)
      MotionSample(distanceM: startM + i * stepM, atMs: t0 + i * stepMs),
  ];
}

void main() {
  test('a stale fix is unknown, never stopped', () {
    // Ten minutes of pings from the exact same spot — the strongest
    // possible "stopped" evidence — but the fix is stale, so the runner
    // may have walked out of signal minutes ago.
    final m = motionFor(samples: ramp(120, 5000, 0), stale: true);
    expect(m.state, MotionState.unknown);
    expect(m.stoppedForMs, isNull);
    expect(m.windowMs, isNull);
  });

  test('fewer than two samples is unknown', () {
    expect(motionFor(samples: const [], stale: false).state,
        MotionState.unknown);
    expect(
      motionFor(
        samples: const [MotionSample(distanceM: 100, atMs: t0)],
        stale: false,
      ).state,
      MotionState.unknown,
    );
  });

  test('a window shorter than the minimum is unknown, however still the runner',
      () {
    // 20 s of standing at a road crossing must not read as stopped.
    final m = motionFor(samples: ramp(5, 5000, 0), stale: false);
    expect(m.state, MotionState.unknown);
    expect(m.windowMs, isNull);
  });

  test('a window exactly at the minimum with no ground covered is stopped', () {
    // Contiguous 5 s pings spanning exactly the minimum. Two pings three
    // minutes apart would NOT do — see the gap cases below.
    final samples = ramp(motionMinWindowMs ~/ 5000 + 1, 5000, 0, 5000);
    final m = motionFor(samples: samples, stale: false);
    expect(m.state, MotionState.stopped);
    expect(m.stoppedForMs, motionMinWindowMs);
    expect(m.windowMs, motionMinWindowMs);
    expect(m.windowDistanceM, 0);
  });

  test('a runner covering ground is moving', () {
    // 5 min of pings at 5 s, 8 m each -> ~1.6 m/s.
    final m = motionFor(samples: ramp(60, 5000, 8), stale: false);
    expect(m.state, MotionState.moving);
    expect(m.stoppedForMs, isNull);
    expect(m.windowMs, 59 * 5000);
    expect(m.windowDistanceM, 59 * 8);
  });

  test('GPS jitter inside the stopped radius still reads as stopped', () {
    // A stationary phone wanders; the odometer creeps but never clears the
    // floor across the whole window.
    final samples = [
      for (var i = 0; i < 60; i++)
        MotionSample(
          distanceM: 5000 + (i % 2 == 0 ? 0 : motionStoppedDistanceM - 5),
          atMs: t0 + i * 5000,
        ),
    ];
    expect(motionFor(samples: samples, stale: false).state,
        MotionState.stopped);
  });

  test('creeping just past the stopped radius is moving', () {
    // Same cadence, but the odometer clears the floor within the window.
    final samples = [
      for (var i = 0; i < 60; i++)
        MotionSample(
          distanceM: 5000 + i * (motionStoppedDistanceM + 1),
          atMs: t0 + i * 5000,
        ),
    ];
    expect(motionFor(samples: samples, stale: false).state, MotionState.moving);
  });

  test('a stop shorter than the minimum inside a longer moving window is moving',
      () {
    // 8 min of running, then 2 min standing still. The stop has not yet
    // earned a claim.
    final moving = ramp(96, 5000, 8);
    final last = moving.last;
    final paused = [
      for (var i = 0; i < 24; i++)
        MotionSample(distanceM: last.distanceM, atMs: last.atMs + (i + 1) * 5000),
    ];
    final m = motionFor(samples: [...moving, ...paused], stale: false);
    expect(m.state, MotionState.moving);
    expect(m.stoppedForMs, isNull);
  });

  test('a stop past the minimum at the end of a moving window is reported without at-least',
      () {
    // 5 min of running, then 5 min standing still: the stop is bounded
    // inside the buffer, so the duration is a figure, not a floor.
    final moving = ramp(60, 5000, 8);
    final last = moving.last;
    final paused = [
      for (var i = 0; i < 60; i++)
        MotionSample(distanceM: last.distanceM, atMs: last.atMs + (i + 1) * 5000),
    ];
    final m = motionFor(samples: [...moving, ...paused], stale: false);
    expect(m.state, MotionState.stopped);
    expect(m.atLeast, isFalse);
    // The span reaches back past the stop into the approach: the last three
    // moving samples (8/16/24 m out) are still inside the 25 m radius. The
    // claim is "has not left this spot", so counting the final metres of
    // the approach is the definition working, not drift — it is bounded by
    // the time it takes to cover motionStoppedDistanceM.
    expect(m.stoppedForMs, 63 * 5000);
  });

  test('a stop filling the whole buffer is reported as a floor', () {
    final m = motionFor(samples: ramp(120, 5000, 0, 5000), stale: false);
    expect(m.state, MotionState.stopped);
    expect(m.atLeast, isTrue);
    expect(m.stoppedForMs, 119 * 5000);
  });

  test('out-of-order samples are sorted, not trusted as given', () {
    final inOrder = ramp(60, 5000, 8);
    final shuffled = inOrder.reversed.toList();
    final a = motionFor(samples: shuffled, stale: false);
    final b = motionFor(samples: inOrder, stale: false);
    expect(a.state, b.state);
    expect(a.stoppedForMs, b.stoppedForMs);
    expect(a.atLeast, b.atLeast);
    expect(a.windowMs, b.windowMs);
    expect(a.windowDistanceM, b.windowDistanceM);
  });

  test('a non-finite odometer is dropped rather than poisoning the window', () {
    final samples = <MotionSample>[
      MotionSample(distanceM: double.nan, atMs: t0 - 10000),
      ...ramp(60, 5000, 8),
      MotionSample(distanceM: double.infinity, atMs: t0 + 60 * 5000),
    ];
    final m = motionFor(samples: samples, stale: false);
    expect(m.state, MotionState.moving);
    expect(m.windowMs, 59 * 5000);
  });

  test('an outage inside the buffer is not counted as stillness', () {
    // The dangerous shape: an hour of silence between two pings from the
    // same place. The runner was NOT observed standing there — they could
    // have run out and back — so the whole outage must be discarded, not
    // reported as "at least 60 min in the same spot".
    final before = ramp(12, 5000, 0, 5000);
    final last = before.last;
    final m = motionFor(
      samples: [
        ...before,
        MotionSample(distanceM: 5000, atMs: last.atMs + 60 * 60 * 1000),
      ],
      stale: false,
    );
    expect(m.state, MotionState.unknown);
    expect(m.stoppedForMs, isNull);
  });

  test('a claim resumes once enough contiguous pings land after an outage', () {
    final before = ramp(12, 5000, 0, 5000);
    final last = before.last;
    // Four minutes of fresh, contiguous, stationary pings after the gap.
    final after = [
      for (var i = 0; i < 49; i++)
        MotionSample(
          distanceM: 5000,
          atMs: last.atMs + 60 * 60 * 1000 + i * 5000,
        ),
    ];
    final m = motionFor(samples: [...before, ...after], stale: false);
    expect(m.state, MotionState.stopped);
    // Measured from the far side of the gap only, never through it.
    expect(m.stoppedForMs, 48 * 5000);
    expect(m.atLeast, isTrue);
  });

  test('a tolerated gap can never be most of the shortest claim', () {
    // The constant is a proportion, not a guarantee — pin the proportion so
    // a future widening has to argue with this test rather than slip past.
    expect(motionMaxGapMs * 6 <= motionMinWindowMs, isTrue);
  });

  test('a gap at the accepted limit is vouched for, one millisecond past it is not',
      () {
    List<MotionSample> spanning(int gapMs) {
      final base = ramp(motionMinWindowMs ~/ 5000 + 1, 5000, 0, 5000);
      return [
        ...base,
        MotionSample(distanceM: 5000, atMs: base.last.atMs + gapMs),
      ];
    }

    expect(motionFor(samples: spanning(motionMaxGapMs), stale: false).state,
        MotionState.stopped);
    // Past the limit the vouched window is the single trailing ping.
    expect(motionFor(samples: spanning(motionMaxGapMs + 1), stale: false).state,
        MotionState.unknown);
  });

  test('only the gap nearest the newest ping bounds the window', () {
    // Two outages. The vouched window starts after the LATER one, so the
    // earlier stretch cannot leak back into the claim.
    final samples = <MotionSample>[
      const MotionSample(distanceM: 1000, atMs: t0),
      const MotionSample(distanceM: 1000, atMs: t0 + 30 * 60 * 1000),
      for (var i = 0; i < 49; i++)
        MotionSample(distanceM: 1000, atMs: t0 + 60 * 60 * 1000 + i * 5000),
    ];
    final m = motionFor(samples: samples, stale: false);
    expect(m.state, MotionState.stopped);
    expect(m.stoppedForMs, 48 * 5000);
  });

  test('a rewound odometer cannot manufacture a stopped verdict', () {
    // A re-armed recorder resets distance to 0 mid-stream; the naive delta
    // is a large negative number, which must not read as "covered no
    // ground". Contiguous cadence throughout, so the gap rule is not what
    // is under test here.
    final samples = <MotionSample>[
      ...ramp(18, 5000, 10, 12000),
      ...ramp(19, 5000, 10, 0).map(
        (s) => MotionSample(distanceM: s.distanceM, atMs: s.atMs + 18 * 5000),
      ),
    ];
    final m = motionFor(samples: samples, stale: false);
    expect(m.state, MotionState.moving);
    expect(m.windowDistanceM! > 0, isTrue);
  });
}

/// Spectator motion state: is the runner we CAN see actually moving?
///
/// `live_freshness` answers "can we see them at all" and the surface is
/// scrupulous about it — a lost-signal runner reads DELAYED, never LIVE.
/// The complementary question had no answer: a runner whose phone is still
/// pinging every few seconds from the same spot renders as a fresh green
/// LIVE dot, and the one derived stat that would have exposed it (recent
/// pace) computes a zero distance delta and returns null, so the readout
/// simply disappears. Silence about "not moving" and silence about "no
/// data yet" looked identical, and the more alarming of the two is the one
/// that vanished.
///
/// This grades a window of recent pings into `moving` / `stopped` /
/// `unknown`. It is deliberately a NEUTRAL report, not an alarm: a runner
/// stopped for six minutes is at an aid station, and one stopped for
/// ninety is a question for their crew. The surface states the fact and
/// the duration; it draws no conclusion the data cannot support.
///
/// Fail-closed in three directions. A stale fix yields `unknown` — the
/// last position being old is exactly the case where "they have not moved"
/// is unknowable, and reporting a stationary runner off pre-dropout pings
/// would be the same lie in a new place. A gap inside the buffer yields
/// `unknown` too, for the same reason arriving through a different door: a
/// runner who reconnects near where they dropped out has not been observed
/// standing there, and the outage must not be counted as stillness. And
/// too short an observation window yields `unknown`, because a five-ping
/// buffer at a 5 s cadence spans twenty seconds and every runner alive
/// stands still for twenty seconds at a road crossing.
///
/// TS↔Dart parity pair with `apps/web/src/lib/safety/live_motion.ts` —
/// keep in lockstep. `atMs` is a Dart `int` (epoch ms, as every other
/// live-surface clock here is) rather than web's `number`, so the
/// non-finite guard covers only the odometer on this side.
library;

/// The window must span at least this much WALL CLOCK before any claim is
/// made. Three minutes is past every ordinary pause a moving runner takes
/// (traffic light, gate, shoe, photo) and well inside the time a spectator
/// would want to know about a genuine stop.
const int motionMinWindowMs = 180000;

/// Ground covered across the window at or below which the runner counts as
/// stopped. GPS jitter walks a stationary phone a few metres per fix and
/// does not average out, so the floor has to absorb an accumulating
/// random walk over minutes rather than a single fix's error.
const double motionStoppedDistanceM = 25;

/// The longest gap between two consecutive pings the window may span. A
/// claim about a runner staying put is a claim about every moment in
/// between, and a hole in the telemetry is precisely where they could have
/// left and come back. Everything before a longer gap is discarded rather
/// than vouched for, so a reconnection after an hour off-grid starts the
/// observation again instead of reading the whole outage as stillness.
/// No gap length is perfectly safe — at a slow jog a runner clears the
/// stopped radius and returns in about twenty seconds — so this is a
/// proportion, not a guarantee: six missed pings at the ~5 s broadcast
/// cadence absorbs ordinary cellular flakiness while keeping any tolerated
/// hole to at most a sixth of the shortest claim the helper will make.
const int motionMaxGapMs = 30000;

enum MotionState { moving, stopped, unknown }

class MotionSample {
  /// Run odometer at this ping, metres.
  final double distanceM;

  /// Wall-clock time the ping was sent, epoch ms. Deliberately NOT the
  /// ping's `elapsed_s`: a recorder that auto-paused freezes elapsed while
  /// the runner is genuinely standing still, which would shrink the
  /// observed window to nothing in exactly the case worth reporting.
  final int atMs;

  const MotionSample({required this.distanceM, required this.atMs});
}

class LiveMotion {
  final MotionState state;

  /// How long the runner has been continuously within
  /// [motionStoppedDistanceM] of where they are now, ms. Null unless
  /// [state] is [MotionState.stopped]. It reaches back through the final
  /// metres of the approach, so it can exceed the moment they actually
  /// halted by the time it took them to cover that radius — bounded, and
  /// the right side to err on for a claim phrased as "has not left this
  /// spot".
  final int? stoppedForMs;

  /// The stopped span reached the start of the vouched window — either the
  /// oldest sample held or the far side of a gap — so the real duration is
  /// at least [stoppedForMs] and possibly longer. The surface must say "at
  /// least" rather than state the figure flat.
  final bool atLeast;

  /// Wall-clock span actually observed, ms. Null when no claim is made.
  final int? windowMs;

  /// Ground covered across that span, metres. Null when no claim is made.
  final double? windowDistanceM;

  const LiveMotion({
    required this.state,
    required this.stoppedForMs,
    required this.atLeast,
    required this.windowMs,
    required this.windowDistanceM,
  });
}

const LiveMotion _unknown = LiveMotion(
  state: MotionState.unknown,
  stoppedForMs: null,
  atLeast: false,
  windowMs: null,
  windowDistanceM: null,
);

LiveMotion motionFor({
  required List<MotionSample> samples,
  required bool stale,
}) {
  if (stale) return _unknown;

  final all = samples.where((s) => s.distanceM.isFinite).toList()
    ..sort((a, b) => a.atMs.compareTo(b.atMs));
  if (all.length < 2) return _unknown;

  // Only the contiguous run ending at the newest ping is evidence. A
  // caller holding a buffer that straddles an outage would otherwise hand
  // us a pre-gap sample as the start of an unbroken stop.
  var firstVouched = 0;
  for (var i = all.length - 1; i > 0; i--) {
    if (all[i].atMs - all[i - 1].atMs > motionMaxGapMs) {
      firstVouched = i;
      break;
    }
  }
  final vouched = all.sublist(firstVouched);
  if (vouched.length < 2) return _unknown;

  final newest = vouched.last;
  final oldest = vouched.first;
  final windowMs = newest.atMs - oldest.atMs;
  if (windowMs < motionMinWindowMs) return _unknown;

  // A rewound odometer (a re-armed recorder, a replayed backlog) would
  // otherwise read as negative ground covered and grade as stopped.
  final windowDistanceM = (newest.distanceM - oldest.distanceM).abs();

  // Walk back from the newest sample while the runner stayed within the
  // stopped radius of where they are now. The first sample that breaks
  // out bounds the stop; reaching the oldest held sample means the stop
  // began before our window and the duration is a floor, not a figure.
  var stopStartIndex = vouched.length - 1;
  for (var i = vouched.length - 2; i >= 0; i--) {
    if ((newest.distanceM - vouched[i].distanceM).abs() > motionStoppedDistanceM) {
      break;
    }
    stopStartIndex = i;
  }
  final stoppedForMs = newest.atMs - vouched[stopStartIndex].atMs;

  // The stop must itself clear the minimum window: a runner who covered
  // ground for most of the observed span and has been still for forty
  // seconds is moving, not stopped.
  if (stoppedForMs < motionMinWindowMs) {
    return LiveMotion(
      state: MotionState.moving,
      stoppedForMs: null,
      atLeast: false,
      windowMs: windowMs,
      windowDistanceM: windowDistanceM,
    );
  }

  return LiveMotion(
    state: MotionState.stopped,
    stoppedForMs: stoppedForMs,
    atLeast: stopStartIndex == 0,
    windowMs: windowMs,
    windowDistanceM: windowDistanceM,
  );
}

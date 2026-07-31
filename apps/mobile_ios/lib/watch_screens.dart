import 'dart:typed_data';

import 'sim_watch_sync.dart' show crc32;

/// Pure Dart mirror of the custom watch's `watch_core::screens` SCR1 wire
/// format — the phone → watch composed-data-screen push.
///
/// The watch ships 40 built-in glance pages, one of them a multi-field
/// dashboard. A composed screen is the runner's own: a [WatchLayout] plus the
/// [WatchMetric]s to fill it, authored on the phone and pushed as one frame.
///
///   magic("SCR1", 4) | version(1) | count(1) | flags(1) | reserved(1) |
///   screen[count] | crc32(4, u32 LE)
///
/// where each screen is `layout(1) | metric[3] (u8, 0 = empty slot)`.
///
/// **One frame is the whole set** — a replacement, never a delta — so a push
/// that lands is the complete answer to "what screens does this watch have".
/// At [kMaxScr1Len] = 28 bytes it fits one ATT write inside the 256-byte MTU,
/// so unlike `watch_course.dart` / `watch_workout.dart` it is **not chunked**.
///
/// The same bytes are the watch's flash record, so a frame this encoder emits
/// is what a runner still has after a power cycle.
///
/// Deliberately pure — no BLE, no platform channels — so [encodeWatchScreens]
/// is unit-testable against the frozen golden vector shared with the Rust
/// tests (`watch_core::screens::the_golden_frame_is_stable`), reusing the
/// run-sync module's [crc32] like the sibling encoders.
const int _screensVersion = 0x01;

/// How many screens a runner may compose — mirrors
/// `watch_core::screens::MAX_SCREENS`.
///
/// The ceiling is navigation, not storage: every screen is a page in the § 350
/// cycle, and § 289's press-cost model is a function of page count alone.
const int kMaxWatchScreens = 4;

/// Slots per screen — mirrors `watch_core::screens::SCREEN_SLOTS`.
const int kWatchScreenSlots = 3;

const int _screensHeaderLen = 8;
const int _screensEntryLen = 1 + kWatchScreenSlots;
const int _screensCrcLen = 4;

/// Largest a SCR1 record can be — one ATT write, and the watch's flash-read
/// buffer.
const int kMaxScr1Len =
    _screensHeaderLen + kMaxWatchScreens * _screensEntryLen + _screensCrcLen;

/// How a screen arranges its slots — mirrors `watch_core::screens::Layout`.
///
/// Byte 3 is deliberately unassigned: it is the seat a four-slot `Quad` would
/// take, and the firmware rejects it until it can draw one.
enum WatchLayout {
  /// One metric, the full 32x48 hero — what every built-in glance page does.
  single(0, 1, 'single'),

  /// Two metrics stacked, both in the 32x48 hero face. The only multi-field
  /// layout that costs nothing in legibility.
  duo(1, 2, 'duo'),

  /// A 32x48 hero over two 16x32 rows: one thing you are watching and two you
  /// are keeping an eye on.
  trio(2, 3, 'trio');

  const WatchLayout(this.wire, this.slots, this.wireName);

  /// The wire discriminant. Stable, and hand-written for the same reason
  /// [WatchMetric.wire] is.
  final int wire;

  /// How many slots this layout draws.
  final int slots;

  /// The stable cross-platform name, pinned against the Rust `wire_name` so a
  /// reorder on either side is a red test rather than a silent re-point.
  final String wireName;
}

/// What a composed screen's slot may headline — the closed catalogue mirroring
/// `watch_core::face::Metric`.
///
/// **The byte is stable and hand-written.** A screen layout names its slots by
/// these bytes and that layout is persisted to the watch's flash and pushed
/// over the radio, so deriving them from declaration order would silently
/// re-point every saved screen the first time someone reordered this enum for
/// tidiness. 0 is deliberately not a metric: it is the empty slot in a layout
/// carrying fewer than [kWatchScreenSlots] values.
enum WatchMetric {
  elapsed(1, 'elapsed'),
  distance(2, 'distance'),
  avgPace(3, 'avg_pace'),
  lapElapsed(4, 'lap_elapsed'),
  heartRate(5, 'heart_rate'),
  pacerDelta(6, 'pacer_delta'),
  guidedRunRemaining(7, 'guided_run_remaining'),
  workoutRemaining(8, 'workout_remaining'),
  racePrediction(9, 'race_prediction'),
  cutoffMargin(10, 'cutoff_margin'),
  trainingStress(11, 'training_stress'),
  roadbookNext(12, 'roadbook_next'),
  fuelCarbs(13, 'fuel_carbs'),
  gearWear(14, 'gear_wear'),
  easyPace(15, 'easy_pace'),
  vo2Max(16, 'vo2_max'),
  altitude(17, 'altitude'),
  distanceToStart(18, 'distance_to_start'),
  daylightCountdown(19, 'daylight_countdown'),
  waypointDistance(20, 'waypoint_distance'),
  climbGain(21, 'climb_gain'),
  recapDistance(22, 'recap_distance'),
  currentStreak(23, 'current_streak'),
  syncedMovingTime(24, 'synced_moving_time'),
  prAge(25, 'pr_age'),
  planReplanChanges(26, 'plan_replan_changes'),
  planAdaptiveChanges(27, 'plan_adaptive_changes'),
  readinessScore(28, 'readiness_score'),
  goalPercent(29, 'goal_percent'),
  turnCueDistance(30, 'turn_cue_distance'),
  routeSimplifyDistance(31, 'route_simplify_distance'),
  autoEffortMatched(32, 'auto_effort_matched'),
  routeElevTotal(33, 'route_elev_total'),
  raceDayDays(34, 'race_day_days'),
  sleepBudget(35, 'sleep_budget'),
  timerRemaining(36, 'timer_remaining'),
  backyardBell(37, 'backyard_bell');

  const WatchMetric(this.wire, this.wireName);

  /// This metric's byte on the SCR1 wire, in `1..=37`.
  final int wire;

  /// The stable cross-platform name for the byte, pinned test-for-test against
  /// the Rust `Metric::wire_name`.
  final String wireName;
}

/// One runner-composed screen: a layout and the metrics filling it.
class WatchScreen {
  /// Throws [ArgumentError] when the metric count and the layout disagree —
  /// too few for the layout, or one past its arity.
  ///
  /// The arity check is what stops a [WatchLayout.single] carrying three
  /// metrics of which two never draw: the runner would have chosen them, and
  /// the watch would silently ignore two thirds of that choice. The firmware
  /// refuses such a frame outright, so catching it here turns a rejected push
  /// into an error the editor can show.
  WatchScreen(this.layout, this.metrics) {
    if (metrics.length != layout.slots) {
      throw ArgumentError(
        'a ${layout.wireName} screen draws ${layout.slots} '
        'slot(s), given ${metrics.length}',
      );
    }
  }

  final WatchLayout layout;

  /// The metrics in draw order, top to bottom. Order is meaning: the same two
  /// metrics swapped is a different screen.
  final List<WatchMetric> metrics;
}

/// Encode a composed-screen set as one SCR1 frame.
///
/// Throws [ArgumentError] past [kMaxWatchScreens] rather than dropping the
/// overflow — a runner who composed five screens and got four would have no way
/// to tell which one went missing. An empty list is legitimate and encodes a
/// count of 0, which is how a runner clears their screens.
Uint8List encodeWatchScreens(List<WatchScreen> screens) {
  if (screens.length > kMaxWatchScreens) {
    throw ArgumentError(
      'a watch holds at most $kMaxWatchScreens screens, given ${screens.length}',
    );
  }
  final len =
      _screensHeaderLen + screens.length * _screensEntryLen + _screensCrcLen;
  final out = Uint8List(len);
  out[0] = 0x53; // 'S'
  out[1] = 0x43; // 'C'
  out[2] = 0x52; // 'R'
  out[3] = 0x31; // '1'
  out[4] = _screensVersion;
  out[5] = screens.length;
  out[6] = 0; // flags — none defined; a set bit rejects the frame
  out[7] = 0; // reserved

  var off = _screensHeaderLen;
  for (final s in screens) {
    out[off] = s.layout.wire;
    for (var i = 0; i < kWatchScreenSlots; i++) {
      out[off + 1 + i] = i < s.metrics.length ? s.metrics[i].wire : 0;
    }
    off += _screensEntryLen;
  }
  final crc = crc32(Uint8List.sublistView(out, 0, off));
  ByteData.sublistView(out).setUint32(off, crc, Endian.little);
  return out;
}

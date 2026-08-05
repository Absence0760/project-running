import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show PlanWorkoutRow, TrainingPlanRow;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_recorder/run_recorder.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../auth_error.dart';
import '../audio_cues.dart';
import '../backend_timeout.dart';
import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../embedded_bests.dart';
import '../goal_time.dart';
import '../health_connect_exporter.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../live_broadcaster.dart';
import '../live_hub_client.dart';
import '../main.dart' show pendingStartWorkout;
import '../live_cutoff_eta.dart';
import '../preferences.dart';
import '../privacy.dart';
import '../off_route_alert.dart';
import '../race_controller.dart';
import '../race_phases.dart';
import '../roadbook.dart';
import '../route_geometry.dart';
import '../route_markers.dart' show parseTarget;
import '../route_match.dart';
import '../route_simplify.dart';
import '../safety_nudge.dart';
import '../settings_sync.dart';
import '../turn_cue_announcer.dart';
import '../turn_cues.dart';
import '../widgets/cutoff_card.dart';
import 'route_picker_screen.dart';
import '../background_location_nudge.dart';
import '../battery_optimisation_hint.dart';
import '../run_notification_bridge.dart';
import '../run_stats.dart';
import '../social_service.dart';
import '../training.dart';
import '../training_service.dart';
import '../widgets/collapsible_panel.dart';
import '../widgets/ghost_pacer.dart';
import '../widgets/live_run_map.dart';
import '../widgets/live_share_indicator.dart';
import '../widgets/safety_nudge_banner.dart';
import '../widgets/todays_workout_card.dart';
import '../widgets/top_banner.dart';
import '../widgets/track_preview.dart' show projectTrack;
import '../widgets/upcoming_event_card.dart';
import '../widgets/workout_execution_band.dart';
import 'event_detail_screen.dart';
import 'plan_detail_screen.dart';
import 'plans_screen.dart';
import 'run_detail_screen.dart';
import 'workout_detail_screen.dart';

/// Whether the recording view should darken the live map to save battery
/// (issue #271). Only while actually recording (not during the countdown,
/// which paints its own scrim) and only when the wakelock is holding the
/// screen on — with the display already free to sleep there is nothing to
/// dim.
bool shouldDimRecordingMap({
  required bool isCountdown,
  required bool keepScreenOn,
  required bool dimWhileRecording,
}) =>
    !isCountdown && keepScreenOn && dimWhileRecording;

/// Broadcasts whether a run is actively recording so the nav shell
/// (`home_screen.dart`) can lock the bottom-nav swipe gesture mid-run — an
/// accidental swipe off the recording surface is disorienting and risky
/// (issue #490). Deliberate bottom-nav taps still navigate (they drive the
/// page controller directly, which a locked swipe physics doesn't block);
/// only the drag gesture is suppressed. Defaults to false and is reset to
/// false on tear-down, so a missed update leaves the nav swipeable
/// (fail-open — the lock is a safety nicety, never a core guarantee).
final ValueNotifier<bool> runRecordingActive = ValueNotifier<bool>(false);

/// Main run recording screen with GPS tracking, live stats, sync, audio cues,
/// auto-pause, countdown, and optional route following.
class RunScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final SocialService social;
  final RaceController? raceController;
  final TrainingService training;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final cm.Route? initialRoute;
  /// Source of the user's privacy zones for the live-broadcast path.
  /// Wired by the host (HomeScreen → SettingsSyncService.effective) so
  /// the LiveBroadcaster can drop in-zone pings client-side before
  /// they leave the device. Without this, the Go-hub transport leaks
  /// in-zone pings to anonymous spectators — the Supabase trigger
  /// only protects the legacy path. See decisions §33.
  final SettingsSyncService? settingsSync;
  /// Pre-loaded planned workout. When set, the run starts in
  /// "structured workout" mode — the [WorkoutExecutionBand] mounts and
  /// `_finishRun` writes `plan_workout_id` + `workout_step_results` +
  /// `workout_adherence` to `runs.metadata`.
  final PlanWorkoutRow? initialWorkout;

  /// An in-progress partial recovered at cold start whose process was killed
  /// mid-run. When set, RunScreen prompts the user to Resume (re-hydrate the
  /// recorder and continue the SAME run), Finish (finalize into a completed
  /// run), or Discard it. Resume is the primary path — it's the fix for a
  /// multi-day effort being split into two disjoint runs by a process kill.
  final cm.Run? initialResumablePartial;

  const RunScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
    this.settingsSync,
    required this.social,
    this.raceController,
    required this.training,
    required this.heartRate,
    required this.treadmill,
    this.initialRoute,
    this.initialWorkout,
    this.initialResumablePartial,
  });

  @override
  State<RunScreen> createState() => _RunScreenState();
}

enum _ScreenState { idle, countdown, recording, paused, finished }

/// The user's choice at the cold-start resume prompt for a process-killed
/// partial: continue the same run, finalize it as-is, or drop it.
enum _ResumeChoice { resume, finish, discard }

class _RunScreenState extends State<RunScreen> {
  _ScreenState _state = _ScreenState.idle;

  /// Single write path for [_state] so the cross-widget [runRecordingActive]
  /// signal can't drift from the screen's real state. A manual mid-session
  /// pause keeps [_state] at `recording` (it's tracked via `_manualPaused`),
  /// so the swipe lock stays on through a pause — the run isn't finished.
  void _setScreenState(_ScreenState next) {
    _state = next;
    runRecordingActive.value = next == _ScreenState.recording;
  }

  RunRecorder? _recorder;
  StreamSubscription<RunSnapshot>? _snapshotSub;

  // Heart-rate samples collected during a run via the paired BLE chest
  // strap (if any). Averaged on stop and written into `metadata.avg_bpm`.
  // Empty list + null avg when no strap is paired, which is fine —
  // metadata just omits the key.
  StreamSubscription<int>? _hrSub;
  // Auto-reconnect status of the BLE strap so a mid-run drop is disclosed
  // rather than the BPM readout silently flat-lining. Persona android #13.
  StreamSubscription<BleHrStatus>? _hrStatusSub;
  BleHrStatus _hrStatus = BleHrStatus.disconnected;
  final List<int> _bpmSamples = [];
  int? _currentBpm;

  // Treadmill (FTMS belt) live-mode toggle. Opt-in L4 distance-source
  // override: when on, belt samples drive the recorder's headline distance
  // via setTreadmillSample; when off the GPS/pedometer path is authoritative.
  // The belt link is the same app-owned singleton paired in Settings, so a
  // belt failure can never disturb the L0 clock / L1 distance path.
  StreamSubscription<TreadmillSample>? _treadmillSub;
  StreamSubscription<BleTreadmillStatus>? _treadmillStatusSub;
  bool _treadmillMode = false;
  bool _treadmillPaired = false;
  BleTreadmillStatus _treadmillStatus = BleTreadmillStatus.disconnected;
  double? _treadmillSpeedKmh;

  // Countdown
  int _countdownValue = 3;
  Timer? _countdownTimer;

  // Selected route (optional)
  cm.Route? _selectedRoute;

  // Turn-by-turn voice-cue state for the followed route. Rebuilt whenever the
  // selected route changes; null when no route is followed. Pure decision core
  // (turn_cue_announcer.dart) — cues fire through the best-effort _ttsCue
  // wrapper so a TTS failure never disturbs the recording (decisions §169).
  TurnCueAnnouncer? _turnAnnouncer;

  void _rebuildTurnAnnouncer() {
    final route = _selectedRoute;
    if (route == null || route.waypoints.length < 3) {
      _turnAnnouncer = null;
      return;
    }
    try {
      final cues = generateTurnCues(
        route.waypoints
            .map((w) => TurnCueWaypoint(w.lat, w.lng))
            .toList(growable: false),
      );
      _turnAnnouncer = cues.isEmpty ? null : TurnCueAnnouncer(cues);
    } catch (e) {
      debugPrint('turn-cue generation failed: $e');
      _turnAnnouncer = null;
    }
  }

  // Roadbook cutoff legs for the followed route, when it carries course
  // markers with cutoffs. Drives the live "next cut-off" card so an ultra
  // runner sees their cutoff buffer without doing the math by hand at hour 60
  // — the same engine (roadbook + live_cutoff_eta) the spectator /live/[id]
  // and planner surfaces already use. Empty when no route / no cutoffs.
  List<RoadbookLeg> _cutoffLegs = const [];

  // Course markers on the followed route that carry a target time
  // (meta.target_elapsed_s), sorted by position — the marker-cue set.
  List<_TargetMarker> _targetMarkers = const [];
  // Distance-along-route at the previous fix; a marker between this and the
  // current along-value has just been crossed.
  double? _lastAlongM;
  // Marker indices already announced this recording — GPS jitter can walk
  // the along-value backwards across a marker and would re-announce it.
  final Set<int> _announcedTargetMarkers = <int>{};
  DateTime? _lastCutoffCueAt;
  LiveCutoffStatus? _lastCutoffCueStatus;

  // Race pacing strategy: chosen pre-run, built into distance-
  // bounded phases at start. Empty plan = no strategy. The goal is kept
  // as the RAW text and re-parsed against the currently-resolved
  // distance — parsing once at sheet-OK time would freeze the "3:30 vs
  // 25:00" disambiguation against whatever route happened to be selected
  // then. _strategyDistanceM is a manual override only (null = follow
  // the selected route).
  RacePhasePreset? _strategyPreset;
  String _strategyGoalText = '';
  double? _strategyDistanceM;
  List<RacePhase> _phasePlan = const [];
  int _phaseIndex = -1;

  int? get _strategyGoalTimeS =>
      parseGoalTimeS(_strategyGoalText, distanceM: _resolvedStrategyDistanceM);

  double? get _strategyGoalPaceSecPerKm {
    final t = _strategyGoalTimeS;
    final d = _resolvedStrategyDistanceM;
    if (t == null || d == null || d <= 0) return null;
    return goalPaceSecPerKm(d, t.toDouble());
  }

  double? get _resolvedStrategyDistanceM {
    final manual = _strategyDistanceM;
    if (manual != null && manual > 0) return manual;
    final route = _selectedRoute;
    if (route == null || route.waypoints.length < 2) return null;
    return polylineLengthMetres(route.waypoints);
  }

  /// Load the followed route's cutoff legs. Best-effort (L4): fetched once at
  /// route selection (the runner is typically online at the start line) and
  /// cached; any failure — offline, no markers, malformed geometry — leaves
  /// the card hidden, never disturbing the core live stats. A mid-run dead
  /// zone simply keeps whatever was loaded at the start.
  /// Minute-of-day the cutoff clocks are measured from. Before the run starts
  /// that is "about now" — the runner is staging — so the pre-start card still
  /// reads true; [_startRecording] and the partial-run restore re-run the load
  /// once the real start is known.
  double _startClockMin() {
    final start = _runStartedAtWall ?? DateTime.now();
    return (start.hour * 60 + start.minute).toDouble();
  }

  Future<void> _loadCutoffLegs() async {
    final route = _selectedRoute;
    final api = widget.apiClient;
    final routeId = route?.id;
    if (route == null ||
        api == null ||
        routeId == null ||
        routeId.isEmpty ||
        route.waypoints.length < 2) {
      if ((_cutoffLegs.isNotEmpty || _targetMarkers.isNotEmpty) && mounted) {
        setState(() {
          _cutoffLegs = const [];
          _targetMarkers = const [];
        });
      }
      return;
    }
    try {
      final waypoints = route.waypoints;
      final markers = await api.fetchRouteMarkers(routeId);
      final targets = <_TargetMarker>[
        for (final m in markers)
          if (m.positionM != null && parseTarget(m.meta)?.elapsedS != null)
            _TargetMarker(
              positionM: m.positionM!,
              kind: m.kind,
              label: m.label,
              targetS: parseTarget(m.meta)!.elapsedS!,
            ),
      ]..sort((a, b) => a.positionM.compareTo(b.positionM));
      final legs = buildRoadbook(
        [
          for (final w in waypoints)
            RoadbookWaypoint(lat: w.lat, lng: w.lng, ele: w.elevationMetres),
        ],
        [
          for (final m in markers)
            RoadbookMarker(
              positionM: m.positionM,
              kind: m.kind,
              label: m.label,
              meta: m.meta,
            ),
        ],
        // A cutoff clock is a wall-clock time and resolves to an elapsed limit
        // only against the start's time of day — without this every
        // `cutoff_clock` marker (the only kind either editor can author)
        // yields no cutoff at all and the live card never appears.
        startClockMin: _startClockMin(),
        // The nominal goal doesn't reach the card (the live projection comes
        // from the runner's own pace), but it does pick which DAY a cutoff
        // clock lands on for a race that runs past midnight.
        goalSeconds: polylineLengthMetres(waypoints),
        model: PacingModel.even,
      ).legs;
      final next = legs.any((l) => l.cutoff != null)
          ? legs
          : const <RoadbookLeg>[];
      if (mounted) {
        setState(() {
          _cutoffLegs = next;
          _targetMarkers = targets;
        });
      }
    } catch (e) {
      debugPrint('cutoff-leg load failed: $e');
    }
  }

  /// The next-cutoff projection for the current live position, or null when
  /// there's no route with cutoffs / no fix yet / the runner is past the last
  /// cutoff. `stale` suppresses the verdict (the helper returns
  /// [LiveCutoffStatus.unknown]) rather than fabricating an ETA off an old fix.
  LiveCutoffEta? _cutoffEta(_LiveStats stats, bool stale) {
    if (_cutoffLegs.isEmpty) return null;
    final pos = stats.routePosition;
    final route = _selectedRoute;
    if (pos == null || route == null) return null;
    try {
      final distAlong =
          distanceAlongRoute((lat: pos.lat, lng: pos.lng), route.waypoints);
      if (distAlong == null) return null;
      final eta = nextCutoffEta(
        distAlongRouteM: distAlong,
        elapsedS: stats.elapsed.inSeconds.toDouble(),
        recentPaceSecPerKm: stats.pace,
        legs: _cutoffLegs,
        stale: stale,
      );
      return eta.checkpoint == null ? null : eta;
    } catch (e) {
      debugPrint('cutoff eta projection failed: $e');
      return null;
    }
  }

  /// Spoken fallback for a target marker with no label — the localized
  /// kind name, mirroring the route-markers panel's list labels.
  String _markerKindLabel(String kind) {
    final l10n = _l10n;
    return switch (kind) {
      'aid_station' => l10n.routeMarkerKindAidStation,
      'cutoff' => l10n.routeMarkerKindCutoff,
      'crew_access' => l10n.routeMarkerKindCrewAccess,
      'hazard' => l10n.routeMarkerKindHazard,
      'note' => l10n.routeMarkerKindNote,
      'climb' => l10n.routeMarkerKindClimb,
      _ => l10n.routeMarkerKindCustom,
    };
  }

  // Live stats. Mirror fields kept for internal consumers (_saveInProgress,
  // _refreshLockScreenNotification, the _formattedX getters). The hot-path
  // UI updates come through _statsNotifier so the per-second snapshot
  // rebuilds only the subtrees that actually show these values — not the
  // whole _buildRecording Stack (chips, banners tied to _gpsLost /
  // _permissionLost, layout widgets).
  Duration _elapsed = Duration.zero;
  double _distanceMetres = 0;
  double? _pace;
  List<cm.Waypoint> _track = [];
  cm.Waypoint? _currentPosition;
  // Last fix the recorder's distance chain accepted. Everything that maps a
  // position onto the followed route (turn cues, marker-target cues, the
  // cut-off ETA) reads this rather than the raw `_currentPosition`, which
  // deliberately carries rejected fixes so the blue dot keeps up.
  cm.Waypoint? _routePosition;
  int _lastTickNotified = 0;
  final ValueNotifier<_LiveStats> _statsNotifier =
      ValueNotifier(_LiveStats.empty);

  // Manual pause only — there is no longer any auto-pause layer. The clock
  // runs continuously during a run (except when the user explicitly taps
  // pause), and "moving time" is computed as a derived metric on the
  // finished-run screen from the GPS track.
  bool _manualPaused = false;
  DateTime? _lastSnapshotAt;

  // Has any GPS fix arrived during this run? Drives the indoor-mode
  // distance fallback below — when false, we use `steps × stride` instead
  // of `0` so a treadmill session shows a plausible distance even though
  // GPS never produced a fix. Flipped true on the first non-null
  // snapshot.currentPosition; reset on discard.
  bool _everHadGpsFix = false;

  // Running elevation gain, updated incrementally as new waypoints arrive
  // in _onSnapshot. The naive O(n) rescan of the full track on every
  // build was the hottest per-frame work in the run screen — a 60-minute
  // run rescans 3600+ points every tween tick (~60 Hz). This is the same
  // noise gate + dropout carry computeElevationGain applies to the
  // finished track, so the live figure and the run-detail figure agree.
  final ElevationGainAccumulator _elevationGain = ElevationGainAccumulator();
  int _elevationProcessedCount = 0;

  // Reentrancy guard on start — prevents rapid taps from spawning
  // multiple recorders.
  bool _startRequested = false;

  // Reentrancy guard on stop — _stop() awaits the recorder, the local save,
  // and the cloud push, and never nulls _recorder. Without this, a second
  // trigger (the lock-screen Stop action racing the on-screen hold-to-stop,
  // or a cold-start Stop intent flushed after the run already finished) would
  // re-run the whole stop path: a second runStore.save / clearInProgress and,
  // worse, a duplicate cloud saveRun + race-result submission. Set on the
  // first _stop, cleared on discard so the next run can stop cleanly.
  bool _stopRequested = false;

  // Crash-safe incremental persistence. A partial Run is serialised every
  // [_incrementalSaveInterval] during a recording; the id is generated at
  // _begin() so the saved run has a stable identity across ticks and across
  // a crash+recover cycle.
  static const _incrementalSaveInterval = Duration(seconds: 10);
  static const _uuid = Uuid();
  Timer? _incrementalSaveTimer;
  String? _runId;
  DateTime? _runStartedAtWall;

  // Live spectator broadcast. Off by default — flips on when the user
  // taps "Share live link". Holds the throttled ping pump that runs
  // alongside `_onSnapshot` while a run is in flight. Only constructed
  // when an authenticated ApiClient is available — anonymous /
  // offline-only sessions skip the broadcaster entirely.
  LiveBroadcaster? _liveBroadcaster;
  // The runner explicitly asked to share this run's live link. Kept so the
  // broadcast is (re)attached when the run starts even if the pre-GO begin
  // failed transiently and the auto-live-share pref is off — otherwise a
  // shared link would stay permanently dead (persona-woman safety finding).
  bool _liveShareRequested = false;
  // A live broadcast was begun for this run id (the is_public=true stub
  // exists server-side), whether or not it is still active at stop. The
  // stop path uses it to resolve the saved run's visibility — the live
  // window's public opt-in must not silently outlive the run (issue #664).
  bool _liveBroadcastBegun = false;
  // Drives the persistent live-share indicator on the recording chrome
  // (issue #613). Flipped true once the broadcaster is attached and false
  // only when the broadcast is torn down (run finish, or an explicit
  // stop-share) — navigating away / minimizing keeps it true because the
  // run screen is a keep-alive tab. A dedicated notifier (not a read of
  // `_liveBroadcaster.isActive`) because attach/detach happen outside
  // setState, so the indicator needs its own rebuild signal.
  final ValueNotifier<bool> _liveShareActive = ValueNotifier<bool>(false);

  // GPS signal state. If snapshots stop arriving for > _gpsLostThreshold we
  // show a banner warning the runner so they're not surprised at stop time.
  static const _gpsLostThreshold = Duration(seconds: 10);
  bool _gpsLost = false;
  Timer? _gpsLostCheckTimer;

  // Weak-GPS (accuracy-gate) state. The recorder drops low-accuracy fixes so
  // distance stops advancing under tree cover / in an urban canyon. Without a
  // banner the runner thinks the app froze. `_weakGpsLatest` mirrors the most
  // recent snapshot's flag (written in _onSnapshot, no setState — hot path);
  // `_weakGps` is the debounced UI flag flipped by _checkGpsHealth's setState.
  bool _weakGpsLatest = false;
  bool _weakGps = false;

  // Permission watchdog — polls Geolocator.checkPermission() so we can
  // warn the runner if location permission is revoked mid-run in Android
  // settings.
  Timer? _permissionWatchdogTimer;
  bool _permissionLost = false;

  // Pedometer resubscribe back-off — if the stream errors we wait a bit,
  // then try again. Failures during a run shouldn't silently drop the
  // cadence widget forever.
  int _pedometerRetries = 0;
  static const _pedometerMaxRetries = 5;

  // Hold-to-stop UX — the progress ticker now lives inside
  // _HoldToStopButton so the 60 Hz rebuild is scoped to that button,
  // not the whole RunScreen. RunScreen just exposes `_stop` as the
  // `onHoldComplete` callback; nothing else is needed here.

  // Laps
  int _lapCount = 0;

  // Activity type — defaults to ActivityType.run so it's safe to read
  // before initState; initState overrides from the user's
  // `default_activity_type` setting (mirrored into Preferences).
  ActivityType _activityType = ActivityType.run;

  // ── Structured workout execution ──
  // Mounted when the run was started from a planned workout. The
  // runner consumes _onSnapshot output and emits transition / drift
  // events into _workoutEventsSub. Band UI listens via _workoutBand.
  WorkoutRunner? _workoutRunner;
  StreamSubscription<WorkoutExecEvent>? _workoutEventsSub;
  String? _activeWorkoutId;
  final ValueNotifier<WorkoutBandState> _workoutBand =
      ValueNotifier(WorkoutBandState.empty);

  // Pace alerts
  DateTime? _lastPaceAlertAt;
  // Session-only mute for live pace cues. Not persisted — a group-run
  // runner silences the pace nagging for this run, their saved audio-cue
  // preference is untouched (round-5 social-group).
  bool _paceCuesMuted = false;

  // False when the user picked minimal voice feedback — suppresses the
  // chatty in-rep progress + pace-drift cues (round-5 older).
  bool get _voiceVerbose =>
      widget.preferences.voiceFeedbackVerbosity != 'minimal';

  bool get _workoutCuesEnabled =>
      widget.preferences.voiceCueEnabled(VoiceCue.workoutSteps);

  // Off-route
  double? _offRouteDistance;
  bool _offRouteWarned = false;
  static const double _offRouteThresholdMetres = 40;

  // Off-route → auto-notify safety contact (docs/features/safety.md).
  // Armed in _attachRecordingSideEffects only when the deploy flag + the
  // runner's opt-in pref are on and a route is selected; null = inert.
  // _offRouteAlertFiring guards a second RPC while the first is in flight
  // (the detector also latches once-per-run).
  OffRouteAlertDetector? _offRouteAlertDetector;
  bool _offRouteAlertFiring = false;

  // Solo-safety nudge — a persistent, dismissible in-tree banner (not a
  // transient toast) so it can't be missed. Set true by _maybeShowSafetyNudge
  // at run start; cleared when the runner acts.
  bool _safetyNudgeVisible = false;

  // Distance remaining on selected route
  double? _routeRemaining;

  // Step tracking
  StreamSubscription<StepCount>? _stepSub;
  int _startSteps = 0;
  // The pedometer's cumulative counter is only meaningful relative to a
  // baseline taken once recording starts. `_startSteps == 0` cannot stand in
  // for "not baselined yet": on resume the computed baseline is legitimately
  // 0 whenever no sensor event has landed, and re-baselining then threw away
  // the steps carried over from the crashed run.
  bool _stepBaselineSet = false;
  // Steps a resumed partial brought with it; the baseline is biased by this
  // so (event.steps - _startSteps) continues from there rather than 0.
  int _stepsCarriedIn = 0;
  int _steps = 0;
  int _cadence = 0;
  final List<_StepSample> _stepSamples = [];

  // Prepare-phase state. The recorder, GPS stream, pedometer, and wakelock
  // are warmed up at the start of the countdown so begin() is instant when
  // the 3 seconds are up.
  Future<void>? _prepareFuture;
  // Error from the in-flight [prepare], held (not swallowed) so _begin can
  // surface the typed error object through _notifyGpsUnavailable.
  Object? _prepareError;

  // Finished run
  cm.Run? _finishedRun;
  bool _synced = false;
  String? _syncError;

  // Next RSVP'd event in the social layer, if within the next 48h. Shown on
  // the idle Run tab as a priority card above the last-run summary.
  EventView? _upcomingEvent;

  // Active-plan overview; drives the today's-workout card on idle.
  ActivePlanOverview? _planOverview;

  // Measured height of the stats overlay — used to offset the map camera so
  // the blue dot sits in the visible area above the overlay, not behind it.
  final GlobalKey _statsOverlayKey = GlobalKey();
  double _statsOverlayHeight = 300;

  // Replaces geolocator's "Run in progress" foreground-service notification
  // with live time / distance / pace so the lock screen is useful mid-run.
  final RunNotificationBridge _lockScreen = RunNotificationBridge();
  DateTime? _lastNotificationAt;

  // Ephemeral top-anchored notices ("split done", "lap marked",
  // "no GPS") render via the shared `showTopBanner` Overlay helper
  // (lib/widgets/top_banner.dart). The recording surface keeps no
  // local banner state — single global entry, single dismiss path.

  // Localizations resolved once per dependency change (locale / theme
  // swap) and reused everywhere on the recording hot path — the
  // per-second `_onSnapshot` handler and the status announcers must never
  // call `AppLocalizations.of(context)` at GPS rate. See
  // apps/mobile_android/CLAUDE.md "Hot-path exception".
  late AppLocalizations _l10n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onPrefsChange);
    widget.runStore.addListener(_onPrefsChange);
    widget.social.addListener(_onSocialChange);
    widget.training.addListener(_onTrainingChange);
    pendingStartWorkout.addListener(_onPendingStartWorkout);
    _activityType =
        ActivityType.fromName(widget.preferences.defaultActivityType);
    _selectedRoute = widget.initialRoute;
    _loadTreadmillPairing();
    _rebuildTurnAnnouncer();
    _loadCutoffLegs();
    _maybePreloadWorkoutRunner();
    _refreshUpcomingEvent();
    _refreshPlanOverview();
    // Drain after first frame: if a deeper screen set
    // `pendingStartWorkout` *before* this State existed (lazy tab
    // construction), we'd have missed the listener fire. Run once
    // post-frame to consume whatever was queued.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPendingStartWorkout();
    });
    // A process-killed run was recovered as resumable at cold start. Prompt
    // once, after first frame (so `_l10n` + a Navigator context exist), to
    // Resume / Finish / Discard it — resume the primary path.
    final resumable = widget.initialResumablePartial;
    if (resumable != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _promptResume(resumable);
      });
    }
  }

  /// Best-effort check for a previously-paired treadmill. The mode toggle
  /// only renders when a belt is paired — otherwise it would do nothing, so
  /// the user is pointed at Settings → Integrations instead. L4: a read
  /// failure leaves the toggle hidden rather than disturbing the screen.
  Future<void> _loadTreadmillPairing() async {
    try {
      final name = await widget.treadmill.pairedName();
      if (!mounted) return;
      setState(() => _treadmillPaired = name != null);
    } catch (e) {
      debugPrint('treadmill pairedName check failed: $e');
    }
  }

  void _onPendingStartWorkout() {
    final wo = pendingStartWorkout.value;
    if (wo == null) return;
    if (!mounted) return;
    if (_state != _ScreenState.idle) {
      // A run is already in progress / saving — don't clobber. Leave
      // the notifier set; the user can finish or discard, return to
      // idle, and the post-frame drain on the next state transition
      // would still need to be revisited if we want to honour it.
      debugPrint('pendingStartWorkout dropped: state=$_state');
      return;
    }
    pendingStartWorkout.value = null;
    _startStructuredWorkout(wo);
  }

  /// Build a [WorkoutRunner] from the incoming planned workout — its
  /// `structure` jsonb plus the plan's `paces` bag — so the run starts
  /// already aware of its first step.
  Future<void> _maybePreloadWorkoutRunner() async {
    final wo = widget.initialWorkout;
    if (wo == null) return;
    Map<String, int> paces = const {};
    try {
      // `.timeout` so a hung backend doesn\'t leave the workout
      // runner half-initialised (cm-pre-load is best-effort —
      // missing paces just means the runner uses defaults). See
      // backend_timeout.dart for the 15 s ceiling.
      final plan = await widget.training
          .fetchPlanForWorkout(wo)
          .timeout(kBackendLoadTimeout);
      paces = _pacesFromPlan(plan);
    } catch (e) {
      debugPrint('Failed to load plan paces for workout ${wo.id}: $e');
    }
    if (!mounted) return;
    final structure = wo.structure is Map<String, dynamic>
        ? wo.structure as Map<String, dynamic>
        : null;
    final steps = expandWorkoutSteps(
      structure: structure,
      paces: paces,
      toleranceSecPerKm: wo.targetPaceToleranceSec ?? 10,
      fallbackDistanceMetres: wo.targetDistanceM,
      fallbackPaceSecPerKm: wo.targetPaceSecPerKm,
    );
    if (steps.isEmpty) return;
    final runner = WorkoutRunner(steps: steps);
    _workoutEventsSub = runner.events.listen(_onWorkoutEvent);
    _workoutRunner = runner;
    _activeWorkoutId = wo.id;
    _publishWorkoutBand();
  }

  /// Build the symbolic pace bag that resolves `'easy'`, `'jog'`,
  /// `'tempo'`, etc. for [expandWorkoutSteps]. Plans on this codebase
  /// don't store an explicit `paces` jsonb today — we re-derive from
  /// the goal pace using the same `resolveTrainingPaces` helper the
  /// generator uses, which keeps the running-time bands identical to
  /// what the editor showed.
  Map<String, int> _pacesFromPlan(TrainingPlanRow? plan) {
    if (plan == null) return const {};
    try {
      final tp = resolveTrainingPaces(
        goalDistanceM: plan.goalDistanceM,
        goalTimeSec: plan.goalTimeSeconds,
        recent5kSec: plan.current5kSeconds,
      );
      return <String, int>{
        'easy': tp.easy,
        'jog': tp.easy + 60,
        'marathon': tp.marathon,
        'tempo': tp.tempo,
        'interval': tp.interval,
        'repetition': tp.repetition,
      };
    } catch (e, st) {
      // L4 (auxiliary): pace-bag derivation is a hint for the workout
      // runner; if it throws (NaN goal pace, divide-by-zero on a
      // 0-distance plan), the runner falls back to step-local
      // targets. Log so the failure surfaces in `flutter logs`
      // without masking a deeper bug, but never let this block the
      // recording layer below.
      debugPrint('run_screen: _pacesFromPlan failed: $e\n$st');
      return const {};
    }
  }

  void _onWorkoutEvent(WorkoutExecEvent e) {
    // Every announceX returns a Future and can reject if the TTS engine
    // hasn't initialised (Play Services TTS update mid-run, missing
    // language pack on a fresh install). The synchronous try/catch
    // we used to use only caught sync throws — async rejections leaked
    // out as unhandled errors. _ttsCue() does the unawaited+catchError
    // dance so the cue is fire-and-forget but the rejection is logged
    // instead of escaping.
    if (e is StepTransitionEvent) {
      _publishWorkoutBand();
      if (widget.preferences.audioCues && _workoutCuesEnabled) {
        _ttsCue(
            'announceWorkoutStepTransition',
            () => widget.audioCues
                .announceWorkoutStepTransition(e.step, widget.preferences.unit));
      }
    } else if (e is StepProgressEvent) {
      // Chatty in-rep progress ("halfway", "fifty metres to go") — dropped
      // in minimal voice-feedback mode (round-5 older).
      if (widget.preferences.audioCues && _workoutCuesEnabled && _voiceVerbose) {
        _ttsCue('announceWorkoutStepProgress',
            () => widget.audioCues.announceWorkoutStepProgress(e.step, e.kind));
      }
    } else if (e is PaceDriftEvent) {
      // Pace-drift nudge — also dropped in minimal mode.
      if (widget.preferences.audioCues && _workoutCuesEnabled && _voiceVerbose) {
        _ttsCue('announceWorkoutPaceDrift',
            () => widget.audioCues.announceWorkoutPaceDrift(e));
      }
    } else if (e is WorkoutCompleteEvent) {
      _publishWorkoutBand();
      if (widget.preferences.audioCues && _workoutCuesEnabled) {
        _ttsCue('announceWorkoutComplete',
            () => widget.audioCues.announceWorkoutComplete());
      }
    } else if (e is WorkoutAbandonedEvent) {
      _publishWorkoutBand();
    }
  }

  /// Fire-and-forget TTS announcement. Wraps both synchronous and
  /// asynchronous failures so a TTS-engine fault never escapes as an
  /// unhandled error.
  void _ttsCue(String label, Future<void> Function() invoke) {
    try {
      unawaited(invoke().catchError((Object e) {
        debugPrint('$label failed (async): $e');
      }));
    } catch (e) {
      debugPrint('$label failed (sync): $e');
    }
  }

  /// Ghost-pacer position for the current workout step. Returns null
  /// (and the LiveRunMap hides the marker) whenever the ghost is
  /// undefined or off the planned route — see [ghostPacerPosition]
  /// for the cases. The marker is only useful when a planned route
  /// is loaded: without one there's no "where you should be" path.
  cm.Waypoint? _computeGhostPosition() {
    final runner = _workoutRunner;
    if (runner == null) return null;
    final step = runner.currentStep;
    if (step == null) return null;
    final route = _selectedRoute;
    if (route == null) return null;
    final path = route.waypoints;
    if (path.length < 2) return null;
    return ghostPacerPosition(
      path: path,
      elapsed: runner.stepElapsed,
      targetPaceSecPerKm: step.targetPaceSecPerKm,
    );
  }

  void _publishWorkoutBand() {
    final runner = _workoutRunner;
    if (runner == null) {
      _workoutBand.value = WorkoutBandState.empty;
      return;
    }
    final step = runner.currentStep;
    _workoutBand.value = WorkoutBandState(
      step: step,
      totalSteps: runner.steps.length,
      currentIndex: runner.currentStepIndex,
      progress: runner.progressFraction,
      remainingMetres: runner.stepRemainingMetres,
      remainingDuration: runner.stepRemainingDuration,
      actualPaceSecPerKm: runner.stepAveragePaceSecPerKm,
      adherence: runner.paceAdherence,
      complete: runner.isComplete && step == null,
      abandoned: false,
    );
  }

  Future<void> _refreshUpcomingEvent() async {
    try {
      final evt = await widget.social
          .fetchNextRsvpedEvent()
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _upcomingEvent = evt);
    } catch (e) {
      // Non-critical — leave the card hidden if the fetch fails. Log
      // so an upstream API rename doesn't surface only as a missing
      // UI card. See docs/architecture/conventions.md § Layered resilience.
      debugPrint('refresh upcoming-event card failed: $e');
    }
  }

  Future<void> _refreshPlanOverview() async {
    try {
      final p = await widget.training
          .fetchActiveOverview()
          .timeout(kBackendLoadTimeout);
      if (mounted) setState(() => _planOverview = p);
    } catch (e) {
      // Non-critical — same logging rationale as `_refreshUpcomingEvent`.
      debugPrint('refresh plan-overview card failed: $e');
    }
  }

  // Both services notify several times in a row when the user takes a
  // single action (e.g. RSVP toggle → membership row update + count
  // refresh + my-rsvp refresh). Debounce so we don't fire 3 fetches
  // for one logical change.
  Timer? _socialDebounce;
  Timer? _trainingDebounce;
  static const _listenerDebounce = Duration(milliseconds: 500);

  void _onSocialChange() {
    _socialDebounce?.cancel();
    _socialDebounce = Timer(_listenerDebounce, () {
      if (mounted) _refreshUpcomingEvent();
    });
  }

  void _onTrainingChange() {
    _trainingDebounce?.cancel();
    _trainingDebounce = Timer(_listenerDebounce, () {
      if (mounted) _refreshPlanOverview();
    });
  }

  @override
  void didUpdateWidget(covariant RunScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoute != null &&
        widget.initialRoute != oldWidget.initialRoute &&
        _state == _ScreenState.idle) {
      setState(() => _selectedRoute = widget.initialRoute);
      _rebuildTurnAnnouncer();
      _loadCutoffLegs();
    }
  }

  /// Fires on both `Preferences` changes and `LocalRunStore` updates (e.g.
  /// the 10-second incremental save during a run). Only trigger a rebuild
  /// when the user can actually see the result — during active recording
  /// the screen reads its stats from snapshots, not from the prefs or the
  /// run store, so a full rebuild every 10s would be pure waste.
  void _onPrefsChange() {
    if (!mounted) return;
    if (_state == _ScreenState.recording ||
        _state == _ScreenState.countdown ||
        _state == _ScreenState.paused) {
      return;
    }
    setState(() {});
  }

  /// Ask for location + notification permissions but don't block the run on
  /// the result — denying location drops the run into a time-only indoor
  /// mode rather than stopping it outright. Denying notifications disables
  /// the live lock-screen stats via [RunNotificationBridge] but otherwise
  /// lets the run proceed. The downstream [RunRecorder.prepare] call
  /// surfaces the denied location case as a snackbar via
  /// [_notifyGpsUnavailable].
  Future<void> _maybeRequestPermission() async {
    await Permission.location.request();
    // POST_NOTIFICATIONS on Android 13+ — without this,
    // NotificationManager.notify silently no-ops and the lock-screen stats
    // never appear. Idempotent; skipped by the OS on older versions.
    final notif = await Permission.notification.request();
    // A denied notification permission used to be swallowed: the run still
    // recorded but the live lock-screen notification never showed, with no
    // explanation. Surface a one-time hint so the runner knows why (and that
    // recording is unaffected). Android-only — iOS routes notifications
    // differently and the live-notification bridge is a no-op there.
    if (Platform.isAndroid &&
        !notif.isGranted &&
        !widget.preferences.notifDeniedHintShown) {
      try {
        await widget.preferences.setNotifDeniedHintShown();
      } catch (e) {
        debugPrint('setNotifDeniedHintShown failed: $e');
      }
      if (mounted) {
        _showTopBanner(
          _l10n.runNotificationsOffHint,
          duration: const Duration(seconds: 6),
          actionLabel: _l10n.runSettings,
          onAction: () => openAppSettings(),
        );
      }
    }
  }

  /// Android 11+ only grants "while in use" from the initial dialog;
  /// background recording needs "Allow all the time", which the OS
  /// routes through app settings. If foreground location is granted but
  /// background isn't, surface a one-tap deep-link to settings before the
  /// run starts (persona #57). Non-blocking — the run proceeds either
  /// way; recording still works while the app is on screen. Shows once:
  /// a dismissal persists (issue #266) and only re-arms if always-on is
  /// later granted then revoked.
  Future<void> _maybeNudgeBackgroundLocation() async {
    if (!Platform.isAndroid) return;
    final foreground = await Permission.location.isGranted;
    final always = await Permission.locationAlways.isGranted;
    if (shouldRearmBackgroundLocationNudge(
      alwaysGranted: always,
      alreadyDismissed: widget.preferences.backgroundLocationNudgeDismissed,
    )) {
      try {
        await widget.preferences.setBackgroundLocationNudgeDismissed(false);
      } catch (e) {
        debugPrint('clearBackgroundLocationNudgeDismissed failed: $e');
      }
    }
    if (!shouldNudgeBackgroundLocation(
      isAndroid: Platform.isAndroid,
      foregroundGranted: foreground,
      alwaysGranted: always,
      alreadyDismissed: widget.preferences.backgroundLocationNudgeDismissed,
    )) {
      return;
    }
    // Mark dismissed up front so a crash / early-dismiss can't re-trigger
    // it on the next run — either dialog action is an informed choice, and
    // the re-arm above restores the nudge if the permission later regresses.
    try {
      await widget.preferences.setBackgroundLocationNudgeDismissed(true);
    } catch (e) {
      debugPrint('setBackgroundLocationNudgeDismissed failed: $e');
    }
    if (!mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.runBackgroundLocationNudgeTitle),
        content: Text(_l10n.runBackgroundLocationNudgeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.runStartAnyway),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.runOpenSettings),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await openAppSettings();
    }
  }

  /// One-time OEM battery-optimisation disclosure. Aggressive OEM app-killers
  /// (Samsung Stamina, Xiaomi, OnePlus) freeze the recording foreground
  /// service mid-run unless the app is exempted from battery optimisation,
  /// silently truncating a long effort. Surface a single dismissible hint
  /// deep-linking to the battery-optimisation settings (App Info as the
  /// fallback). Android-only, non-blocking — the run proceeds either way.
  /// Wrapped so a settings-deep-link failure can't abort the run start.
  Future<void> _maybeShowBatteryOptHint() async {
    if (!shouldShowBatteryOptHint(
      isAndroid: Platform.isAndroid,
      alreadyShown: widget.preferences.batteryOptHintShown,
    )) {
      return;
    }
    // Mark shown up front so a crash / early-dismiss can't re-trigger it on
    // the next run — the hint is informational, once is enough.
    try {
      await widget.preferences.setBatteryOptHintShown();
    } catch (e) {
      debugPrint('setBatteryOptHintShown failed: $e');
    }
    if (!mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.runBatteryOptHintTitle),
        content: Text(_l10n.runBatteryOptHintBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.runNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.runOpenSettings),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await openBatteryOptimisationExemption(
        isAndroid: Platform.isAndroid,
        openAppSettingsFallback: openAppSettings,
      );
    }
  }

  Future<void> _selectRoute() async {
    final routes = widget.routeStore.routes;
    if (routes.isEmpty) {
      showTopBanner(context, _l10n.runNoRoutesSaved);
      return;
    }
    final unit = widget.preferences.unit;
    // Full-screen page (was a modal bottom sheet). Surfaces a
    // search field at the top + sorts starred routes first per
    // user feedback. See `route_picker_screen.dart`.
    final picked = await pickRoute(context, routes: routes, unit: unit);
    if (!mounted) return;
    setState(() => _selectedRoute = picked);
    _rebuildTurnAnnouncer();
    _loadCutoffLegs();
  }

  Future<void> _beginCountdown() async {
    if (_startRequested || _state != _ScreenState.idle) return;
    _startRequested = true;
    await _maybeRequestPermission();
    if (!mounted) {
      _startRequested = false;
      return;
    }
    await _maybeNudgeBackgroundLocation();
    if (!mounted) {
      _startRequested = false;
      return;
    }
    await _maybeShowBatteryOptHint();
    if (!mounted) {
      _startRequested = false;
      return;
    }
    setState(() {
      _setScreenState(_ScreenState.countdown);
      _countdownValue = 3;
    });

    // Warm up everything that would otherwise delay the start of the run —
    // GPS stream, pedometer sensor, wakelock — while the countdown ticks.
    _preload();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdownValue <= 1) {
        t.cancel();
        _begin();
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  /// Kick off all asynchronous setup that's needed before the run can start
  /// cleanly. Runs during the countdown so the user doesn't see a delay when
  /// it ends.
  /// #14: wire the lock-screen notification's Pause / Resume / Stop buttons to
  /// the recorder. The actions route through the native RunNotificationBridge →
  /// MainActivity → method channel; here we map them onto the same handlers the
  /// on-screen controls use, so a11y announcements + UI state stay consistent.
  /// Android-only — on iOS the notification has no action buttons so these
  /// never fire. Shared by the fresh-start [_preload] and the [_resumeInProgress]
  /// paths.
  void _wireLockScreenControls() {
    _lockScreen.onPause = () {
      if (!mounted || _recorder == null || _manualPaused) return;
      _toggleManualPause();
    };
    _lockScreen.onResume = () {
      if (!mounted || _recorder == null || !_manualPaused) return;
      _toggleManualPause();
    };
    _lockScreen.onStop = () {
      if (!mounted || _recorder == null) return;
      _stop();
    };
  }

  void _preload() {
    _recorder = RunRecorder();
    _snapshotSub = _recorder!.snapshots.listen(_onSnapshot);

    _wireLockScreenControls();

    // Pedometer sensor stream. We subscribe now, but don't count steps
    // toward the run until _begin sets a baseline.
    _subscribeToPedometer();

    // Keep the screen awake from the start of the countdown onward,
    // unless the user has turned the wakelock off in Settings.
    if (widget.preferences.keepScreenOn) {
      WakelockPlus.enable();
    }

    // Open the GPS stream now so the first fix is already in hand when the
    // run starts. Positions received during this phase drive the blue dot
    // but don't accumulate into the track or distance. A failure is HELD in
    // _prepareError, not swallowed: _begin surfaces it via
    // _notifyGpsUnavailable (non-blocking snackbar) and proceeds in
    // time-only indoor mode — the recorder's retry loop self-heals once
    // services come back. The handler is attached here rather than at
    // _begin's await three seconds later because Dart reports an error that
    // completes on a listener-less future to the zone as uncaught, so the
    // documented indoor-fallback path was emitting a spurious error report
    // on every occurrence.
    final adv = widget.preferences.advancedGps;
    _prepareError = null;
    _prepareFuture = _recorder!
        .prepare(
      route: _selectedRoute,
      distanceFilterMetres: adv ? 2 : _activityType.gpsDistanceFilter,
      minMovementMetres: adv ? 1 : _activityType.minMovementMetres,
      maxSpeedMps: _activityType.maxSpeedMps,
      accuracy: adv ? LocationAccuracy.best : LocationAccuracy.high,
    )
        .catchError((Object e) {
      _prepareError = e;
    });
  }

  /// Subscribe to the pedometer stream. On error, wait a bit and retry —
  /// a transient sensor glitch shouldn't kill the cadence widget for the
  /// rest of the run.
  void _subscribeToPedometer() {
    _stepSub?.cancel();
    _stepSub = Pedometer.stepCountStream.listen((event) {
      _pedometerRetries = 0; // reset back-off on successful event
      if (_state != _ScreenState.recording) return;
      if (!_stepBaselineSet) {
        _startSteps = event.steps - _stepsCarriedIn;
        _stepBaselineSet = true;
      }
      final newSteps = event.steps - _startSteps;
      _stepSamples.add(_StepSample(DateTime.now(), newSteps));
      final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
      _stepSamples.removeWhere((s) => s.time.isBefore(cutoff));
      if (_stepSamples.length >= 2) {
        final first = _stepSamples.first;
        final last = _stepSamples.last;
        final dt = last.time.difference(first.time).inMilliseconds / 1000.0;
        if (dt > 1) {
          _cadence = ((last.steps - first.steps) / dt * 60).round();
        }
      }
      if (mounted) setState(() => _steps = newSteps);
    }, onError: (e) {
      debugPrint('Pedometer stream error: $e');
      if (_pedometerRetries >= _pedometerMaxRetries) return;
      _pedometerRetries++;
      // Exponential-ish backoff capped at 16s.
      final delay = Duration(seconds: (1 << _pedometerRetries).clamp(1, 16));
      Future.delayed(delay, () {
        if (!mounted) return;
        if (_state == _ScreenState.idle ||
            _state == _ScreenState.finished) return;
        _subscribeToPedometer();
      });
    });
  }

  /// Flip the run on. All expensive setup was already done in [_preload];
  /// this is synchronous aside from a last-resort await on the prepare
  /// future in case it hasn't completed yet.
  /// Pre-mint the run id (so the live URL is stable across the
  /// "share now → tap GO later" gap) and hand it to the system share
  /// sheet. The web spectator page at `/live/{run_id}` is empty until
  /// the runner starts pushing pings — that's a documented behaviour
  /// of `apps/web/src/routes/live/[run_id]`.
  Future<void> _shareLiveLink() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      // A /live link only ever goes live for a signed-in broadcaster; sharing
      // one while signed out hands the recipient a permanently dead link.
      if (mounted) _showTopBanner(_l10n.runLiveShareNeedsSignIn);
      return;
    }
    _runId ??= _uuid.v4();
    final base = _liveLinkBase();
    final url = '$base/live/${_runId!}';

    // Record the intent before the (best-effort) begin so a transient failure
    // here is recovered when the run starts, even if auto-live-share is off.
    _liveShareRequested = true;
    final started = await _startLiveBroadcast();

    try {
      await Share.share(url, subject: _l10n.runShareSubject);
    } catch (e) {
      // The user-facing banner is the primary signal, but also log
      // so a Share.share regression is observable in dev/release
      // logs without us reproducing the user's exact moment.
      debugPrint('Share.share live link failed: $e');
      if (mounted) _showTopBanner(_l10n.runCouldNotShareLink(friendlyError(_l10n, e)));
      return;
    }

    if (!started && mounted) {
      // Don't let a failed begin masquerade as a working live link. When idle,
      // the intent flag makes the run retry the broadcast on GO; mid-run the
      // runner can re-tap Share. Either way, disclose that it isn't live yet.
      _showTopBanner(_l10n.runLiveShareNotStarted);
    }
  }

  /// Tapped the persistent live-share indicator (issue #613). Offers the
  /// two mid-run actions the runner previously had no way to reach: re-open
  /// the OS share sheet to (re)send the link, or stop the live share.
  Future<void> _onLiveShareIndicatorTap() async {
    final action = await showLiveShareSheet(context);
    if (action == null || !mounted) return;
    switch (action) {
      case LiveShareAction.reshare:
        await _shareLiveLink();
      case LiveShareAction.stop:
        await _stopLiveShare();
    }
  }

  /// Stop the live share mid-run without ending the run. Concludes the
  /// broadcast (stamps runs.concluded_at so spectators see a real
  /// conclusion, not a frozen-then-stale feed) and detaches the pump; the
  /// run keeps recording. Clears [_liveShareRequested] so a later GO / auto
  /// path doesn't silently re-broadcast against the runner's choice.
  Future<void> _stopLiveShare() async {
    _liveShareRequested = false;
    final lb = _liveBroadcaster;
    final api = widget.apiClient;
    final id = _runId;
    if (api != null && api.userId != null && id != null &&
        lb != null && lb.isActive) {
      try {
        await api.concludeLiveBroadcast(id).timeout(kBackendLoadTimeout);
      } catch (e) {
        debugPrint('concludeLiveBroadcast (stop-share) failed: $e');
      }
    }
    lb?.detach();
    _liveShareActive.value = false;
    if (mounted) _showTopBanner(_l10n.runLiveShareStopped);
  }

  /// Pre-create the parent runs row + flip the broadcaster on so the
  /// first ping after _begin() lands successfully. The runs row is
  /// marked is_public=true (the opt-in to the LIVE window — either the
  /// user's "Share live link" tap or the auto_live_share device pref);
  /// that opt-in ends with the run: _stop resolves the saved run's
  /// visibility via _resolvePostLiveVisibility, so it follows the
  /// runner's default unless they explicitly keep it public (issue
  /// #664). Skipped on anonymous sessions — only signed-in users
  /// can broadcast. Returns whether the broadcaster is attached.
  Future<bool> _startLiveBroadcast() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return false;
    _runId ??= _uuid.v4();
    // LiveHubClient stays nil-effect when `LIVE_HUB_URL` is unset
    // — the broadcaster falls back to the legacy
    // `live_run_pings` Supabase path. Once the Go hub is deployed
    // and the env var lands in the build, the broadcaster swaps to
    // the hub without any further client change.
    final hubUrl = dotenv.env['LIVE_HUB_URL'] ?? '';
    _liveBroadcaster ??= LiveBroadcaster(
      api,
      hubClient: hubUrl.isNotEmpty
          ? LiveHubClient(baseUrl: hubUrl)
          : null,
      // Re-evaluated on every pushPing so a mid-run "add privacy
      // zone" save in Settings takes effect immediately. Without
      // this wire, the Go-hub transport leaks in-zone pings to
      // anonymous spectators — the Supabase trigger
      // `live_run_pings_drop_in_zone` only protects the legacy
      // path. See decisions §33.
      privacyZonesProvider: () => _currentPrivacyZones(),
    );
    try {
      await api
          .beginLiveBroadcast(
            runId: _runId!,
            startedAt: _runStartedAtWall ?? DateTime.now(),
            activityType: _activityType.name,
          )
          .timeout(kBackendLoadTimeout);
      _liveBroadcaster!.attach(_runId!);
      _liveBroadcastBegun = true;
      _liveShareActive.value = true;
      return true;
    } catch (e) {
      debugPrint('beginLiveBroadcast failed: $e');
      return false;
    }
  }

  /// The auto_live_share device pref (docs/features/safety.md). False
  /// when settings aren't available (signed out, sync not wired) —
  /// fail-closed: no silent broadcast without the explicit opt-in.
  bool get _autoLiveShareEnabled {
    final service = widget.settingsSync?.service;
    if (service == null) return false;
    try {
      return service.effective<bool>(
            SettingsKeys.autoLiveShare,
            fallback: false,
          ) ==
          true;
    } catch (e) {
      debugPrint('auto_live_share read failed: $e');
      return false;
    }
  }

  /// The OFF_ROUTE_ESCALATION_ENABLED deploy flag (docs/features/safety.md).
  /// Fail-closed: unset/false → the whole off-route auto-notify path is inert
  /// (the CISO/counsel deploy gate).
  bool get _offRouteEscalationEnabled =>
      dotenv.isInitialized &&
      offRouteEscalationEnabled(dotenv.env['OFF_ROUTE_ESCALATION_ENABLED']);

  /// The runner's `safety_off_route_alerts` opt-in (default false). False when
  /// settings aren't available — fail-closed.
  bool get _offRouteAlertsPrefEnabled {
    final service = widget.settingsSync?.service;
    if (service == null) return false;
    try {
      return service.effective<bool>(
            SettingsKeys.safetyOffRouteAlerts,
            fallback: false,
          ) ==
          true;
    } catch (e) {
      debugPrint('safety_off_route_alerts read failed: $e');
      return false;
    }
  }

  /// Whether an off-route escalation could actually reach the contact right
  /// now: a backend to call, a run to name, and an active live broadcast so
  /// the `/live` link the contact receives works. Checked BEFORE the
  /// detector's sustain clock is advanced — see the call site in
  /// [_onSnapshot].
  bool get _offRouteEscalationDeliverable =>
      widget.apiClient != null &&
      _runId != null &&
      (_liveBroadcaster?.isActive ?? false);

  /// Fire the off-route trusted-contact escalation once (docs/features/safety.md).
  /// The RPC re-checks every server-side gate (owner, opt-in, confirmed
  /// contact, once-per-run). L4 — best-effort, its own catch path; a failure
  /// must never touch the recording.
  void _escalateOffRoute() {
    final api = widget.apiClient;
    final runId = _runId;
    if (api == null || runId == null) return;
    _offRouteAlertFiring = true;
    unawaited(api.escalateRunOffRoute(runId).then((escalated) {
      if (escalated && mounted) {
        _showTopBanner(
          _l10n.runOffRouteAlertSent,
          duration: const Duration(seconds: 6),
        );
      }
    }).catchError((Object e) {
      debugPrint('escalateRunOffRoute failed: $e');
    }));
  }

  /// Throttled, dismissible prompt to share a live link when a solo run
  /// starts after dark with no live share attached — the safety-net gap
  /// for runners who never turned on auto-live-share (docs/features/safety.md,
  /// persona-woman). The decision is the pure `shouldSurfaceSoloSafetyNudge`
  /// twin; this method only gathers inputs and flips the persistent-banner
  /// flag. The banner stays until the runner acts (`_onSafetyNudgeShare` /
  /// `_dismissSafetyNudge`), and only an action stamps the throttle — a
  /// missed nudge is never suppressed. Entirely L4: wrapped so any failure
  /// here can never disturb the recording.
  void _maybeShowSafetyNudge() {
    try {
      final service = widget.settingsSync?.service;
      // No settings service → we can't throttle, so nudging would nag on
      // every run (friction). Fail-closed: skip.
      if (service == null) return;

      final now = DateTime.now();
      final dismissedIso =
          service.effective<String>(SettingsKeys.safetyNudgeDismissedAt);
      final lastActedAtMs =
          DateTime.tryParse(dismissedIso ?? '')?.millisecondsSinceEpoch;

      final should = shouldSurfaceSoloSafetyNudge(SoloSafetyNudgeSurfaceInput(
        nowLocalMinutes: now.hour * 60 + now.minute,
        latitude: _currentPosition?.lat,
        dayOfYear: now.difference(DateTime(now.year)).inDays + 1,
        autoLiveShareOn: _autoLiveShareEnabled,
        isBroadcast: _liveBroadcaster?.isActive ?? false,
        lastActedAtMs: lastActedAtMs,
        nowMs: now.millisecondsSinceEpoch,
      ));
      if (!should || !mounted) return;

      setState(() => _safetyNudgeVisible = true);
    } catch (e) {
      debugPrint('safety nudge failed: $e');
    }
  }

  /// "Share" action on the persistent safety banner: stamp the throttle,
  /// hide the banner, and share the live link.
  void _onSafetyNudgeShare() {
    _dismissSafetyNudge();
    unawaited(_shareLiveLink());
  }

  /// "Not now" action (or any acted-on dismissal) on the persistent safety
  /// banner: hide it and stamp the throttle so it stays suppressed for the
  /// window. Stamping ONLY on an action (not on show) is the fix — a nudge
  /// the runner never engaged with must resurface next dark solo run.
  void _dismissSafetyNudge() {
    if (mounted) setState(() => _safetyNudgeVisible = false);
    try {
      final service = widget.settingsSync?.service;
      if (service == null) return;
      // Fire-and-forget; a failed write just risks re-surfacing next run,
      // which is the safe direction.
      service.updateDevice({
        SettingsKeys.safetyNudgeDismissedAt:
            DateTime.now().toUtc().toIso8601String(),
      }).catchError((Object e) {
        debugPrint('safety nudge stamp failed: $e');
      });
    } catch (e) {
      debugPrint('safety nudge stamp failed: $e');
    }
  }

  /// Base URL of the spectator web app. Reads `WEB_BASE_URL` from
  /// `.env.local` when set; otherwise falls back to the production host
  /// so a freshly-installed app still produces a working link.
  String _liveLinkBase() {
    final fromEnv = dotenv.env['WEB_BASE_URL'] ?? '';
    if (fromEnv.isNotEmpty) {
      return fromEnv.replaceAll(RegExp(r'/+$'), '');
    }
    return 'https://threkir.com';
  }

  Future<void> _begin() async {
    // In the common case prepare has already completed during the 3-second
    // countdown, so this await is a no-op. On a slow device it waits for
    // the GPS stream to come up before starting the clock. If prepare
    // failed (location services off, permission denied), the recorder is
    // still marked prepared and we proceed into an indoor/time-only run —
    // the stopwatch ticks, distance stays 0, and the live map shows its
    // "Waiting for GPS..." placeholder until a fix arrives (if ever).
    await _prepareFuture;
    final prepareError = _prepareError;
    if (prepareError != null) _notifyGpsUnavailable(prepareError);

    if (!mounted || _recorder == null) return;

    // Announced-turn state is per-recording. The announcer is only rebuilt when
    // the SELECTED ROUTE changes, so a second run on the same route reused the
    // fully-latched fired set and spoke no turn cues at all. Every recording
    // funnels through here, so this is the one place that can't be bypassed.
    _turnAnnouncer?.reset();

    _recorder!.begin();

    // Stable run id + wall-clock start time for incremental persistence.
    // If the user pre-minted the id (e.g. by tapping "Share live link"
    // before pressing GO) reuse it so the spectator URL they already
    // copied stays valid.
    _runId ??= _uuid.v4();
    _runStartedAtWall = DateTime.now();
    // Rebind the cutoff clocks to the real start — the legs were built while
    // staging, off an approximate one.
    _loadCutoffLegs();

    // Reset the pedometer baseline so steps taken during the countdown
    // don't count toward the run.
    _stepsCarriedIn = 0;
    _stepBaselineSet = false;
    _startSteps = 0;
    _steps = 0;
    _cadence = 0;
    _stepSamples.clear();

    _attachRecordingSideEffects();

    // Build the race-strategy phase plan for this recording and
    // reset the per-recording cue trackers.
    final strategyDist = _resolvedStrategyDistanceM;
    _phasePlan = _strategyPreset != null && strategyDist != null
        ? buildPhasePlan(strategyDist, _strategyPreset!)
        : const [];
    _phaseIndex = -1;
    _lastAlongM = null;
    _announcedTargetMarkers.clear();
    _lastCutoffCueAt = null;
    _lastCutoffCueStatus = null;

    if (widget.preferences.audioCues &&
        widget.preferences.voiceCueEnabled(VoiceCue.startFinish)) {
      _ttsCue('announceStart', () => widget.audioCues.announceStart());
    }

    setState(() => _setScreenState(_ScreenState.recording));
    _announceA11yState(_l10n.runA11yStarted);
  }

  /// Shared post-begin wiring for both a fresh [_begin] and a
  /// [_resumeInProgress]: auto-live-share, the BLE HR + treadmill status
  /// streams, the crash-save / GPS-health / permission watchdog timers, and the
  /// live-race attach. The recorder is already recording and [_runId] /
  /// [_runStartedAtWall] are set before this runs. Step-baseline handling stays
  /// in each caller (a fresh run zeroes it; a resume continues from the
  /// persisted total).
  void _attachRecordingSideEffects() {
    // A previous run's split row survives in the shade across sessions
    // (it outlives the foreground service); drop it so this run starts
    // with a clean shade (#303). Bridge swallows its own failures (L4).
    _lockScreen.clearSplit();

    // Auto-live-share (docs/features/safety.md): the device pref starts
    // the broadcast on every run start, so the overdue escalation has a
    // telemetry stream to watch and a partner has a link to follow. L4 —
    // fire-and-forget in its own catch path; a failed share must never
    // touch the recording. Also (re)attach when the runner manually asked to
    // share this run's link (_liveShareRequested): a successful pre-GO begin
    // already left the broadcaster active so the `!isActive` guard skips it,
    // but a transient pre-GO failure is recovered here instead of leaving the
    // shared link dead.
    if (shouldStartBroadcastOnRunStart(
      autoLiveShareEnabled: _autoLiveShareEnabled,
      liveShareRequested: _liveShareRequested,
      broadcasterActive: _liveBroadcaster?.isActive ?? false,
    )) {
      unawaited(_startLiveBroadcast().then((attached) {
        if (attached && mounted) {
          _showTopBanner(_l10n.runAutoLiveShareStarted);
        }
      }).catchError((Object e) {
        debugPrint('auto live share failed: $e');
      }));
    }

    // Solo-run safety nudge (docs/features/safety.md): the complement of
    // the auto-share path — when the run is unprotected (no auto-share,
    // no manual broadcast) AND started after dark, prompt the runner to
    // share a live link. L4 — its own catch path; a failure computing
    // daylight or reading prefs must never touch the recording.
    _maybeShowSafetyNudge();

    // Off-route → auto-notify safety contact (docs/features/safety.md,
    // persona-woman). Arm the sustained-off-route detector only when the
    // deploy flag + the runner's opt-in pref are on, a route is selected (so
    // an off-route distance is computed), and we can reach the backend. The
    // escalation itself also requires an active live broadcast at fire time
    // (checked in _escalateOffRoute). Fail-closed: any gate off → null (inert).
    _offRouteAlertFiring = false;
    if (_offRouteEscalationEnabled &&
        _offRouteAlertsPrefEnabled &&
        _selectedRoute != null &&
        widget.apiClient?.userId != null) {
      _offRouteAlertDetector = OffRouteAlertDetector();
    } else {
      _offRouteAlertDetector = null;
    }

    // Subscribe to the BLE chest strap's BPM stream if a strap has been
    // paired. `connectCached` runs at app start in main.dart; the stream
    // is already producing if the strap is in range. Samples are
    // averaged on stop into `metadata.avg_bpm`.
    _bpmSamples.clear();
    _currentBpm = null;
    _hrSub = widget.heartRate.stream.listen(
      (bpm) {
        // Drop obviously bogus BLE readings before they reach the averaged
        // samples that feed metadata.avg_bpm (→ TRIMP → CTL/ATL/TSB) — the
        // same 30–230 bounds run_recorder + hr_zones apply, so one malformed
        // packet can't skew weeks of training load or the live readout.
        if (bpm < 30 || bpm > 230) return;
        _bpmSamples.add(bpm);
        // Stamp each new sample onto the recorder so the saved track
        // carries per-point BPM (and run_detail_screen's HR-zone
        // breakdown lights up for phone-recorded runs). The recorder
        // drops out-of-range values defensively.
        _recorder?.setHeartRate(bpm);
        if (mounted) setState(() => _currentBpm = bpm);
      },
      // The strap stream doesn't error today, but a future plugin
      // bump or a mid-run BT toggle could surface one — without an
      // onError, that becomes an unhandled async error and tears
      // down the whole zone.
      onError: (Object e) {
        debugPrint('heartRate.stream error: $e');
      },
    );

    // Disclose strap drops / reconnects while recording. The strap's
    // BPM stream just goes silent on a drop, so without this the live
    // BPM readout freezes on its last value with no explanation.
    _hrStatus = widget.heartRate.status;
    _hrStatusSub = widget.heartRate.statusStream.listen((s) {
      final prev = _hrStatus;
      _hrStatus = s;
      if (!mounted) return;
      switch (s) {
        case BleHrStatus.reconnecting:
          if (prev == BleHrStatus.connected) {
            _showTopBanner(_l10n.runHrStrapLostReconnecting);
          }
          setState(() => _currentBpm = null);
        case BleHrStatus.connected:
          if (prev == BleHrStatus.reconnecting) {
            _showTopBanner(_l10n.runHrStrapReconnected,
                duration: const Duration(seconds: 2));
          }
        case BleHrStatus.disconnected:
          if (prev == BleHrStatus.reconnecting) {
            _showTopBanner(_l10n.runHrStrapLostNoHr);
          }
          setState(() => _currentBpm = null);
        case BleHrStatus.connectFailed:
          // Strap was off / out of range at launch — auto-reconnect doesn't
          // retry this case, so offer a manual one-tap reconnect instead of
          // leaving the runner with a silently-dead HR readout.
          setState(() => _currentBpm = null);
          _showTopBanner(
            _l10n.runHrStrapNotFound,
            duration: const Duration(seconds: 6),
            actionLabel: _l10n.runReconnect,
            onAction: _reconnectHeartRate,
          );
        case BleHrStatus.connecting:
          break;
      }
    });

    // Disclose treadmill belt drops / reconnects while recording. The sample
    // pump is NOT started here — treadmill mode is an explicit opt-in via the
    // toggle (so a belt that happens to be in range can't hijack an outdoor
    // GPS run). This only mirrors the belt's connection state into the UI and
    // surfaces a banner on a mid-run drop; when the belt is lost the recorder
    // already degrades to the L0 clock + the pedometer-distance fallback.
    _treadmillStatus = widget.treadmill.status;
    _treadmillStatusSub = widget.treadmill.statusStream.listen((s) {
      final prev = _treadmillStatus;
      _treadmillStatus = s;
      if (!mounted) return;
      // Only disclose when the user actually engaged treadmill mode — a
      // background belt's connection churn shouldn't banner an outdoor run.
      if (!_treadmillMode) {
        setState(() {});
        return;
      }
      switch (s) {
        case BleTreadmillStatus.reconnecting:
          if (prev == BleTreadmillStatus.connected) {
            _showTopBanner(_l10n.runTreadmillLostReconnecting);
          }
          setState(() => _treadmillSpeedKmh = null);
        case BleTreadmillStatus.connected:
          if (prev == BleTreadmillStatus.reconnecting) {
            _showTopBanner(_l10n.runTreadmillReconnected,
                duration: const Duration(seconds: 2));
          }
        case BleTreadmillStatus.disconnected:
          if (prev == BleTreadmillStatus.reconnecting) {
            _showTopBanner(_l10n.runTreadmillLostFallback);
          }
          setState(() => _treadmillSpeedKmh = null);
        case BleTreadmillStatus.connectFailed:
          setState(() => _treadmillSpeedKmh = null);
          _showTopBanner(
            _l10n.runTreadmillNotFound,
            duration: const Duration(seconds: 6),
            actionLabel: _l10n.runReconnect,
            onAction: _reconnectTreadmill,
          );
        case BleTreadmillStatus.connecting:
          break;
      }
    });

    // Crash-safe incremental persistence — every 10s, write the current
    // track + stats to a separate file so a force-kill mid-run is recoverable.
    _incrementalSaveTimer =
        Timer.periodic(_incrementalSaveInterval, (_) => _saveInProgress());

    // GPS-lost banner watchdog — flag stale signal in the UI.
    _gpsLostCheckTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _checkGpsHealth());

    // Location permission watchdog — catch cases where the runner toggles
    // permission off in Android settings while the run is in flight.
    _permissionWatchdogTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkPermission(),
    );

    // If a live race is running, attach this recorder so pings flow and
    // the finished run auto-submits to the leaderboard.
    final race = widget.raceController?.active;
    if (race != null && race.isRunning) {
      widget.raceController!.attachRecorder(
        eventId: race.eventId,
        instance: race.instanceStart,
      );
    }
  }

  /// Prompt the user to Resume / Finish / Discard a process-killed partial
  /// recovered at cold start. Resume is the primary (highlighted) action —
  /// re-hydrating the recorder so a multi-day effort continues as ONE run
  /// instead of being split into two disjoint records. The prompt is modal
  /// (no barrier-dismiss) so the partial isn't silently left in limbo.
  Future<void> _promptResume(cm.Run partial) async {
    if (!mounted || _state != _ScreenState.idle) return;
    final choice = await showDialog<_ResumeChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.runResumeDialogTitle),
        content: Text(_l10n.runResumeDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ResumeChoice.discard),
            child: Text(_l10n.runDiscard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ResumeChoice.finish),
            child: Text(_l10n.runResumeFinishAction),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _ResumeChoice.resume),
            child: Text(_l10n.runResumeAction),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _ResumeChoice.resume:
        await _resumeInProgress(partial);
      case _ResumeChoice.finish:
        await _finalizeResumedPartial(partial);
      case _ResumeChoice.discard:
        await widget.runStore.clearInProgress();
        if (mounted) {
          _showTopBanner(_l10n.runResumeDiscardedBanner,
              duration: const Duration(seconds: 3));
        }
      case null:
        break;
    }
  }

  /// Re-hydrate the recorder from a persisted partial and CONTINUE the same
  /// run — the append-only in-progress file keeps accumulating onto the same
  /// run id, and the finished run carries the whole effort (track, laps,
  /// elapsed) as one record.
  Future<void> _resumeInProgress(cm.Run partial) async {
    if (_startRequested || _state != _ScreenState.idle) return;
    _startRequested = true;

    _runId = partial.id;
    _runStartedAtWall = partial.startedAt;
    // Same rebind as a fresh start: a run resumed hours later must measure its
    // cutoff clocks from when it actually began, not from now.
    _loadCutoffLegs();
    _activityType = ActivityType.fromName(
        partial.metadata?[cm.MetadataKeys.activityType] as String? ??
            _activityType.name);

    final strategy = partial.metadata?[cm.MetadataKeys.pacingStrategy];
    if (strategy is Map) {
      RacePhasePreset? preset;
      for (final p in RacePhasePreset.values) {
        if (p.wire == strategy['preset']) preset = p;
      }
      final dist = (strategy['distance_m'] as num?)?.toDouble();
      final goal = (strategy['goal_time_s'] as num?)?.toInt();
      if (preset != null && dist != null && dist > 0) {
        _strategyPreset = preset;
        _strategyDistanceM = dist;
        _strategyGoalText = goal == null ? '' : formatGoalTimeS(goal);
        _phasePlan = buildPhasePlan(dist, preset);
        _phaseIndex = -1;
      }
    }

    final restoredLaps = lapsFromCanonicalJson(
      (partial.metadata?[cm.MetadataKeys.laps] as List<dynamic>?) ??
          const <dynamic>[],
      startedAt: partial.startedAt,
    );
    final restoredSteps =
        (partial.metadata?[cm.MetadataKeys.steps] as num?)?.toInt() ?? 0;

    // Restore the followed route so off-route detection + the remaining-
    // distance UI survive a crash-recovered resume, mirroring what
    // _selectRoute() does at a fresh start. Best-effort against the local
    // library only (the runner is typically offline right after a crash) —
    // a route no longer in the store just means the run resumes unfollowed,
    // same as picking no route at all.
    final restoredRouteId = partial.routeId;
    if (restoredRouteId != null && restoredRouteId.isNotEmpty) {
      cm.Route? match;
      for (final r in widget.routeStore.routes) {
        if (r.id == restoredRouteId) {
          match = r;
          break;
        }
      }
      _selectedRoute = match;
      _rebuildTurnAnnouncer();
      unawaited(_loadCutoffLegs());
    }

    // Seed the mirror fields up front so an early crash-save (before the first
    // post-resume snapshot lands) still writes the full accumulated
    // track / stats, and the finish summary is continuous from the moment of
    // resume.
    _track = List<cm.Waypoint>.from(partial.track);
    _distanceMetres = partial.distanceMetres;
    _elapsed = partial.duration;
    _lapCount = restoredLaps.length;
    _steps = restoredSteps;
    _everHadGpsFix = partial.track.isNotEmpty;
    // Splits already announced before the process was killed must not
    // re-announce on the first post-resume snapshot: a fresh State starts at
    // tick 0, so 42 km of restored distance reads as a just-crossed split.
    final resumeTickInterval = widget.preferences.splitIntervalMetres > 0
        ? widget.preferences.splitIntervalMetres.toDouble()
        : _activityType.splitIntervalMetresFor(widget.preferences.unit);
    _lastTickNotified = UnitFormat.activityTicks(
        _displayDistanceMetres, resumeTickInterval);

    _recorder = RunRecorder();
    _snapshotSub = _recorder!.snapshots.listen(_onSnapshot);
    _wireLockScreenControls();
    _subscribeToPedometer();
    if (widget.preferences.keepScreenOn) {
      WakelockPlus.enable();
    }

    final adv = widget.preferences.advancedGps;
    try {
      await _recorder!.resumeSession(
        track: partial.track,
        distanceMetres: partial.distanceMetres,
        elapsed: partial.duration,
        startedAt: partial.startedAt,
        laps: restoredLaps,
        route: _selectedRoute,
        distanceFilterMetres: adv ? 2 : _activityType.gpsDistanceFilter,
        minMovementMetres: adv ? 1 : _activityType.minMovementMetres,
        maxSpeedMps: _activityType.maxSpeedMps,
        accuracy: adv ? LocationAccuracy.best : LocationAccuracy.high,
      );
    } catch (e) {
      _notifyGpsUnavailable(e);
    }

    if (!mounted || _recorder == null) {
      _startRequested = false;
      return;
    }

    // Continue the pedometer from the restored total: the baseline is biased
    // by restoredSteps so the handler's (event.steps - _startSteps) resumes
    // there rather than restarting at 0. Deferred to the first event when the
    // sensor hasn't reported yet — the counter only ticks on an actual step,
    // so a runner reading the Resume dialog usually hasn't produced one.
    _stepsCarriedIn = restoredSteps;
    _stepBaselineSet = false;
    _startSteps = 0;

    _attachRecordingSideEffects();

    setState(() => _setScreenState(_ScreenState.recording));
    _announceA11yState(_l10n.runA11yStarted);
    _showTopBanner(_l10n.runResumedBanner,
        duration: const Duration(seconds: 3));
    _startRequested = false;
  }

  /// Finalize a resumed partial into a completed run without continuing to
  /// record (the "Finish" choice). Mirrors the pre-existing crash-recovery
  /// finalize: stamp `recovered_from_crash`, save locally, and clear the
  /// in-progress file — the SyncService pushes it to the cloud on its next
  /// trigger. Stays on the idle surface with a confirmation banner. Save is
  /// guarded: if it throws, the in-progress file is left in place so the next
  /// launch can retry.
  Future<void> _finalizeResumedPartial(cm.Run partial) async {
    final metadata = Map<String, dynamic>.from(partial.metadata ?? {});
    metadata[cm.MetadataKeys.recoveredFromCrash] = true;
    metadata.remove(cm.MetadataKeys.inProgressSavedAt);
    final run = cm.Run(
      id: partial.id,
      startedAt: partial.startedAt,
      duration: partial.duration,
      distanceMetres: partial.distanceMetres,
      track: partial.track,
      routeId: partial.routeId,
      source: partial.source,
      externalId: partial.externalId,
      metadata: metadata,
      createdAt: partial.createdAt,
    );
    bool saved = false;
    try {
      await widget.runStore.save(run);
      saved = true;
    } catch (e) {
      debugPrint('Finalize resumed partial save failed: $e');
    }
    if (saved) await widget.runStore.clearInProgress();
    if (!mounted) return;
    _showTopBanner(
      saved ? _l10n.runResumeSavedBanner : _l10n.runSaveFailedRelaunch,
      duration: const Duration(seconds: 4),
    );
  }

  /// Manual heart-rate reconnect, driven by the "Reconnect" affordance on
  /// the strap-not-found banner. Best-effort L4 aux effect — wrapped so a
  /// BLE failure can never disturb the live recording. The status stream the
  /// banner reads from updates on its own as the connect progresses.
  Future<void> _reconnectHeartRate() async {
    try {
      final ok = await widget.heartRate.reconnect();
      if (!mounted) return;
      if (!ok) {
        _showTopBanner(
          _l10n.runHrStrapStillNotFound,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      debugPrint('Manual HR reconnect failed: $e');
    }
  }

  /// Turn treadmill (FTMS belt) live mode on/off mid-run. An L4 auxiliary
  /// effect layered on top of the live recording: on a failure it shows a
  /// banner and reverts the toggle, never tearing down the recorder. The
  /// recorder's [RunRecorder.setTreadmillSample] self-guards (own try/catch,
  /// drops bad samples), so this is the second layer of the contract — the
  /// L0 clock + L1 distance path survive any belt failure. Each effect
  /// (stream listen, recorder call) gets its own guard + debugPrint; the
  /// catch here is the toggle-level fallback, not a widened single catch.
  Future<void> _toggleTreadmillMode(bool on) async {
    if (on) {
      try {
        await _treadmillSub?.cancel();
        _treadmillSub = widget.treadmill.stream.listen(
          (sample) {
            try {
              _recorder?.setTreadmillSample(
                sample.speedMps,
                totalDistanceMetres: sample.totalDistanceMetres,
              );
            } catch (e) {
              debugPrint('treadmill setTreadmillSample failed: $e');
            }
            if (mounted) {
              setState(() => _treadmillSpeedKmh = sample.instantaneousSpeedKmh);
            }
          },
          onError: (Object e) {
            debugPrint('treadmill sample stream error: $e');
          },
        );
        setState(() {
          _treadmillMode = true;
          _treadmillSpeedKmh = null;
        });
        // A belt that was off / out of range at launch reports connectFailed
        // and never auto-retries — offer a one-tap reconnect, mirroring HR.
        if (_treadmillStatus == BleTreadmillStatus.connectFailed) {
          _showTopBanner(
            _l10n.runTreadmillNotFound,
            duration: const Duration(seconds: 6),
            actionLabel: _l10n.runReconnect,
            onAction: _reconnectTreadmill,
          );
        }
      } catch (e) {
        debugPrint('Enabling treadmill mode failed: $e');
        await _treadmillSub?.cancel();
        _treadmillSub = null;
        if (mounted) {
          setState(() => _treadmillMode = false);
          _showTopBanner(_l10n.runTreadmillNotFound);
        }
      }
    } else {
      await _treadmillSub?.cancel();
      _treadmillSub = null;
      try {
        _recorder?.clearTreadmillMode();
      } catch (e) {
        debugPrint('clearTreadmillMode failed: $e');
      }
      if (mounted) {
        setState(() {
          _treadmillMode = false;
          _treadmillSpeedKmh = null;
        });
      }
    }
  }

  /// Manual treadmill reconnect from the belt-not-found banner. Best-effort
  /// L4 aux effect — a BLE failure can never disturb the live recording.
  Future<void> _reconnectTreadmill() async {
    try {
      final ok = await widget.treadmill.reconnect();
      if (!mounted) return;
      if (!ok) {
        _showTopBanner(
          _l10n.runTreadmillNotFound,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e) {
      debugPrint('Manual treadmill reconnect failed: $e');
    }
  }

  void _onSnapshot(RunSnapshot snapshot) {
      final unit = widget.preferences.unit;

      // Sensor liveness comes from the fix's own acceptance time, never
      // from `currentPosition != null`: the recorder re-emits the LAST fix
      // on every 1 s tick, so a non-null position outlives the sensor and
      // a total GPS blackout would otherwise look permanently healthy.
      // Also latch _everHadGpsFix so we know whether to fall back to the
      // pedometer for distance.
      final fixedAt = snapshot.positionFixedAt;
      if (fixedAt != null) {
        _lastSnapshotAt = fixedAt;
        if (!_everHadGpsFix) _everHadGpsFix = true;
      }
      final positionFresh = fixedAt != null &&
          DateTime.now().difference(fixedAt) <= _gpsLostThreshold;
      // Route progress must only ever advance on a fix the recorder's
      // distance chain ACCEPTED. A rejected teleport still drives the blue
      // dot, but feeding it to distanceAlongRoute latches every course
      // marker it skipped over — permanently, since the announced set is
      // never un-latched.
      if (snapshot.currentPosition != null && snapshot.positionTrusted) {
        _routePosition = snapshot.currentPosition;
      }

      // Extend the elevation-gain accumulator with any new waypoints. The
      // recorder only appends to the track (no reordering / truncation
      // during a run), so processing just the tail is correct.
      final track = snapshot.track;
      if (track.length < _elevationProcessedCount) {
        // Defensive reset — shouldn't happen unless the recorder was
        // swapped out from under us (discard → new run inside the same
        // lifecycle, which does go through _discard anyway).
        _elevationGain.reset();
        _elevationProcessedCount = 0;
      }
      for (int i = _elevationProcessedCount; i < track.length; i++) {
        _elevationGain.add(track[i]);
      }
      _elevationProcessedCount = track.length;

      // Update the mirror fields so internal consumers (_saveInProgress,
      // _refreshLockScreenNotification, the _formattedX getters) see the
      // latest values immediately. No setState — the UI rebuilds are
      // driven by _statsNotifier below so only the stats-consuming
      // subtrees rebuild, not the whole screen.
      _elapsed = snapshot.elapsed;
      _distanceMetres = snapshot.distanceMetres;
      _pace = snapshot.currentPaceSecondsPerKm;
      _track = track;
      _currentPosition = snapshot.currentPosition;
      _offRouteDistance = snapshot.offRouteDistanceMetres;
      _routeRemaining = snapshot.routeRemainingMetres;
      // Mirror only — the visible banner flips through _checkGpsHealth's
      // setState (2 s cadence) so the GPS-rate snapshot stream never drives
      // a full-screen rebuild.
      _weakGpsLatest = snapshot.weakGps;
      _statsNotifier.value = _LiveStats(
        elapsed: _elapsed,
        distanceMetres: _distanceMetres,
        pace: _pace,
        track: _track,
        currentPosition: _currentPosition,
        routePosition: _routePosition,
        offRouteDistance: _offRouteDistance,
        routeRemaining: _routeRemaining,
      );
      // Debug-only sanity check that the mirror fields and the notifier
      // carry the same values. If a future edit updates one without the
      // other (the classic regression path when someone "cleans up" the
      // dual write), this trips immediately in dev builds. Stripped in
      // release by the Dart compiler.
      assert(() {
        final v = _statsNotifier.value;
        return v.elapsed == _elapsed &&
            v.distanceMetres == _distanceMetres &&
            identical(v.track, _track);
      }(), 'Mirror fields and _statsNotifier desynced — update them together.');

      // Every auxiliary effect below runs behind its own try/catch — if any
      // one fails (TTS init error, network race-ping error, flaky route
      // math on a corrupt route) the rest still fire, and the core stats
      // update above stays intact. The layering rule is: L0 (clock) and
      // L1 (GPS distance / pace in the setState above) must not be broken
      // by any failure in L4 auxiliaries.

      // L4 — Structured-workout runner. Pure snapshot consumer; emits
      // events (transitions, halfway / last-50m / pace-drift cues) onto
      // an async stream that _onWorkoutEvent drains, so ordering vs the
      // L0/L1 update above doesn't matter for cue synchrony. Wrapped so
      // a future runner change (e.g. corrupted step list, out-of-bounds
      // index) can't freeze the visible counters.
      try {
        final wr = _workoutRunner;
        if (wr != null && !wr.isComplete) {
          wr.onSnapshot(snapshot);
          _publishWorkoutBand();
        }
      } catch (e) {
        debugPrint('workout runner snapshot failed: $e');
      }

      // L4 — Live race spectator ping. Requires a real, FRESH GPS fix;
      // cadence throttled inside RaceController. Network / Supabase realtime
      // can throw; swallow and keep going.
      try {
        final pos = snapshot.currentPosition;
        if (pos != null && positionFresh) {
          widget.raceController?.pushPing(
            lat: pos.lat,
            lng: pos.lng,
            distanceM: snapshot.distanceMetres,
            elapsedS: snapshot.elapsed.inSeconds,
            bpm: _currentBpm,
          );
        }
      } catch (e) {
        debugPrint('raceController.pushPing failed: $e');
      }

      // L4 — Live spectator broadcast (separate from race-mode pings).
      // Active only when the user has tapped "Share live link"; throttled
      // inside the broadcaster. Same swallow-on-fail rule as race pings.
      // Gated on freshness so the spectator's live_freshness reads an
      // honest "updated N min ago" during a signal blackout instead of a
      // fresh, stationary runner re-pinged off a frozen coordinate.
      try {
        final pos = snapshot.currentPosition;
        if (pos != null && positionFresh) {
          _liveBroadcaster?.pushPing(
            lat: pos.lat,
            lng: pos.lng,
            distanceM: snapshot.distanceMetres,
            elapsedS: snapshot.elapsed.inSeconds,
            bpm: _currentBpm,
            ele: pos.elevationMetres,
          );
        }
      } catch (e) {
        debugPrint('liveBroadcaster.pushPing failed: $e');
      }

      // L4 — Off-route warning + audio cue. Route math is pure but the
      // audio_cues TTS bridge can throw if the engine hasn't initialised.
      try {
        final off = snapshot.offRouteDistanceMetres;
        if (off != null) {
          if (off > _offRouteThresholdMetres && !_offRouteWarned) {
            _offRouteWarned = true;
            if (widget.preferences.audioCues &&
                widget.preferences.voiceCueEnabled(VoiceCue.offRoute)) {
              _ttsCue('announceOffRoute',
                  () => widget.audioCues.announceOffRoute());
            }
          } else if (off < _offRouteThresholdMetres / 2) {
            _offRouteWarned = false;
          }
        }
      } catch (e) {
        debugPrint('off-route cue failed: $e');
      }

      // L4 — Off-route → auto-notify trusted contact (docs/features/safety.md).
      // Feed the debounced detector; a sustained departure fires ONCE and
      // escalates to confirmed safety contacts via escalate_run_off_route.
      // Pure decision + best-effort RPC; a failure here can't disturb the
      // core stats above.
      try {
        final detector = _offRouteAlertDetector;
        // Deliverability is part of the gate, not a post-hoc check: the
        // detector fires ONCE per run, so letting the sustain clock run
        // while the escalation cannot be delivered (no live broadcast → the
        // contact gets a dead link) spends the latch and leaves the runner
        // with a silently-dead safety net for the rest of the run.
        if (detector != null &&
            !_offRouteAlertFiring &&
            _offRouteEscalationDeliverable) {
          final fired = detector.update(
            snapshot.offRouteDistanceMetres,
            DateTime.now().millisecondsSinceEpoch,
          );
          if (fired) _escalateOffRoute();
        }
      } catch (e) {
        debugPrint('off-route escalation check failed: $e');
      }

      // L4 — Turn-by-turn voice cue. Pure geometry (distanceAlongRoute +
      // the turn-cue announcer) decides which cue to fire; the spoken cue
      // goes through the best-effort _ttsCue wrapper so a TTS failure never
      // disturbs the recording (decisions §169).
      try {
        final announcer = _turnAnnouncer;
        final pos = _routePosition;
        final route = _selectedRoute;
        if (announcer != null &&
            pos != null &&
            route != null &&
            widget.preferences.audioCues &&
            widget.preferences.turnByTurnCues) {
          final along = distanceAlongRoute(
            (lat: pos.lat, lng: pos.lng),
            route.waypoints,
          );
          if (along != null) {
            final a = announcer.announcementFor(along);
            if (a != null) {
              // The runner's real distance to the turn, not the band that
              // triggered the cue — the band is a coarse trigger.
              final distanceStr =
                  a.isNow ? null : UnitFormat.distance(a.aheadM, unit);
              _ttsCue(
                'announceTurn',
                () => widget.audioCues.announceTurn(
                  a.cue.direction,
                  distance: distanceStr,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('turn-cue announce failed: $e');
      }

      // L4 — Pace alert (skip for cycling — pace target doesn't apply).
      // With an active race-strategy phase the phase's derived target pace
      // takes over from the static preference, and the cue speaks
      // the correction amount instead of a bare "speed up".
      try {
        final phaseTarget = _phasePlan.isNotEmpty && _phaseIndex >= 0
            ? phaseTargetPaceSecPerKm(
                _phasePlan[_phaseIndex], _strategyGoalPaceSecPerKm)
            : null;
        final target =
            phaseTarget ?? widget.preferences.targetPaceSecPerKm.toDouble();
        if (!_activityType.usesSpeed &&
            target > 0 &&
            _pace != null &&
            widget.preferences.audioCues &&
            widget.preferences.voiceCueEnabled(VoiceCue.paceAlerts) &&
            !_paceCuesMuted) {
          final diff = _pace! - target;
          final lastAlert = _lastPaceAlertAt;
          final canAlert = lastAlert == null ||
              DateTime.now().difference(lastAlert).inSeconds > 30;
          if (canAlert && diff.abs() > 30) {
            _lastPaceAlertAt = DateTime.now();
            // Round the spoken correction to 5 s so the cue stays terse;
            // sub-5 s residue isn't actionable mid-run.
            final unitFactor = unit == DistanceUnit.mi ? 1.609344 : 1.0;
            final delta = ((diff.abs() * unitFactor) / 5).round() * 5;
            _ttsCue(
                'announcePaceAlert',
                () => widget.audioCues.announcePaceAlert(
                      tooSlow: diff > 0,
                      deltaSecPerUnit: delta > 0 ? delta : null,
                      unit: unit,
                    ));
            // Haptic companion to the TTS so the runner notices even
            // with headphones paused or ambient noise masking the cue.
            // Two-pulse for "speed up", single strong pulse for "slow
            // down" — the direction is distinguishable by feel alone.
            HapticFeedback.heavyImpact();
            if (diff > 0) {
              // The delayed pulse runs on a different stack frame from
              // the surrounding try/catch — without its own guard, a
              // throw here propagates as unhandled and can break the
              // _onSnapshot pipeline (L0/L1 freeze). Each auxiliary
              // effect owns its own try/catch + debugPrint; see
              // docs/architecture/conventions.md § Layered resilience.
              Future<void>.delayed(const Duration(milliseconds: 180), () {
                try {
                  HapticFeedback.heavyImpact();
                } catch (e) {
                  debugPrint('pace-alert second-pulse haptic failed: $e');
                }
              });
            }
          }
        }
      } catch (e) {
        debugPrint('pace-alert cue failed: $e');
      }

      // L4 — Race-strategy phase transition. Phase membership is by
      // recorded distance, not distance-along-route, so it works with or
      // without a followed route. The first announcement waits for 50 m of
      // movement so it doesn't cancel the start cue (a new speak() call
      // interrupts the previous utterance).
      try {
        final phaseDistance = _displayDistanceMetres;
        if (_phasePlan.isNotEmpty && phaseDistance > 50) {
          final idx = phaseAt(_phasePlan, phaseDistance);
          if (idx >= 0 && idx != _phaseIndex) {
            _phaseIndex = idx;
            if (widget.preferences.audioCues &&
                widget.preferences.voiceCueEnabled(VoiceCue.phaseTransitions)) {
              final phase = _phasePlan[idx];
              _ttsCue(
                  'announcePhaseTransition',
                  () => widget.audioCues.announcePhaseTransition(
                        index: idx + 1,
                        total: _phasePlan.length,
                        intent: phase.intent,
                        targetPaceSecPerKm: phaseTargetPaceSecPerKm(
                            phase, _strategyGoalPaceSecPerKm),
                        unit: unit,
                      ));
            }
          }
        }
      } catch (e) {
        debugPrint('phase transition cue failed: $e');
      }

      // L4 — Cutoff catch-up voice cue. When the live projection
      // says the next cutoff is tight or slipping away, speak the distance
      // and the flat pace still sufficient to make it. Only a WORSENING
      // status bypasses the two-minute throttle — margin noise flapping
      // tight↔behind must not re-announce on every flip — and nothing
      // fires while manually paused (the frozen snapshot would repeat the
      // identical warning at an aid-station stop forever). A cutoff whose
      // limit has truly passed (eta.limitPassed, never inferred from a
      // null pace — that also means merely "too close to project") is
      // announced once as unreachable rather than given an impossible
      // pace.
      try {
        if (_cutoffLegs.isNotEmpty &&
            !_manualPaused &&
            widget.preferences.audioCues &&
            widget.preferences.voiceCueEnabled(VoiceCue.cutoffCatchUp)) {
          final stale = _gpsLost || _weakGpsLatest;
          final eta = _cutoffEta(_statsNotifier.value, stale);
          final status = eta?.status;
          if (eta != null &&
              (status == LiveCutoffStatus.tight ||
                  status == LiveCutoffStatus.behind)) {
            int rank(LiveCutoffStatus? s) => switch (s) {
                  LiveCutoffStatus.behind => 2,
                  LiveCutoffStatus.tight => 1,
                  _ => 0,
                };
            final escalated = rank(status) > rank(_lastCutoffCueStatus);
            final lastCue = _lastCutoffCueAt;
            final canCue = lastCue == null ||
                DateTime.now().difference(lastCue).inSeconds > 120;
            if (escalated || canCue) {
              final rp = eta.requiredPaceSecPerKm;
              if (rp != null) {
                _lastCutoffCueAt = DateTime.now();
                _lastCutoffCueStatus = status;
                _ttsCue(
                    'announceCutoffCatchUp',
                    () => widget.audioCues.announceCutoffCatchUp(
                          distanceToM: eta.distanceToM,
                          requiredPaceSecPerKm: rp,
                          unit: unit,
                        ));
              } else if (escalated && eta.limitPassed) {
                _lastCutoffCueAt = DateTime.now();
                _lastCutoffCueStatus = status;
                _ttsCue('announceCutoffUnreachable',
                    () => widget.audioCues.announceCutoffUnreachable());
              }
            }
          } else {
            _lastCutoffCueStatus = status;
          }
        }
      } catch (e) {
        debugPrint('cutoff catch-up cue failed: $e');
      }

      // L4 — Course-marker target cue. Crossing a marker that
      // carries a target time announces ahead/behind-plan. A crossing is
      // the along-route distance moving past position_m between
      // consecutive fixes; announced indices are remembered because GPS
      // jitter can walk the along-value backwards over a marker and would
      // otherwise re-announce it. The baseline advances OUTSIDE the cue
      // toggles: only the announcement is preference-gated, so flipping
      // the cue on mid-run (locally or via a settings-sync pull) can't
      // burst-announce every marker passed while it was off.
      try {
        final route = _selectedRoute;
        final pos = _routePosition;
        if (_targetMarkers.isNotEmpty && route != null && pos != null) {
          final along = distanceAlongRoute(
            (lat: pos.lat, lng: pos.lng),
            route.waypoints,
          );
          if (along != null) {
            final last = _lastAlongM;
            _lastAlongM = along;
            if (last != null &&
                along > last &&
                widget.preferences.audioCues &&
                widget.preferences.voiceCueEnabled(VoiceCue.markerTargets)) {
              for (var i = 0; i < _targetMarkers.length; i++) {
                final m = _targetMarkers[i];
                if (m.positionM > last &&
                    m.positionM <= along &&
                    _announcedTargetMarkers.add(i)) {
                  final deltaS = m.targetS - _elapsed.inSeconds;
                  final label = m.label.isNotEmpty
                      ? m.label
                      : _markerKindLabel(m.kind);
                  _ttsCue(
                      'announceMarkerTarget',
                      () => widget.audioCues.announceMarkerTarget(
                            label: label,
                            deltaS: deltaS,
                          ));
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('marker target cue failed: $e');
      }

      // L4 — Distance tick snackbar + audio cue. Custom interval from
      // preferences overrides the activity-type default.
      try {
        final customInterval = widget.preferences.splitIntervalMetres;
        final tickInterval = customInterval > 0
            ? customInterval.toDouble()
            : _activityType.splitIntervalMetresFor(unit);
        final tickDistance = _displayDistanceMetres;
        final currentTick =
            UnitFormat.activityTicks(tickDistance, tickInterval);
        if (currentTick > _lastTickNotified && currentTick > 0) {
          _lastTickNotified = currentTick;
          final totalDistanceMetres = (currentTick * tickInterval).toDouble();
          final tail = _activityType.usesSpeed
              ? '${UnitFormat.speed(_pace, unit)} ${UnitFormat.speedLabel(unit)}'
              : '${UnitFormat.pace(_pace, unit)} ${UnitFormat.paceLabel(unit)}';
          final splitText = _l10n.runSplitTick(
            UnitFormat.distance(totalDistanceMetres, unit),
            tail,
          );
          _showTopBanner(splitText);
          // Shade twin of the banner (#303): one fixed native id, so
          // each split replaces the previous row instead of stacking,
          // and the row auto-dismisses instead of demanding a swipe.
          _lockScreen.updateSplit(
            title: _activityType.label,
            text: splitText,
          );
          if (widget.preferences.audioCues &&
              widget.preferences.voiceCueEnabled(VoiceCue.splits)) {
            final avgPace =
                averagePaceSecPerKm(tickDistance, _elapsed.inSeconds);
            _ttsCue('announceSplit', () => widget.audioCues.announceSplit(
                  distanceTicks: currentTick,
                  paceSecondsPerKm: _pace,
                  unit: unit,
                  useSpeed: _activityType.usesSpeed,
                  tickIntervalMetres: tickInterval,
                  averagePaceSecondsPerKm: avgPace,
                  paceMode: widget.preferences.splitPaceMode,
                ));
          }
        }
      } catch (e) {
        debugPrint('split tick failed: $e');
      }

      // L4 — Lock-screen notification (Dart client already has its own
      // try/catch, but isolate here too for belt-and-suspenders).
      try {
        _refreshLockScreenNotification();
      } catch (e) {
        debugPrint('lock-screen notification update failed: $e');
      }
  }

  /// Local shim that adapts to the shared `showTopBanner` helper so
  /// internal call sites stay terse. Mounted check is here once so
  /// the call sites don't repeat it.
  void _showTopBanner(
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    showTopBanner(
      context,
      message,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Push the current stats to the native lock-screen notification,
  /// throttled to ~1 Hz so a burst of GPS fixes doesn't spam the
  /// NotificationManager. The native side reposts on geolocator's
  /// channel + id, so this replaces (rather than duplicates) the
  /// "Run in progress" row.
  void _refreshLockScreenNotification() {
    if (_state != _ScreenState.recording) return;
    final now = DateTime.now();
    final last = _lastNotificationAt;
    if (last != null && now.difference(last).inMilliseconds < 900) return;
    _lastNotificationAt = now;

    final unit = widget.preferences.unit;
    final timeStr = _formatDuration(_elapsed);
    // Mirror the on-screen distance (GPS or pedometer-estimated with a
    // tilde prefix) so the lock-screen matches what the user sees.
    final rawDistance = UnitFormat.distance(_displayDistanceMetres, unit);
    final distanceStr =
        _distanceIsEstimated ? '~$rawDistance' : rawDistance;
    final paceStr = _activityType.usesSpeed
        ? '${UnitFormat.speed(_pace, unit)} ${UnitFormat.speedLabel(unit)}'
        : '${UnitFormat.pace(_pace, unit)} ${UnitFormat.paceLabel(unit)}';

    _lockScreen.update(
      title: _manualPaused ? '${_activityType.label} • paused' : _activityType.label,
      text: '$timeStr  •  $distanceStr  •  $paceStr',
      bigText:
          'Time: $timeStr\nDistance: $distanceStr\n${_activityType.usesSpeed ? "Speed" : "Pace"}: $paceStr',
      paused: _manualPaused,
    );
  }

  /// Serialise the in-progress run to disk. Runs every 10s via
  /// [_incrementalSaveTimer] so a crash mid-run is recoverable.
  Future<void> _saveInProgress() async {
    final id = _runId;
    final startedAt = _runStartedAtWall;
    if (id == null || startedAt == null) return;
    if (_state != _ScreenState.recording) return;

    // Mirror the indoor-estimate path in _stop() so a crash-recovered
    // treadmill run keeps its pedometer-based distance instead of being
    // promoted as 0 km.
    final indoorEstimate = !_everHadGpsFix &&
        _distanceMetres == 0 &&
        _displayDistanceMetres > 0;
    final metadata = <String, dynamic>{
      cm.MetadataKeys.activityType: _activityType.name,
      cm.MetadataKeys.inProgressSavedAt: DateTime.now().toIso8601String(),
      if (indoorEstimate) cm.MetadataKeys.indoorEstimated: true,
      if (indoorEstimate) cm.MetadataKeys.distanceSource: 'pedometer',
      if (_steps > 0) cm.MetadataKeys.steps: _steps,
      // The active race strategy, so a crash-recovered run resumes its
      // phases (and the final save keeps the metadata the runner actually
      // executed against).
      if (_strategyPreset != null && _phasePlan.isNotEmpty)
        cm.MetadataKeys.pacingStrategy: <String, dynamic>{
          'preset': _strategyPreset!.wire,
          'distance_m': _resolvedStrategyDistanceM,
          if (_strategyGoalTimeS != null) 'goal_time_s': _strategyGoalTimeS,
        },
    };
    // Persist lap / aid-station marks so a process-kill mid-run can restore
    // them on resume (numbering + cumulative totals continue unbroken). The
    // recorder owns the canonical lap state; mirror it in the same shape
    // `stop()` writes so the loader reads one format.
    final recorderLaps = _recorder?.laps ?? const <LapSplit>[];
    if (recorderLaps.isNotEmpty) {
      metadata[cm.MetadataKeys.laps] = lapsToCanonicalJson(recorderLaps);
    }
    // Workout review trail — written here so a crash mid-workout
    // surfaces the planned-vs-actual table on the recovered run.
    // Empty map when no runner is active or no plan_workout_id is
    // linked. Mirrors the same call in _finishRun. See docs/followups
    // for the 7d "Crash-checkpoint resume for workouts" item.
    final runner = _workoutRunner;
    final activeWorkoutId = _activeWorkoutId ?? widget.initialWorkout?.id;
    metadata.addAll(
      runner?.reviewMetadata(planWorkoutId: activeWorkoutId) ??
          const <String, dynamic>{},
    );
    final run = cm.Run(
      id: id,
      startedAt: startedAt,
      duration: _elapsed,
      distanceMetres:
          indoorEstimate ? _displayDistanceMetres : _distanceMetres,
      track: List.unmodifiable(_track),
      routeId: _selectedRoute?.id,
      source: cm.RunSource.app,
      metadata: metadata,
    );
    try {
      await widget.runStore.saveInProgress(run);
    } catch (e) {
      debugPrint('Incremental save failed: $e');
    }
  }

  /// Update [_gpsLost] based on GPS-backed snapshot freshness. Drives the
  /// warning banner rendered in [_buildRecording]. Only fires once at
  /// least one real GPS fix has arrived — a run that starts without GPS
  /// (indoor / treadmill) shouldn't nag the user about signal loss.
  void _checkGpsHealth() {
    if (_state != _ScreenState.recording) return;
    final last = _lastSnapshotAt;
    // The recorder drops every fix while paused, so the fix age says
    // nothing about the sensor — a paused runner at an aid station has not
    // lost signal.
    final lost = last != null &&
        !_manualPaused &&
        DateTime.now().difference(last) > _gpsLostThreshold;
    // Weak-GPS only matters while the signal is still live; a full GPS-lost
    // state supersedes it (and carries its own, louder banner).
    final weak = _weakGpsLatest && !lost;
    if ((lost != _gpsLost || weak != _weakGps) && mounted) {
      setState(() {
        _gpsLost = lost;
        _weakGps = weak;
      });
    }
  }

  /// Poll location permission so we can surface a banner if the runner
  /// toggles it off in Android settings mid-run. The recorder's position
  /// stream will silently stall otherwise. Skipped for indoor runs that
  /// never had a GPS fix — those users have intentionally denied
  /// permission and don't need a banner reminding them.
  Future<void> _checkPermission() async {
    if (_state != _ScreenState.recording) return;
    try {
      final p = await Geolocator.checkPermission();
      final denied = p == LocationPermission.denied ||
          p == LocationPermission.deniedForever;
      // Only treat denial as "revoked mid-run" if we previously had a fix.
      // A run started in indoor mode stays indoor silently.
      final lost = denied && _lastSnapshotAt != null;
      if (lost != _permissionLost && mounted) {
        setState(() => _permissionLost = lost);
      }
    } catch (e) {
      debugPrint('Permission check failed: $e');
    }
  }

  /// Non-blocking notification that GPS isn't available for this run. The
  /// run still starts — the stopwatch ticks and the map shows its
  /// "Waiting for GPS..." placeholder — so a treadmill / indoor session
  /// still gets recorded. The snackbar carries a Settings shortcut so the
  /// user can enable the missing piece mid-run if they change their mind.
  void _notifyGpsUnavailable(Object? error) {
    debugPrint('RunRecorder.prepare failed: $error');
    if (!mounted) return;

    String message;
    String? actionLabel;
    VoidCallback? onAction;
    if (error is LocationServiceDisabledError) {
      message = _l10n.runGpsNoServiceSettings;
      actionLabel = _l10n.runSettings;
      onAction = () => Geolocator.openLocationSettings();
    } else if (error is LocationPermissionDeniedError) {
      message = error.forever
          ? _l10n.runGpsBlockedSettings
          : _l10n.runGpsPermissionPending;
      actionLabel = _l10n.runSettings;
      onAction = () => Geolocator.openAppSettings();
    } else if (error is LocationPermissionWhileInUseError) {
      message = _l10n.runGpsAllowAllTheTime;
      actionLabel = _l10n.runSettings;
      onAction = () => Geolocator.openAppSettings();
    } else {
      message = _l10n.runGpsSensorFailed;
    }

    // Top-anchored banner instead of a SnackBar so we don't cover the
    // Pause / Stop / Lap buttons in the bottom stats panel.
    _showTopBanner(
      message,
      duration: const Duration(seconds: 6),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Read the user's privacy zones from the synced settings bag. Used
  /// by [LiveBroadcaster] to drop in-zone pings before they leave the
  /// device — without this gate the Go-hub transport leaks the
  /// runner's home/work coordinates to anonymous spectators (the
  /// `live_run_pings_drop_in_zone` trigger only protects the legacy
  /// Supabase path). Returns an empty list when settings aren't
  /// available (signed out, sync not yet wired) — equivalent to "no
  /// zones configured", which is the safe default behaviour.
  List<PrivacyZone> _currentPrivacyZones() {
    final service = widget.settingsSync?.service;
    if (service == null) return const [];
    try {
      final raw = service.effective<List<dynamic>>(
        privacyZonesKey,
        fallback: const <dynamic>[],
      );
      if (raw == null || raw.isEmpty) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(PrivacyZone.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('Privacy zones read failed: $e');
      return const [];
    }
  }

  /// audit/accessibility (2026-05-25) High — WCAG 4.1.3 (Status
  /// Messages). State transitions that a sighted user reads off the
  /// screen (pause / lap / start / finish) are inaudible to a
  /// TalkBack user because the recording surface uses a
  /// `ValueListenable` rather than `setState`, so the screen-reader
  /// announcer never fires automatically. `SemanticsService.announce`
  /// pushes a one-shot live-region message so the cue is screen-
  /// reader compatible (the TTS path in audio_cues.dart is gated on
  /// the user's `audioCues` preference and so cannot satisfy the
  /// status-message contract). Best-effort: a TTS-engine throw must
  /// not break the recording state machine — wrap in try / catch.
  void _announceA11yState(String message) {
    try {
      SemanticsService.announce(message, TextDirection.ltr);
    } catch (e) {
      debugPrint('SemanticsService.announce failed: $e');
    }
  }

  void _toggleManualPause() {
    if (_recorder == null) return;
    if (_manualPaused) {
      _recorder!.resume();
      setState(() => _manualPaused = false);
      _announceA11yState(_l10n.runA11yResumed);
    } else {
      _recorder!.pause();
      setState(() => _manualPaused = true);
      _announceA11yState(_l10n.runA11yPaused);
    }
  }

  void _markLap() {
    if (_recorder == null) return;
    final n = _recorder!.lap();
    if (n > 0) {
      setState(() => _lapCount = n);
      _showTopBanner(_l10n.runLapMarked(n),
          duration: const Duration(seconds: 2));
      _announceA11yState(_l10n.runLapMarked(n));
    }
  }

  Future<void> _stop() async {
    final recorder = _recorder;
    if (_stopRequested || recorder == null) return;
    _stopRequested = true;
    final raw = await recorder.stop();
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _incrementalSaveTimer?.cancel();
    _gpsLostCheckTimer?.cancel();
    _permissionWatchdogTimer?.cancel();
    _lastNotificationAt = null;
    // geolocator's stopForeground(STOP_FOREGROUND_REMOVE) removes the
    // ongoing notification on stream cancel, but clear explicitly so a
    // slow service teardown doesn't leave a stale row on the lock screen.
    _lockScreen.clear();
    WakelockPlus.disable();

    // Tag the run with the chosen activity type + step count so the web
    // and future mobile views can display a consistent summary.
    final metadata = Map<String, dynamic>.from(raw.metadata ?? {});
    metadata[cm.MetadataKeys.activityType] = _activityType.name;
    if (_steps > 0) metadata[cm.MetadataKeys.steps] = _steps;

    // The race-strategy plan this run was executed against, so the
    // detail views can grade the phases later. Registered in
    // docs/backend/metadata.md.
    if (_strategyPreset != null && _phasePlan.isNotEmpty) {
      metadata[cm.MetadataKeys.pacingStrategy] = <String, dynamic>{
        'preset': _strategyPreset!.wire,
        'distance_m': _resolvedStrategyDistanceM,
        if (_strategyGoalTimeS != null) 'goal_time_s': _strategyGoalTimeS,
      };
    }

    // Indoor fallback: if no GPS fix ever arrived but the pedometer ran,
    // save the estimated distance so the run history shows something
    // useful. Flagged in metadata so downstream views can mark it as
    // estimated rather than measured.
    final indoorEstimate = !_everHadGpsFix &&
        raw.distanceMetres == 0 &&
        _displayDistanceMetres > 0;
    if (indoorEstimate) {
      metadata[cm.MetadataKeys.indoorEstimated] = true;
      metadata[cm.MetadataKeys.distanceSource] = 'pedometer';
    }

    // Average heart rate across the run (BLE chest-strap samples).
    if (_bpmSamples.isNotEmpty) {
      metadata[cm.MetadataKeys.avgBpm] = _bpmSamples.reduce((a, b) => a + b) / _bpmSamples.length;
    }
    await _hrSub?.cancel();
    _hrSub = null;
    await _hrStatusSub?.cancel();
    _hrStatusSub = null;
    await _treadmillSub?.cancel();
    _treadmillSub = null;
    await _treadmillStatusSub?.cancel();
    _treadmillStatusSub = null;

    // Structured-workout review trail. Three keys are registered in
    // [docs/backend/metadata.md]: plan_workout_id, workout_step_results,
    // workout_adherence. The web run-detail "Workout" section reads
    // them to render a planned-vs-actual table. _activeWorkoutId
    // covers both the in-app "tap card → load runner" entry and the
    // pass-as-prop entry; metadata is written whenever a runner ran.
    // The same helper runs in _saveInProgress so a crashed mid-workout
    // run keeps its review trail on recovery (decisions §7d / followups).
    final runner = _workoutRunner;
    final activeWorkoutId = _activeWorkoutId ?? widget.initialWorkout?.id;
    metadata.addAll(
      runner?.reviewMetadata(planWorkoutId: activeWorkoutId) ??
          const <String, dynamic>{},
    );

    // Prefer the stable id generated at _begin() over the recorder's
    // stop-time uuid so the saved run matches any incremental in-progress
    // file that may have been written while recording.
    final runId = _runId ?? raw.id;
    var resolvedRouteId = _selectedRoute?.id ?? raw.routeId;
    final api = widget.apiClient;
    final distanceMetres =
        indoorEstimate ? _displayDistanceMetres : raw.distanceMetres;

    // L4 — Auto-link unmatched runs to a saved route. Only when no
    // route was pre-selected, the track has enough points to bother
    // the RPC with, and we're signed in. Network failure here is
    // best-effort; never let it block the save.
    if (resolvedRouteId == null &&
        api != null &&
        api.userId != null &&
        raw.track.length >= 2) {
      try {
        final candidates = await api
            .fetchRoutesIntersectingTrack(raw.track, maxResults: 5)
            .timeout(kBackendLoadTimeout);
        final match = bestStrongRouteMatch(
          candidates,
          runDistanceMetres: distanceMetres,
        );
        if (match != null) resolvedRouteId = match.id;
      } catch (e) {
        debugPrint('Auto-link routes_intersecting_track failed: $e');
      }
    }

    // Persona-hunt Round 2 #4: compute embedded best efforts (per
    // canonical distance) over the GPS track and merge into metadata;
    // the api_client save path lifts them onto the promoted fastest_*_s
    // columns (20270325_001) so the SQL `personal_records` trigger can
    // pick up a sub-20 5k inside an 18 km long run. Helper is null-safe
    // + idempotent + a no-op for tracks under 3 points.
    final enrichedMetadata = enrichMetadataWithEmbeddedBests(
      track: raw.track,
      metadata: metadata,
    );

    final run = cm.Run(
      id: runId,
      startedAt: _runStartedAtWall ?? raw.startedAt,
      duration: raw.duration,
      distanceMetres: distanceMetres,
      track: raw.track,
      routeId: resolvedRouteId,
      source: raw.source,
      externalId: raw.externalId,
      metadata: enrichedMetadata,
      createdAt: raw.createdAt,
    );

    // Persist the run BEFORE clearing the in-progress recovery file, and
    // never gate the save on `mounted` — the recorder is already stopped
    // and the data lives in memory, so a navigation or process kill after
    // this point must not lose it. The two ordering invariants together
    // (save-then-clear, save-not-gated-on-mounted) close the data-loss
    // window that bit a real user in May 2026: clearInProgress() ran
    // first, then setState + an awaited audio cue, then save() — if the
    // OS killed the app during the audio cue, both in_progress.json AND
    // the saved run file were gone, the run was lost forever. If save
    // throws (disk full, isolate crash, plugin failure) we deliberately
    // skip clearInProgress so the next launch promotes the partial via
    // the recovery path in main.dart. Pinned by
    // architecture_guards_test.dart#_stop saves before clearInProgress.
    bool localSaved = false;
    try {
      await widget.runStore.save(run);
      localSaved = true;
    } catch (e) {
      debugPrint('Run save failed: $e');
    }
    if (localSaved) {
      await widget.runStore.clearInProgress();
      // Best-effort write-back to Health Connect (persona #36) when the
      // user opted in. Android-only + fire-and-forget — a HC failure must
      // never touch the save flow or the finish UI.
      if (Platform.isAndroid && widget.preferences.writeToHealthConnect) {
        unawaited(HealthConnectExporter.writeRun(run).catchError((Object e) {
          debugPrint('Health Connect write-back failed: $e');
          return false;
        }));
      }
    }

    if (!mounted) return;
    setState(() {
      _finishedRun = run;
      _setScreenState(_ScreenState.finished);
      if (!localSaved) {
        _syncError = _l10n.runSaveFailedRelaunch;
      }
    });
    _announceA11yState(_l10n.runA11yFinished);

    if (widget.preferences.audioCues &&
        widget.preferences.voiceCueEnabled(VoiceCue.startFinish)) {
      try {
        await widget.audioCues.announceFinish(
          distanceMetres: run.distanceMetres,
          elapsed: run.duration,
          unit: widget.preferences.unit,
        );
      } catch (e) {
        debugPrint('announceFinish failed: $e');
      }
    }

    // If the local save failed, skip the cloud push — local is the
    // source of truth and pushing a row whose authoritative copy isn't
    // on disk would diverge web from mobile until the next reconciliation.
    if (!localSaved) return;

    if (api != null && api.userId != null) {
      try {
        // Honour the user's privacy_default setting. `public` →
        // is_public=true at insert time so the user doesn't have to
        // tap "share" on every run. `followers` / `private` /
        // unknown → leave is_public null (the legacy default; reads
        // as "not public" everywhere). A live broadcast does NOT
        // override this: the live window's public opt-in ends with
        // the run, and keeping the saved run public is an explicit
        // post-stop choice (_resolvePostLiveVisibility, issue #664).
        //
        // `.timeout` so a hung backend (Supabase down, edge function
        // misconfigured) doesn\'t leave the user stuck on the finish
        // summary forever. The run is already saved locally above
        // (line `runStore.save(run)`) and WorkManager will retry the
        // cloud sync on the next periodic schedule.
        await api
            .saveRun(
              run,
              isPublic: widget.preferences.newRunsArePublic ? true : null,
            )
            .timeout(kBackendLoadTimeout);
        await widget.runStore.markSynced(run.id);
        if (mounted) setState(() => _synced = true);
      } catch (e) {
        debugPrint('Auto-sync failed: $e');
        if (mounted) {
          setState(() => _syncError = _l10n.runSyncFailedSaveOffline);
        }
      }
    } else {
      if (mounted) setState(() => _syncError = _l10n.runSavedOffline);
    }

    // Live broadcast wind-down. Two things to do, both best-effort:
    //   1. Stamp runs.concluded_at so the spectator page shows a real
    //      conclusion instead of inferring "finished" from ping absence.
    //      Stamped while the stub is still readable so an open
    //      spectator's ~15s poll can flip to the conclusion card.
    //   2. Detach the broadcaster so a stray late-arriving snapshot
    //      doesn't try to ping a concluded run id.
    // This is the ONLY teardown of the broadcast — navigating away or
    // minimizing keeps it live (the run screen is a keep-alive tab), so a
    // shared link stays valid until the run actually finishes here.
    // The saved run's visibility is resolved separately below
    // (_resolvePostLiveVisibility) — the live window's public opt-in
    // must not silently outlive the run (issue #664).
    final lb = _liveBroadcaster;
    final broadcasterActiveAtStop = lb != null && lb.isActive;
    if (broadcasterActiveAtStop) {
      final api2 = widget.apiClient;
      if (api2 != null && api2.userId != null) {
        try {
          await api2.concludeLiveBroadcast(run.id).timeout(kBackendLoadTimeout);
        } catch (e) {
          debugPrint('concludeLiveBroadcast failed: $e');
        }
      }
      lb.detach();
      _liveShareActive.value = false;
    }

    // If this run was hosting a live race, submit the finisher time so
    // the leaderboard updates without the user having to remember to.
    if (mounted) {
      await widget.raceController?.submitResult(
        runId: run.id,
        durationS: run.duration.inSeconds,
        distanceM: run.distanceMetres,
      );
    }

    await _resolvePostLiveVisibility(
      run.id,
      broadcasterActiveAtStop: broadcasterActiveAtStop,
    );
  }

  /// Post-stop visibility resolution for a run that had a live broadcast
  /// (issue #664). beginLiveBroadcast's stub is is_public=true — the
  /// opt-in to the LIVE window only. Left alone, that flip silently
  /// outlives the run (saveRun's upsert clears it on success, but a
  /// failed cloud save leaves the public stub, and the old stop path
  /// re-asserted it unconditionally), bypassing the deliberate consent
  /// flow run_detail's _confirmMakePublic implements. So: the saved run
  /// follows the runner's default visibility, and keeping it public is
  /// an explicit choice —
  ///   - default already public → nothing to resolve;
  ///   - broadcast still active at stop → AlertDialog: keep public
  ///     (makeRunPublic) or keep private (makeRunPrivate, also the
  ///     dismiss/fail-closed direction);
  ///   - broadcast stopped mid-run → no dialog (the runner already ended
  ///     the share); quietly assert makeRunPrivate so a failed cloud
  ///     save can't leave the stub public.
  /// Auxiliary to the save (L4): the run is already persisted locally,
  /// and a failed flip is disclosed via banner, never rethrown.
  Future<void> _resolvePostLiveVisibility(
    String runId, {
    required bool broadcasterActiveAtStop,
  }) async {
    final api = widget.apiClient;
    final action = postLiveVisibilityActionOnStop(
      broadcastBegun: _liveBroadcastBegun,
      broadcasterActiveAtStop: broadcasterActiveAtStop,
      defaultPublic: widget.preferences.newRunsArePublic,
      signedIn: api != null && api.userId != null,
    );
    _liveBroadcastBegun = false;
    if (action == PostLiveVisibilityAction.none) return;

    var keepPublic = false;
    if (action == PostLiveVisibilityAction.prompt && mounted) {
      keepPublic = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              key: const ValueKey('live-share-keep-public-dialog'),
              title: Text(_l10n.runLiveShareEndedTitle),
              content: Text(_l10n.runLiveShareEndedBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_l10n.runLiveShareKeepPrivate),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(_l10n.runLiveShareKeepPublic),
                ),
              ],
            ),
          ) ??
          false;
    }

    try {
      if (keepPublic) {
        await api!.makeRunPublic(runId).timeout(kBackendLoadTimeout);
      } else {
        await api!.makeRunPrivate(runId).timeout(kBackendLoadTimeout);
      }
    } catch (e) {
      debugPrint('post-live visibility update failed: $e');
      if (mounted) {
        _showTopBanner(keepPublic
            ? _l10n.runDetailMakePublicFailed(friendlyError(_l10n, e))
            : _l10n.runDetailMakePrivateFailed(friendlyError(_l10n, e)));
      }
    }
  }

  Future<void> _confirmDiscardMidRun() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.runDiscardDialogTitle),
        content: Text(_l10n.runDiscardDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.runKeepRunning),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.of(ctx).danger,
              foregroundColor: AppSemanticColors.of(ctx).onDanger,
            ),
            child: Text(_l10n.runDiscard),
          ),
        ],
      ),
    );
    if (ok == true) _discard();
  }

  void _discard() {
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _treadmillSub?.cancel();
    _treadmillSub = null;
    _treadmillStatusSub?.cancel();
    _treadmillStatusSub = null;
    _treadmillMode = false;
    _treadmillSpeedKmh = null;
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _gpsLostCheckTimer?.cancel();
    _permissionWatchdogTimer?.cancel();
    _recorder?.dispose();
    _recorder = null;
    _prepareFuture = null;
    _prepareError = null;
    _stepSamples.clear();
    _lastSnapshotAt = null;
    _startRequested = false;
    _stopRequested = false;
    _runId = null;
    _runStartedAtWall = null;
    // Clear the share intent + indicator so the next run starts private —
    // a sticky flag would silently re-broadcast a fresh run the runner
    // never chose to share.
    _liveShareRequested = false;
    _liveBroadcastBegun = false;
    _liveShareActive.value = false;
    _pedometerRetries = 0;
    _gpsLost = false;
    _weakGps = false;
    _weakGpsLatest = false;
    // Strategy choice survives into the next run; the built plan and the
    // per-recording cue trackers do not.
    _phasePlan = const [];
    _phaseIndex = -1;
    _lastAlongM = null;
    _announcedTargetMarkers.clear();
    _lastCutoffCueAt = null;
    _lastCutoffCueStatus = null;
    _permissionLost = false;
    _everHadGpsFix = false;
    _elevationGain.reset();
    _elevationProcessedCount = 0;
    _statsNotifier.value = _LiveStats.empty;
    // Fire-and-forget — if we discarded mid-run, drop the in-progress file.
    widget.runStore.clearInProgress();
    _lockScreen.clear();
    _lastNotificationAt = null;
    WakelockPlus.disable();
    setState(() {
      _setScreenState(_ScreenState.idle);
      _elapsed = Duration.zero;
      _distanceMetres = 0;
      _pace = null;
      _track = [];
      _currentPosition = null;
      _routePosition = null;
      _lastTickNotified = 0;
      _steps = 0;
      _startSteps = 0;
      _stepBaselineSet = false;
      _stepsCarriedIn = 0;
      _cadence = 0;
      _finishedRun = null;
      _synced = false;
      _syncError = null;
      _manualPaused = false;
      _lapCount = 0;
      _offRouteDistance = null;
      _offRouteWarned = false;
      _offRouteAlertDetector = null;
      _offRouteAlertFiring = false;
      _safetyNudgeVisible = false;
      _routeRemaining = null;
      _lastPaceAlertAt = null;
    });
  }

  @override
  void dispose() {
    // A disposed recording surface is no longer recording, so release the
    // nav-shell swipe lock (issue #490) — leaving it latched would trap the
    // shell in non-swipeable state.
    runRecordingActive.value = false;
    pendingStartWorkout.removeListener(_onPendingStartWorkout);
    widget.preferences.removeListener(_onPrefsChange);
    widget.runStore.removeListener(_onPrefsChange);
    widget.social.removeListener(_onSocialChange);
    widget.training.removeListener(_onTrainingChange);
    _socialDebounce?.cancel();
    _trainingDebounce?.cancel();
    _snapshotSub?.cancel();
    _stepSub?.cancel();
    _countdownTimer?.cancel();
    _incrementalSaveTimer?.cancel();
    _gpsLostCheckTimer?.cancel();
    _permissionWatchdogTimer?.cancel();
    // The strap stream is app-owned, but our subscriptions are not —
    // drop them so a mid-run screen tear-down doesn't leak listeners.
    _hrSub?.cancel();
    _hrStatusSub?.cancel();
    // The belt reader is app-owned (the singleton outlives the screen); only
    // our subscriptions are local — drop them, never disconnect the belt.
    _treadmillSub?.cancel();
    _treadmillStatusSub?.cancel();
    // Active top banner is global (Overlay-backed); dismiss any
    // entry we own so the screen tear-down doesn't leave one stuck.
    hideTopBanner();
    _workoutEventsSub?.cancel();
    _workoutRunner?.dispose();
    _workoutBand.dispose();
    _recorder?.dispose();
    _statsNotifier.dispose();
    _liveShareActive.dispose();
    super.dispose();
  }

  String _strategyLabel(AppLocalizations l10n, RacePhasePreset p) =>
      switch (p) {
        RacePhasePreset.tenTenTen => l10n.runStrategyTenTenTen,
        RacePhasePreset.negativeSplit => l10n.runStrategyNegativeSplit,
        RacePhasePreset.even => l10n.runStrategyEven,
      };

  /// Pre-run race-strategy sheet: pick a phase preset, confirm the
  /// race distance (prefilled from the selected route), optionally set a
  /// goal time so the phases carry target paces.
  Future<void> _editRaceStrategy() async {
    final l10n = _l10n;
    final unit = widget.preferences.unit;
    final isMi = unit == DistanceUnit.mi;
    final resolved = _resolvedStrategyDistanceM;
    final distPrefill = resolved == null
        ? ''
        : (resolved / (isMi ? 1609.344 : 1000)).toStringAsFixed(2);
    final distCtrl = TextEditingController(text: distPrefill);
    final goalCtrl = TextEditingController(text: _strategyGoalText);
    var preset = _strategyPreset;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.runRaceStrategy,
                      style: Theme.of(ctx).textTheme.titleMedium),
                  RadioListTile<RacePhasePreset?>(
                    value: null,
                    groupValue: preset,
                    title: Text(l10n.runStrategyNone),
                    onChanged: (v) => setSheet(() => preset = v),
                  ),
                  RadioListTile<RacePhasePreset?>(
                    value: RacePhasePreset.tenTenTen,
                    groupValue: preset,
                    title: Text(l10n.runStrategyTenTenTen),
                    subtitle: Text(l10n.runStrategyTenTenTenHint),
                    onChanged: (v) => setSheet(() => preset = v),
                  ),
                  RadioListTile<RacePhasePreset?>(
                    value: RacePhasePreset.negativeSplit,
                    groupValue: preset,
                    title: Text(l10n.runStrategyNegativeSplit),
                    subtitle: Text(l10n.runStrategyNegativeSplitHint),
                    onChanged: (v) => setSheet(() => preset = v),
                  ),
                  RadioListTile<RacePhasePreset?>(
                    value: RacePhasePreset.even,
                    groupValue: preset,
                    title: Text(l10n.runStrategyEven),
                    subtitle: Text(l10n.runStrategyEvenHint),
                    onChanged: (v) => setSheet(() => preset = v),
                  ),
                  if (preset != null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: distCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.runStrategyDistance,
                        suffixText: isMi ? 'mi' : 'km',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: goalCtrl,
                      keyboardType: TextInputType.datetime,
                      decoration: InputDecoration(
                        labelText: l10n.runStrategyGoalTime,
                        hintText: 'hh:mm:ss',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child:
                        Text(MaterialLocalizations.of(ctx).okButtonLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (result == true && mounted) {
      final distRaw = distCtrl.text.trim().replaceAll(',', '.');
      final distVal = double.tryParse(distRaw);
      final manualM = distVal != null && distVal > 0
          ? distVal * (isMi ? 1609.344 : 1000.0)
          : null;
      setState(() {
        _strategyPreset = preset;
        // An untouched prefill is NOT a manual override — the plan must
        // keep following the selected route, or switching routes after
        // setting the strategy would build phases from the old route's
        // length.
        _strategyDistanceM =
            distCtrl.text.trim() == distPrefill ? null : manualM;
        _strategyGoalText = goalCtrl.text.trim();
      });
      if (preset != null && _resolvedStrategyDistanceM == null) {
        _showTopBanner(l10n.runStrategyNeedsDistance);
      } else if (_strategyGoalText.isNotEmpty && _strategyGoalTimeS == null) {
        // A non-empty but unparseable goal time was silently dropped —
        // the phase target pace just went missing with no feedback.
        _showTopBanner(l10n.runStrategyInvalidGoal);
      }
    }
    distCtrl.dispose();
    goalCtrl.dispose();
  }

  /// Bottom-sheet picker shown when the user taps today's-workout card.
  /// "Start workout" loads the structured runner inline; "View details"
  /// pushes the existing detail screen.
  Future<void> _showWorkoutEntryChoice(
      PlanWorkoutRow wo, String planId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(_l10n.runStartWorkout),
              subtitle: Text(_l10n.runStartWorkoutSubtitle),
              onTap: () => Navigator.pop(ctx, 'start'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(_l10n.runViewWorkoutDetails),
              onTap: () => Navigator.pop(ctx, 'detail'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'start':
        await _startStructuredWorkout(wo);
      case 'detail':
        // The detail screen pops with the PlanWorkoutRow when the user
        // taps "Start workout" — pick that up and load the runner so
        // the user lands back on the run tab, ready to tap GO.
        final result = await Navigator.of(context).push<PlanWorkoutRow?>(
          MaterialPageRoute<PlanWorkoutRow?>(
            builder: (_) => WorkoutDetailScreen(
              training: widget.training,
              planId: planId,
              workoutId: wo.id,
            ),
          ),
        );
        _refreshPlanOverview();
        if (result != null && mounted) {
          await _startStructuredWorkout(result);
        }
    }
  }

  /// Load a planned workout into the current run-screen state — builds
  /// the [WorkoutRunner], hooks the band, and leaves the user in the
  /// idle screen ready to tap GO. Reused by today's-workout card; safe
  /// to call when no workout is currently set, idempotent if the same
  /// workout is selected twice.
  Future<void> _startStructuredWorkout(PlanWorkoutRow wo) async {
    if (_state != _ScreenState.idle) return;
    Map<String, int> paces = const {};
    try {
      final plan = await widget.training
          .fetchPlanForWorkout(wo)
          .timeout(kBackendLoadTimeout);
      paces = _pacesFromPlan(plan);
    } catch (e) {
      debugPrint('fetchPlanForWorkout failed for ${wo.id}: $e');
    }
    if (!mounted) return;
    final structure = wo.structure is Map<String, dynamic>
        ? wo.structure as Map<String, dynamic>
        : null;
    final steps = expandWorkoutSteps(
      structure: structure,
      paces: paces,
      toleranceSecPerKm: wo.targetPaceToleranceSec ?? 10,
      fallbackDistanceMetres: wo.targetDistanceM,
      fallbackPaceSecPerKm: wo.targetPaceSecPerKm,
    );
    if (steps.isEmpty) {
      if (mounted) {
        showTopBanner(context, _l10n.runWorkoutNoStructure);
      }
      return;
    }
    _workoutEventsSub?.cancel();
    _workoutRunner?.dispose();
    final runner = WorkoutRunner(steps: steps);
    _workoutEventsSub = runner.events.listen(_onWorkoutEvent);
    setState(() {
      _workoutRunner = runner;
      _activeWorkoutId = wo.id;
    });
    _publishWorkoutBand();
    if (mounted) {
      showTopBanner(context, _l10n.runWorkoutLoaded(steps.length));
    }
  }

  void _onSkipWorkoutStep() {
    final r = _workoutRunner;
    if (r == null) return;
    r.skipStep();
    _publishWorkoutBand();
  }

  void _onRewindWorkoutStep() {
    final r = _workoutRunner;
    if (r == null) return;
    if (r.rewindStep()) _publishWorkoutBand();
  }

  void _onAbandonWorkout() async {
    final r = _workoutRunner;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.runAbandonWorkoutTitle),
        content: Text(_l10n.runAbandonWorkoutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.runCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(_l10n.runAbandon),
          ),
        ],
      ),
    );
    if (ok == true) {
      r.abandon();
      _workoutBand.value = WorkoutBandState(
        step: null,
        totalSteps: r.steps.length,
        currentIndex: r.currentStepIndex,
        progress: 0,
        remainingMetres: 0,
        actualPaceSecPerKm: null,
        adherence: PaceAdherence.onPace,
        complete: false,
        abandoned: true,
      );
    }
  }

  // ──────────────── Formatting ────────────────

  DistanceUnit get _unit => widget.preferences.unit;

  String get _formattedTime => _formatDuration(_elapsed);

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Distance the screen displays AND every distance-derived behaviour acts
  /// on — split ticks, split average pace, race-phase transitions. Cycling has
  /// no pedometer so its estimate is zero; there's no meaningful fallback for
  /// that activity.
  double get _displayDistanceMetres => liveDistanceMetres(
        everHadGpsFix: _everHadGpsFix,
        gpsDistanceMetres: _distanceMetres,
        steps: _steps,
        strideMetres: _activityType.strideMetres,
      );

  /// True when [_displayDistanceMetres] is pedometer-estimated rather than
  /// GPS-measured. Drives the tilde prefix and the "estimated" chip so the
  /// user knows the number isn't from GPS.
  bool get _distanceIsEstimated =>
      !_everHadGpsFix && _displayDistanceMetres > 0;

  String get _formattedDistance {
    final base = UnitFormat.distance(_displayDistanceMetres, _unit);
    return _distanceIsEstimated ? '~$base' : base;
  }

  String get _formattedDistanceValue {
    final base = UnitFormat.distanceValue(_displayDistanceMetres, _unit);
    return _distanceIsEstimated ? '~$base' : base;
  }

  String get _formattedPaceValue => UnitFormat.pace(_pace, _unit);

  String get _formattedAvgPaceValue {
    final d = _displayDistanceMetres;
    if (d < 10 || _elapsed.inSeconds < 1) return '--:--';
    final secPerKm = _elapsed.inSeconds / (d / 1000);
    return UnitFormat.pace(secPerKm, _unit);
  }

  /// Average pace computed against a supplied moving time rather than the
  /// full elapsed time. Used on the finished-run screen so the headline
  /// pace excludes stops.
  String _formattedAvgPaceValueFromMoving(Duration movingTime) {
    final d = _displayDistanceMetres;
    if (d < 10 || movingTime.inSeconds < 1) return '--:--';
    final secPerKm = movingTime.inSeconds / (d / 1000);
    return UnitFormat.pace(secPerKm, _unit);
  }

  String get _formattedAvgSpeedValue {
    final d = _displayDistanceMetres;
    if (d < 10 || _elapsed.inSeconds < 1) return '--';
    final secPerKm = _elapsed.inSeconds / (d / 1000);
    return UnitFormat.speed(secPerKm, _unit);
  }

  String get _formattedCalories {
    // Assume 70 kg body weight; multiplier varies by activity. Uses the
    // display distance so indoor runs show non-zero calories from the
    // pedometer estimate rather than always 0.
    final cals =
        (70 * _activityType.kcalPerKgPerKm * _displayDistanceMetres / 1000)
            .round();
    return '$cals';
  }

  String get _formattedElevation => '${_elevationGain.gainMetres.round()}';

  // ──────────────── Build ────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_state) {
        _ScreenState.idle => _buildIdle(context),
        _ScreenState.countdown ||
        _ScreenState.recording ||
        _ScreenState.paused =>
          _buildLive(context),
        _ScreenState.finished => _buildFinished(context),
      },
    );
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    final lastRun = _mostRecentRun();
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Center(
                      child: Wrap(
                        spacing: 8,
                        children: ActivityType.values.map((t) {
                          final selected = t == _activityType;
                          return ChoiceChip(
                            showCheckmark: false,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(t.icon, size: 16),
                                const SizedBox(width: 4),
                                Text(t.label),
                              ],
                            ),
                            selected: selected,
                            onSelected: (_) {
                              if (_state != _ScreenState.idle) return;
                              setState(() => _activityType = t);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _selectRoute,
                            icon: const Icon(Icons.route),
                            label: Text(
                              _selectedRoute == null
                                  ? l10n.runChooseRoute
                                  : l10n.runChangeRoute,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _shareLiveLink,
                            icon: const Icon(Icons.podcasts),
                            label: Text(l10n.runShareLiveLink),
                          ),
                          if (_activityType == ActivityType.run)
                            TextButton.icon(
                              onPressed: _editRaceStrategy,
                              icon: const Icon(Icons.flag_outlined),
                              label: Text(_strategyPreset == null
                                  ? l10n.runRaceStrategy
                                  : _strategyLabel(l10n, _strategyPreset!)),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              final overview = _planOverview;
                              if (overview != null) {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PlanDetailScreen(
                                      training: widget.training,
                                      planId: overview.plan.id,
                                    ),
                                  ),
                                );
                              } else {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PlansScreen(
                                      training: widget.training,
                                      apiClient: widget.apiClient,
                                    ),
                                  ),
                                );
                              }
                              _refreshPlanOverview();
                            },
                            icon: const Icon(Icons.calendar_month),
                            label: Text(_planOverview == null
                                ? l10n.runTrainingPlans
                                : _planOverview!.plan.name),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Priority-card *stack* (previously a pick-one chain).
                    // When the user has multiple signals active — an RSVP
                    // event tomorrow, a plan workout today, and a recent
                    // run — showing them together fills the space that
                    // was sitting empty between the chips and the START
                    // button. If a route is selected for this specific
                    // run, suppress the social/plan cards and show only
                    // the route preview since that's the active context.
                    if (widget.raceController != null)
                      ListenableBuilder(
                        listenable: widget.raceController!,
                        builder: (_, __) {
                          final race = widget.raceController!.active;
                          if (race == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RaceBanner(race: race),
                          );
                        },
                      ),
                    if (_selectedRoute != null)
                      _RoutePreviewCard(route: _selectedRoute!)
                    else ...[
                      if (_upcomingEvent != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: UpcomingEventCard(
                            event: _upcomingEvent!,
                            onTap: () async {
                              final evt = _upcomingEvent!;
                              List<ClubView> clubs = const [];
                              try {
                                clubs = await widget.social
                                    .fetchMyClubs()
                                    .timeout(kBackendLoadTimeout);
                              } catch (e) {
                                debugPrint('fetchMyClubs failed: $e');
                              }
                              final match = clubs
                                  .where((c) => c.row.id == evt.row.clubId)
                                  .toList();
                              if (!mounted) return;
                              final slug = match.isEmpty
                                  ? null
                                  : match.first.row.slug;
                              if (slug == null) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => EventDetailScreen(
                                    social: widget.social,
                                    clubSlug: slug,
                                    eventId: evt.row.id,
                                  ),
                                ),
                              );
                              _refreshUpcomingEvent();
                            },
                          ),
                        ),
                      if (_planOverview?.todayWorkout != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TodaysWorkoutCard(
                            overview: _planOverview!,
                            onTap: () => _showWorkoutEntryChoice(
                              _planOverview!.todayWorkout!,
                              _planOverview!.plan.id,
                            ),
                          ),
                        ),
                      if (lastRun != null)
                        _LastRunCard(
                          run: lastRun,
                          onTap: () => _openLastRun(lastRun),
                        )
                      else if (_upcomingEvent == null &&
                          _planOverview?.todayWorkout == null)
                        _FirstRunPrompt(theme: theme),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  // audit/accessibility (2026-05-25) High — WCAG 1.3.1 +
                  // 4.1.2. The pre-fix tree was a bare GestureDetector
                  // → Container → Text('START'); TalkBack saw a
                  // generic tappable region with no role. Semantics
                  // wraps the whole circle so the button is announced
                  // as a discrete control with a meaningful label.
                  child: Semantics(
                    button: true,
                    label: l10n.runStartA11yLabel,
                    child: GestureDetector(
                      onTap: _beginCountdown,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: semantic.success.withOpacity(0.3),
                            width: 3,
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: semantic.success,
                            boxShadow: [
                              BoxShadow(
                                color: semantic.success.withValues(alpha: 0.25),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          // The circle is a fixed 140 px, so its label is
                          // bounded by the graphic. "START" already fills
                          // 117.5 of the 124 px interior in English at 1.0x —
                          // French "DÉMARRER" and German "STARTEN" were being
                          // broken mid-word, and 2x cropped every locale.
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  l10n.runStart,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: semantic.onSuccess,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  cm.Run? _mostRecentRun() {
    final runs = widget.runStore.runs;
    if (runs.isEmpty) return null;
    final sorted = [...runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.first;
  }

  void _openLastRun(cm.Run run) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(
          run: run,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          apiClient: widget.apiClient,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  Widget _buildLive(BuildContext context) {
    // Unified countdown + recording + paused subtree. Sharing a single
    // LiveRunMap instance across the countdown → recording flip preserves
    // its element identity (and therefore the flutter_map MapController,
    // tile cache attachment, and the interpolated-dot tween state) — the
    // stage transition becomes a chrome swap instead of an unmount-and-
    // remount, which is what produced the brief flash to the map's
    // default backdrop. Mirrors the watch_wear CountdownOverlay
    // (RunWatchApp.kt:264) which solves the same problem by keeping the
    // RouteMiniMap mounted under the digit.
    final isCountdown = _state == _ScreenState.countdown;
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        // Always-mounted map. During countdown stats.currentPosition may
        // be null (no snapshots until the prep stream lands a fix); fall
        // back to _currentPosition so the camera can centre on the most
        // recent fix _preload() captured. The two stay in sync once
        // recording starts (_onSnapshot writes both).
        ValueListenableBuilder<_LiveStats>(
          valueListenable: _statsNotifier,
          builder: (context, stats, _) => LiveRunMap(
            track: stats.track,
            currentPosition: stats.currentPosition ?? _currentPosition,
            plannedRoute: _selectedRoute?.waypoints,
            bottomPadding: isCountdown ? 0 : _statsOverlayHeight,
            activity: isCountdown ? null : _activityType,
            ghostPosition: _computeGhostPosition(),
          ),
        ),

        // Battery-saver dim: darken the bright live map (the dominant
        // draw) while recording, leaving the stats + controls that render
        // in later Stack children at full brightness. IgnorePointer keeps
        // map pan/zoom working through the scrim. Only meaningful with the
        // wakelock holding the screen on (issue #271).
        if (shouldDimRecordingMap(
          isCountdown: isCountdown,
          keepScreenOn: widget.preferences.keepScreenOn,
          dimWhileRecording: widget.preferences.dimScreenWhileRecording,
        ))
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Color(0x99000000)),
            ),
          ),

        // Countdown chrome — scrim + digit + cancel hint, layered on top
        // of the same map. Tap-anywhere cancels and resets to idle.
        if (isCountdown)
          Positioned.fill(
            child: GestureDetector(
              onTap: _discard,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Soft scrim — strong enough that the digit's strokes
                  // don't fight tile contrast, light enough that the map
                  // stays readable around the edges.
                  Container(color: Colors.black.withValues(alpha: 0.45)),
                  Center(
                    // audit/accessibility (May 2026) High — WCAG
                    // 2.3.3. Honour MediaQuery.disableAnimations so
                    // the 350 ms scale + fade collapses to an
                    // instant cut when the OS has reduced-motion on.
                    // AnimatedSwitcher always animates (no
                    // null-duration accepted), so we just feed it
                    // Duration.zero — it still fires the right
                    // build callbacks but skips the transition.
                    child: AnimatedSwitcher(
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween<double>(begin: 1.4, end: 1.0).animate(
                          CurvedAnimation(
                              parent: anim, curve: Curves.easeOutCubic),
                        ),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Text(
                        '$_countdownValue',
                        key: ValueKey(_countdownValue),
                        style: TextStyle(
                          fontSize: 200,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.8),
                              offset: const Offset(0, 2),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // "Tap to cancel" hint — visible for every countdown
                  // tick (the outer `if (isCountdown)` already gates
                  // the whole overlay). Persona-hunt Round 2 finding
                  // Casual #5: pre-fix the hint only rendered while
                  // `_countdownValue == 3` and disappeared at the
                  // 2-second mark, leaving a fat-finger-Start casual
                  // user no idea they could still abort.
                  Positioned(
                      bottom: 48,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Text(
                          l10n.runTapToCancel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // Recording chrome — workout band, route badge, off-route /
        // GPS / permission banners, and the stats panel. All hidden
        // during countdown.
        if (!isCountdown) ...[

        // Every top-anchored overlay in ONE column — see [RunTopOverlay].
        RunTopOverlay(
          // Structured-workout band — only mounts when the run was
          // started from a planned workout. Reads through its own
          // ValueListenable so the band rebuilds on transitions /
          // progress without forcing a Stack-wide rebuild.
          workoutBand: _workoutRunner == null
              ? null
              : WorkoutExecutionBand(
                  state: _workoutBand,
                  onSkip: _onSkipWorkoutStep,
                  onRewind: _onRewindWorkoutStep,
                  onAbandon: _onAbandonWorkout,
                ),
          // Persistent live-share indicator on the left while a
          // broadcast is active (issue #613) — standing confirmation
          // the feed is on, and the only mid-run tap target to
          // re-share the link or stop sharing. "X to go" badge on the
          // right when a route is selected. Each reads its own
          // notifier so it updates at attach/detach or GPS rate
          // without a Stack-wide rebuild.
          badges: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: _liveShareActive,
                      builder: (context, active, _) {
                        if (!active) return const SizedBox.shrink();
                        return LiveShareIndicator(
                            onTap: _onLiveShareIndicatorTap);
                      },
                    ),
                    const Spacer(),
                    ValueListenableBuilder<_LiveStats>(
                      valueListenable: _statsNotifier,
                      builder: (context, stats, _) {
                        final rem = stats.routeRemaining;
                        if (rem == null) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 8),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flag_rounded,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.runRouteRemaining(
                                    UnitFormat.distance(rem, _unit)),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
          banners: ValueListenableBuilder<_LiveStats>(
            valueListenable: _statsNotifier,
            builder: (context, stats, _) {
              final off = stats.offRouteDistance;
              return RunTopBanners(
                offRouteMetres:
                    off != null && off > _offRouteThresholdMetres ? off : null,
                permissionLost: _permissionLost,
                gpsLost: _gpsLost,
                weakGps: _weakGps,
                safetyNudgeVisible: _safetyNudgeVisible,
                onSafetyNudgeShare: _onSafetyNudgeShare,
                onSafetyNudgeDismiss: _dismissSafetyNudge,
              );
            },
          ),
        ),
        // Bottom-anchored utility stack above the stats overlay: the
        // race-strategy phase chip, the next-cutoff card (L4), and the
        // treadmill live-mode toggle compose in one Column so their real
        // heights stack — fixed per-widget offsets overlapped the moment a
        // card grew (a11y text scaling, long labels).
        if (_phasePlan.isNotEmpty || _cutoffLegs.isNotEmpty || _treadmillPaired)
          Positioned(
            left: 12,
            right: 12,
            bottom: _statsOverlayHeight + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current phase + intent (+ the phase's target pace when a
                // goal time was set).
                if (_phasePlan.isNotEmpty)
                  ValueListenableBuilder<_LiveStats>(
                    valueListenable: _statsNotifier,
                    builder: (context, _, _) {
                      final idx = phaseAt(_phasePlan, _displayDistanceMetres);
                      if (idx < 0) return const SizedBox.shrink();
                      final phase = _phasePlan[idx];
                      final target = phaseTargetPaceSecPerKm(
                          phase, _strategyGoalPaceSecPerKm);
                      final prefUnit = widget.preferences.unit;
                      final intent = switch (phase.intent) {
                        RacePhaseIntent.holdBack => l10n.phaseIntentHoldBack,
                        RacePhaseIntent.settle => l10n.phaseIntentSettle,
                        RacePhaseIntent.race => l10n.phaseIntentRace,
                        RacePhaseIntent.even => l10n.phaseIntentEven,
                      };
                      var text =
                          l10n.runPhaseChip(idx + 1, _phasePlan.length, intent);
                      if (target != null) {
                        text =
                            '$text · ${UnitFormat.pace(target, prefUnit)} ${UnitFormat.paceLabel(prefUnit)}';
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Text(text,
                                  style:
                                      Theme.of(context).textTheme.labelLarge),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                // Only when the followed route carries cutoff markers and
                // there's a next cutoff ahead; the ETA refreshes at GPS rate.
                if (_cutoffLegs.isNotEmpty)
                  ValueListenableBuilder<_LiveStats>(
                    valueListenable: _statsNotifier,
                    builder: (context, stats, _) {
                      final stale = _gpsLost || _weakGpsLatest;
                      final eta = _cutoffEta(stats, stale);
                      if (eta == null) return const SizedBox.shrink();
                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: _treadmillPaired ? 8 : 0),
                        child: CutoffCard(eta: eta, stale: stale),
                      );
                    },
                  ),
                // Only when a belt is paired (otherwise it would do nothing;
                // the user is pointed at Settings instead). An L4 opt-in
                // distance-source override.
                if (_treadmillPaired) _buildTreadmillToggle(context, l10n),
              ],
            ),
          ),

        // Top banner is rendered via the Overlay-based `showTopBanner`
        // helper (lib/widgets/top_banner.dart) — no inline pill needed
        // in the recording Stack.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // SizeChangedLayoutNotifier fires precisely when the overlay's
          // size changes (panel expand/collapse). Scheduling the previous
          // post-frame measurement from inside build() fired the callback
          // on every frame of the run — cheap per call, but wasteful given
          // the panel height stabilises immediately and only changes on
          // user interaction.
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: _onOverlaySizeChanged,
            child: SizeChangedLayoutNotifier(
              child: CollapsiblePanel(
                key: _statsOverlayKey,
                // The collapsed bar only shows elapsed time; listen to the
                // notifier so the clock ticks without rebuilding the
                // enclosing Stack.
                collapsedChild: ValueListenableBuilder<_LiveStats>(
                  valueListenable: _statsNotifier,
                  builder: (context, _, __) => _CollapsedStatsBar(
                    time: _formattedTime,
                    onHoldComplete: _stop,
                  ),
                ),
                // Expanded panel reads every stat — wrap once so the whole
                // body rebuilds on each snapshot, but the map, chips, and
                // banners above do not.
                expandedChild: ValueListenableBuilder<_LiveStats>(
                  valueListenable: _statsNotifier,
                  builder: (context, _, __) => _StatsOverlay(
                    time: _formattedTime,
                    distanceValue: _formattedDistanceValue,
                    distanceUnit: UnitFormat.distanceLabel(_unit),
                    primaryValue: _activityType.usesSpeed
                        ? UnitFormat.speed(_pace, _unit)
                        : _formattedPaceValue,
                    primaryUnit: _activityType.usesSpeed
                        ? UnitFormat.speedLabel(_unit)
                        : UnitFormat.paceLabel(_unit),
                    primaryLabel: _activityType.usesSpeed
                        ? l10n.runStatSpeed
                        : l10n.runStatPace,
                    secondaryValue: _activityType.usesSpeed
                        ? _formattedAvgSpeedValue
                        : _formattedAvgPaceValue,
                    secondaryLabel: _activityType.usesSpeed
                        ? l10n.runStatAvgSpeed
                        : l10n.runStatAvgPace,
                    calories: _formattedCalories,
                    elevation: _formattedElevation,
                    steps: '$_steps',
                    cadence: '$_cadence',
                    bpm: _currentBpm,
                    lapCount: _lapCount,
                    paused: _manualPaused,
                    onHoldComplete: _stop,
                    onDiscard: _confirmDiscardMidRun,
                    onPauseToggle: _toggleManualPause,
                    onLap: _markLap,
                    paceCuesActive: !_activityType.usesSpeed &&
                        widget.preferences.audioCues &&
                        widget.preferences.targetPaceSecPerKm > 0,
                    paceCuesMuted: _paceCuesMuted,
                    onTogglePaceMute: () =>
                        setState(() => _paceCuesMuted = !_paceCuesMuted),
                  ),
                ),
              ),
            ),
          ),
        ),
        ],
      ],
    );
  }

  /// Remeasure the stats overlay after the collapsible panel has changed
  /// size. Cheaper than the previous per-frame post-frame callback because
  /// SizeChangedLayoutNotification only dispatches on real layout changes.
  ///
  /// SizeChangedLayoutNotification dispatches synchronously from inside
  /// `_RenderSizeChangedWithCallback.performLayout`, so we're still in the
  /// layout phase when this fires. Calling `setState` directly throws a
  /// "Build scheduled during frame" assertion (and was reproducing during
  /// hold-to-stop on the collapsed bar — the per-tick progress-ring
  /// rebuild triggered a panel relayout). Defer the state change to a
  /// post-frame callback so the rebuild lands cleanly in the next frame.
  bool _onOverlaySizeChanged(SizeChangedLayoutNotification _) {
    final box =
        _statsOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final h = box.size.height;
    if ((h - _statsOverlayHeight).abs() > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _statsOverlayHeight = h);
      });
    }
    return false;
  }

  /// The treadmill live-mode toggle card shown over the recording view.
  /// When on, the subtitle shows the live belt speed (unit-aware); while the
  /// belt is reconnecting it shows an inline hint rather than freezing the
  /// last speed read-out.
  Widget _buildTreadmillToggle(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    String? subtitle;
    if (_treadmillMode) {
      if (_treadmillStatus == BleTreadmillStatus.reconnecting) {
        subtitle = l10n.runTreadmillLostReconnecting;
      } else if (_treadmillSpeedKmh != null) {
        final kmh = _treadmillSpeedKmh!;
        final value = _unit == DistanceUnit.mi ? kmh / 1.609344 : kmh;
        final speed =
            '${formatFixed(value, 1, activeLocaleTag)} ${UnitFormat.speedLabel(_unit)}';
        subtitle = l10n.runTreadmillModeSpeed(speed);
      }
    }
    return Card(
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      margin: EdgeInsets.zero,
      child: SwitchListTile(
        dense: true,
        secondary: const Icon(Icons.directions_run_outlined),
        title: Text(l10n.runTreadmillModeLabel),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: _treadmillMode,
        onChanged: (on) => _toggleTreadmillMode(on),
      ),
    );
  }

  Widget _buildFinished(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final track = _finishedRun?.track ?? <cm.Waypoint>[];
    // Derived metric: "moving time" — elapsed with stops excluded, computed
    // from the GPS track. Replaces the old live auto-pause.
    final movingTime = movingTimeOf(track);

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: LiveRunMap(track: track, followRunner: false),
        ),
        Expanded(
          flex: 4,
          child: FinishedSummary(
            distanceValue: _formattedDistance,
            timeValue: _formattedTime,
            movingValue: _formatDuration(movingTime),
            primaryLabel: _activityType.usesSpeed
                ? l10n.runStatAvgSpeed
                : l10n.runStatPace,
            primaryValue: _activityType.usesSpeed
                ? _formattedAvgSpeedValue
                : _formattedAvgPaceValueFromMoving(movingTime),
            primaryUnit: _activityType.usesSpeed
                ? UnitFormat.speedLabel(_unit)
                : UnitFormat.paceLabel(_unit),
            synced: _synced,
            syncError: _syncError,
            onDone: _discard,
          ),
        ),
      ],
    );
  }
}

/// The stats pane of the finished-run summary — everything below the map.
/// A fixed-height centered Column clipped the sync status + Done button at
/// large OS text scaling (~2x on a compact-height phone), so the pane uses
/// the same scroll fallback as `_buildIdle`: content that fits stays
/// vertically centered, content that doesn't scrolls.
class FinishedSummary extends StatelessWidget {
  const FinishedSummary({
    super.key,
    required this.distanceValue,
    required this.timeValue,
    required this.movingValue,
    required this.primaryLabel,
    required this.primaryValue,
    required this.primaryUnit,
    required this.synced,
    required this.syncError,
    required this.onDone,
  });

  final String distanceValue;
  final String timeValue;
  final String movingValue;
  final String primaryLabel;
  final String primaryValue;
  final String primaryUnit;
  final bool synced;
  final String? syncError;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: clampDouble(
                  constraints.maxHeight - 48, 0, double.maxFinite),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(l10n.runComplete, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: StatColumn(
                          label: l10n.runStatDistance, value: distanceValue),
                    ),
                    Expanded(
                      child: StatColumn(
                          label: l10n.runStatTime, value: timeValue),
                    ),
                    Expanded(
                      child: StatColumn(
                          label: l10n.runStatMoving, value: movingValue),
                    ),
                    Expanded(
                      child: StatColumn(
                        label: primaryLabel,
                        value: primaryValue,
                        unit: primaryUnit,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (synced) ...[
                  Icon(Icons.cloud_done, color: semantic.success, size: 36),
                  const SizedBox(height: 4),
                  Text(l10n.runSynced),
                ] else if (syncError != null) ...[
                  Icon(Icons.cloud_off, size: 36, color: semantic.warning),
                  const SizedBox(height: 4),
                  Text(syncError!,
                      style: TextStyle(
                          color: semantic.warning, fontSize: 13)),
                ] else ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.runSyncing),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: onDone, child: Text(l10n.runDone)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass stats bar overlaid on the map during recording.
class _StatsOverlay extends StatelessWidget {
  final String time;
  final String distanceValue;
  final String distanceUnit;
  final String primaryValue;
  final String primaryUnit;
  final String primaryLabel;
  final String secondaryValue;
  final String secondaryLabel;
  final String calories;
  final String elevation;
  final String steps;
  final String cadence;
  final int? bpm;
  final int lapCount;
  final bool paused;
  final VoidCallback onHoldComplete;
  final VoidCallback onDiscard;
  final VoidCallback onPauseToggle;
  final VoidCallback onLap;
  /// Pace-cue mute toggle — only shown when pace cues can actually fire
  /// (a pace target is set and audio cues are on). Lets a runner on a
  /// social group run silence the pace nagging for this session only,
  /// without touching their saved audio-cue preference (round-5 social-group).
  final bool paceCuesActive;
  final bool paceCuesMuted;
  final VoidCallback? onTogglePaceMute;

  const _StatsOverlay({
    required this.time,
    required this.distanceValue,
    required this.distanceUnit,
    required this.primaryValue,
    required this.primaryUnit,
    required this.primaryLabel,
    required this.secondaryValue,
    required this.secondaryLabel,
    required this.calories,
    required this.elevation,
    required this.steps,
    required this.cadence,
    required this.bpm,
    required this.lapCount,
    required this.paused,
    required this.onHoldComplete,
    required this.onDiscard,
    required this.onPauseToggle,
    required this.onLap,
    this.paceCuesActive = false,
    this.paceCuesMuted = false,
    this.onTogglePaceMute,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: theme.textTheme.displayMedium?.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
                children: [
                  Expanded(
                      child: StatColumn(
                          label: l10n.runStatDistance, value: distanceValue, unit: distanceUnit)),
                  _divider(theme),
                  Expanded(
                      child: StatColumn(
                          label: primaryLabel, value: primaryValue, unit: primaryUnit)),
                  _divider(theme),
                  Expanded(
                      child: StatColumn(
                          label: secondaryLabel, value: secondaryValue, unit: primaryUnit)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: StatColumn(label: l10n.runStatCalories, value: calories, unit: l10n.runUnitKcal)),
                  _divider(theme),
                  Expanded(child: StatColumn(label: l10n.runStatElevation, value: elevation, unit: l10n.runUnitMetres)),
                  _divider(theme),
                  Expanded(child: StatColumn(label: l10n.runStatSteps, value: steps)),
                  _divider(theme),
                  Expanded(child: StatColumn(label: l10n.runStatCadence, value: cadence, unit: l10n.runUnitSpm)),
                ],
              ),
              // Heart rate row — only renders when a BLE chest strap is
              // paired AND has produced at least one sample. Null-on-null
              // keeps the overlay the same height as before for runners
              // without a strap.
              if (bpm != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatColumn(
                        label: l10n.runStatHeartRate,
                        value: '$bpm',
                        unit: l10n.runUnitBpm,
                      ),
                    ),
                  ],
                ),
              ],
              if (paceCuesActive) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onTogglePaceMute,
                  icon: Icon(
                    paceCuesMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 18,
                  ),
                  label: Text(
                    paceCuesMuted ? l10n.runPaceCuesMuted : l10n.runMutePaceCues,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Discard button.
                  // audit/accessibility (May 2026) Critical: the bare
                  // GestureDetector + Container + Icon shape gave
                  // TalkBack no name or role — a screen-reader user
                  // couldn't end the run from this control.
                  // Semantics(button: true, label:) is the Flutter idiom.
                  Semantics(
                    button: true,
                    enabled: true,
                    label: l10n.runDiscardA11yLabel,
                    hint: l10n.runDiscardA11yHint,
                    child: GestureDetector(
                      onTap: onDiscard,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceContainerHighest,
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          size: 26,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Pause / Resume.
                  // audit/accessibility (May 2026) Critical — see
                  // above. Toggle label reflects current state.
                  Semantics(
                    button: true,
                    enabled: true,
                    toggled: paused,
                    label: paused ? l10n.runResumeA11yLabel : l10n.runPauseA11yLabel,
                    hint: paused
                        ? l10n.runResumeA11yHint
                        : l10n.runPauseA11yHint,
                    child: GestureDetector(
                      onTap: onPauseToggle,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: paused ? semantic.success : semantic.warning,
                        ),
                        child: Center(
                          child: Icon(
                            paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                            size: 32,
                            color: paused
                                ? semantic.onSuccess
                                : semantic.onWarning,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Stop button — hold-to-stop, 800ms. Prevents accidental
                  // one-tap stops mid-run.
                  HoldToStopButton(
                    onHoldComplete: onHoldComplete,
                  ),
                  const SizedBox(width: 16),
                  // Lap button.
                  // audit/accessibility (May 2026) Critical — same fix
                  // pattern. Lap count is announced so a screen-reader
                  // user knows how many laps the gesture produced.
                  Semantics(
                    button: true,
                    enabled: true,
                    label: lapCount > 0
                        ? l10n.runMarkLapWithCountA11yLabel(lapCount)
                        : l10n.runMarkLapA11yLabel,
                    hint: l10n.runMarkLapA11yHint,
                    child: GestureDetector(
                      onTap: onLap,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primaryContainer,
                        ),
                        child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 28,
                            color: theme.colorScheme.primary,
                          ),
                          if (lapCount > 0)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: semantic.danger,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 14,
                                  minHeight: 14,
                                ),
                                child: Text(
                                  '$lapCount',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: semantic.onDanger,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) {
    return Container(width: 1, height: 28, color: theme.dividerColor);
  }
}

@visibleForTesting
class StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  const StatColumn(
      {super.key, required this.label, required this.value, this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // A wide value (a multi-hour elapsed time, a 4-digit ultra
        // distance, a long localized unit) must shrink to fit its column
        // rather than paint an overflow stripe — the finished summary packs
        // four of these into one Row and the live overlay three, so the
        // available width per column is small on a narrow phone.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StepSample {
  final DateTime time;
  final int steps;
  const _StepSample(this.time, this.steps);
}

/// Immutable per-snapshot bundle fed through `_statsNotifier`. Wrapping
/// this in a `ValueNotifier` + `ValueListenableBuilder` lets the hot-path
/// subtrees rebuild without forcing a `setState` that would rebuild the
/// entire recording screen at 1 Hz minimum. Only the subtrees that
/// actually display these values listen; banners driven by other fields
/// (`_gpsLost`, `_permissionLost`) continue to rebuild through their
/// usual `setState` path.
class _TargetMarker {
  final double positionM;
  final String kind;
  final String label;
  final int targetS;

  const _TargetMarker({
    required this.positionM,
    required this.kind,
    required this.label,
    required this.targetS,
  });
}

/// The conditional banners over the top of the live map — off-route, the
/// permission / GPS status chain, and the solo-safety nudge — composed in
/// one Column so any combination stacks vertically instead of overlapping
/// (issue #666 V10; the bottom-anchored utility stack got the same
/// treatment first). Public so the composition is widget-testable without
/// pumping the whole run screen.
/// Every top-anchored recording overlay, composed into ONE `Positioned`
/// column so their real heights stack.
///
/// Fixed per-widget offsets overlapped the moment two showed at once: the
/// off-route and GPS-lost banners were both pinned to `top: 60` and the
/// centred cards crossed the `top: 56` badges (issue #666 V10), and the
/// workout band — anchored separately at the status-bar inset — sat on top of
/// the badge row whenever a run was started from a planned workout. Adding a
/// new top overlay means adding a slot here, not another `Positioned`.
///
/// [Positioned] is returned rather than wrapped around this widget so the
/// single anchor lives with the composition; it still applies to the host
/// [Stack] because parent-data widgets walk up to the nearest render object.
class RunTopOverlay extends StatelessWidget {
  const RunTopOverlay({
    super.key,
    this.workoutBand,
    required this.badges,
    required this.banners,
  });

  /// The structured-workout band, or null when no workout is armed.
  final WorkoutExecutionBand? workoutBand;

  /// The live-share indicator + route-remaining badge row.
  final Widget badges;

  /// The conditional banner stack ([RunTopBanners]).
  final Widget banners;

  /// Clearance from the top of the screen. The column carries the whole top
  /// band now, so it takes the larger of this and the device's status-bar
  /// inset — the band used to anchor on the inset itself and must not end up
  /// under a tall cutout.
  static const topInset = 56.0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: math.max(topInset, MediaQuery.of(context).padding.top),
      left: 12,
      right: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workoutBand != null) workoutBand!,
          badges,
          const SizedBox(height: 4),
          banners,
        ],
      ),
    );
  }
}

class RunTopBanners extends StatelessWidget {
  const RunTopBanners({
    super.key,
    required this.offRouteMetres,
    required this.permissionLost,
    required this.gpsLost,
    required this.weakGps,
    required this.safetyNudgeVisible,
    required this.onSafetyNudgeShare,
    required this.onSafetyNudgeDismiss,
  });

  /// Metres off the planned route, already gated on the alert threshold by
  /// the caller; null hides the banner.
  final double? offRouteMetres;
  final bool permissionLost;
  final bool gpsLost;
  final bool weakGps;
  final bool safetyNudgeVisible;
  final VoidCallback onSafetyNudgeShare;
  final VoidCallback onSafetyNudgeDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final semantic = AppSemanticColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Off-route banner — independent of the status chain below, so
        // both can show at once and stack.
        if (offRouteMetres != null)
          Center(
            child: Card(
              color: semantic.danger,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  l10n.runOffRoute(offRouteMetres!.round()),
                  style: TextStyle(
                      color: semantic.onDanger, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        if (permissionLost)
          Center(
            child: Card(
              color: semantic.danger,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off,
                        color: semantic.onDanger, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      l10n.runPermissionRevoked,
                      style: TextStyle(
                          color: semantic.onDanger,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (gpsLost)
          Center(
            child: Card(
              color: semantic.danger,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gps_off, color: semantic.onDanger, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      l10n.runGpsLost,
                      style: TextStyle(
                          color: semantic.onDanger,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (weakGps)
          Center(
            child: Card(
              color: semantic.warning,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.gps_not_fixed,
                        color: semantic.onWarning, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      l10n.runWeakGps,
                      style: TextStyle(
                          color: semantic.onWarning,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Solo-run safety nudge — a persistent, dismissible action card
        // (not a 6-second toast) so an after-dark solo runner can't miss
        // it. Acting on it (Share / Not now) stamps the throttle; merely
        // showing it does not.
        if (safetyNudgeVisible)
          SafetyNudgeBanner(
            onShare: onSafetyNudgeShare,
            onDismiss: onSafetyNudgeDismiss,
          ),
      ],
    );
  }
}

class _LiveStats {
  final Duration elapsed;
  final double distanceMetres;
  final double? pace;
  final List<cm.Waypoint> track;
  final cm.Waypoint? currentPosition;

  /// Last fix the recorder ACCEPTED — the only position route-relative math
  /// may use. [currentPosition] can be a rejected teleport.
  final cm.Waypoint? routePosition;
  final double? offRouteDistance;
  final double? routeRemaining;

  const _LiveStats({
    required this.elapsed,
    required this.distanceMetres,
    required this.pace,
    required this.track,
    required this.currentPosition,
    required this.routePosition,
    required this.offRouteDistance,
    required this.routeRemaining,
  });

  static const _LiveStats empty = _LiveStats(
    elapsed: Duration.zero,
    distanceMetres: 0,
    pace: null,
    track: [],
    currentPosition: null,
    routePosition: null,
    offRouteDistance: null,
    routeRemaining: null,
  );
}

/// Minimal stats bar shown when the overlay is collapsed. Keeps time visible
/// plus a hold-to-stop button so the runner can still abort without
/// expanding first.
class _CollapsedStatsBar extends StatelessWidget {
  final String time;
  final VoidCallback onHoldComplete;

  const _CollapsedStatsBar({
    required this.time,
    required this.onHoldComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              time,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          HoldToStopButton(
            size: 48,
            iconSize: 24,
            showHint: false,
            onHoldComplete: onHoldComplete,
          ),
        ],
      ),
    );
  }
}

/// Big red stop button that must be *held* for [holdDuration] before the run
/// is actually stopped. The circular progress ring grows during the hold so
/// the user gets clear visual feedback, and (when [showHint]) a "hold to stop"
/// caption tells the user the control needs a press-and-hold, not a tap.
/// Cancels cleanly on release.
@visibleForTesting
class HoldToStopButton extends StatefulWidget {
  static const holdDuration = Duration(milliseconds: 800);

  final VoidCallback onHoldComplete;
  final double size;
  final double iconSize;
  final bool showHint;

  const HoldToStopButton({
    super.key,
    required this.onHoldComplete,
    this.size = 68,
    this.iconSize = 36,
    this.showHint = true,
  });

  @override
  State<HoldToStopButton> createState() => _HoldToStopButtonState();
}

/// Owns the 60 Hz progress ticker locally so the surrounding run screen
/// (map, stats panel, banners) doesn't rebuild at 60 Hz during a hold.
/// Only this ~68 px button rebuilds while the user holds the stop.
class _HoldToStopButtonState extends State<HoldToStopButton>
    with TickerProviderStateMixin {
  Ticker? _ticker;
  Duration _holdStart = Duration.zero;
  double _progress = 0;

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onPointerDown() {
    _ticker?.dispose();
    _holdStart = Duration.zero;
    _ticker = createTicker((elapsed) {
      if (_holdStart == Duration.zero) _holdStart = elapsed;
      final held = elapsed - _holdStart;
      final p = (held.inMilliseconds / HoldToStopButton.holdDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      if (p != _progress && mounted) setState(() => _progress = p);
      if (p >= 1.0) {
        _ticker?.dispose();
        _ticker = null;
        if (mounted) setState(() => _progress = 0);
        widget.onHoldComplete();
      }
    })
      ..start();
  }

  void _onPointerUpOrCancel() {
    _ticker?.dispose();
    _ticker = null;
    if (_progress != 0 && mounted) setState(() => _progress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final semantic = AppSemanticColors.of(context);
    final l10n = AppLocalizations.of(context);
    // The hold gesture is a sighted-user accidental-stop guard built on
    // raw Listener pointer events — a screen-reader user navigates by
    // element + double-tap-to-activate and can't perform a sustained
    // hold, so without an explicit Semantics(onTap) the stop control is
    // unreachable for them. The Semantics gives it a name + role and
    // routes the activate gesture straight to onHoldComplete;
    // ExcludeSemantics drops the bare Container/Icon below so the node
    // has no competing child semantics.
    final button = Semantics(
      button: true,
      enabled: true,
      label: l10n.runStopA11yLabel,
      hint: l10n.runStopA11yHint,
      onTap: widget.onHoldComplete,
      child: ExcludeSemantics(
        // `behavior: HitTestBehavior.opaque` so the Listener claims any
        // touch inside its 48–68 px square outright, instead of the default
        // `deferToChild` which delegates to whichever child happens to be
        // opaque at that pixel. The visible Container only claims hits
        // within its painted circle, so a tap inside the square but
        // outside the circle (corners + the ring overlay during a hold)
        // would otherwise pass straight through to whatever sat behind
        // — most visibly inside the AnimatedCrossFade-driven collapsed
        // stats bar where the button is at the smaller 48 px size and
        // the corner gap is proportionally bigger.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _onPointerDown(),
          onPointerUp: (_) => _onPointerUpOrCancel(),
          onPointerCancel: (_) => _onPointerUpOrCancel(),
          child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: semantic.danger,
                boxShadow: [
                  BoxShadow(
                    color: semantic.danger.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Icon(Icons.stop_rounded,
                    size: widget.iconSize, color: semantic.onDanger),
              ),
            ),
            if (_progress > 0)
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 4,
                  color: Colors.white,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
          ),
        ),
      ),
    );

    if (!widget.showHint) return button;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Text(
            l10n.runHoldToStopHint,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

String _formatAgo(BuildContext context, DateTime when) {
  final l10n = AppLocalizations.of(context);
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 60) {
    return diff.inMinutes <= 1
        ? l10n.runAgoJustNow
        : l10n.runAgoMinutes(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.runAgoHours(diff.inHours);
  }
  if (diff.inDays == 1) return l10n.runAgoYesterday;
  if (diff.inDays < 7) return l10n.runAgoDays(diff.inDays);
  if (diff.inDays < 30) {
    final weeks = (diff.inDays / 7).floor();
    return l10n.runAgoWeeks(weeks);
  }
  final months = (diff.inDays / 30).floor();
  return l10n.runAgoMonths(months);
}

/// Whether the run-start wiring should (re)attach the live broadcast: either
/// the device auto-live-share pref is on, or the runner manually asked to share
/// this run's link — unless a broadcast is already active. The manual-request
/// arm is what stops a shared link from staying dead when the pre-GO begin
/// failed transiently and auto-live-share is off (persona-woman safety fix).
@visibleForTesting
bool shouldStartBroadcastOnRunStart({
  required bool autoLiveShareEnabled,
  required bool liveShareRequested,
  required bool broadcasterActive,
}) =>
    (autoLiveShareEnabled || liveShareRequested) && !broadcasterActive;

/// What the stop path owes the saved run's visibility after a live share
/// (issue #664). The live window's is_public=true opt-in ends with the run:
/// never a silent permanent public flip.
enum PostLiveVisibilityAction {
  /// Nothing to resolve — no broadcast was begun, signed out, or the
  /// runner's default is already public (the save honoured it).
  none,

  /// The broadcast was live at stop: ask, and only an explicit choice
  /// keeps the run public.
  prompt,

  /// The runner already ended the share mid-run: no dialog, quietly
  /// assert the not-public default (covers the failed-cloud-save stub).
  revertToDefault,
}

@visibleForTesting
PostLiveVisibilityAction postLiveVisibilityActionOnStop({
  required bool broadcastBegun,
  required bool broadcasterActiveAtStop,
  required bool defaultPublic,
  required bool signedIn,
}) {
  if (!broadcastBegun || !signedIn) return PostLiveVisibilityAction.none;
  if (defaultPublic) return PostLiveVisibilityAction.none;
  return broadcasterActiveAtStop
      ? PostLiveVisibilityAction.prompt
      : PostLiveVisibilityAction.revertToDefault;
}

String _formatKm(double metres) =>
    formatFixed(metres / 1000, 2, activeLocaleTag);

String _formatPace(Duration duration, double metres) {
  if (metres < 10) return '--:--';
  final secondsPerKm = duration.inSeconds / (metres / 1000);
  return UnitFormat.pace(secondsPerKm, DistanceUnit.km);
}

class _LastRunCard extends StatelessWidget {
  final cm.Run run;
  final VoidCallback onTap;
  const _LastRunCard({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.runLastRunOpenA11yLabel,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                if (run.track.length >= 2)
                  SizedBox(
                    width: 72,
                    height: 56,
                    child: CustomPaint(
                      painter: _TrackSparkPainter(
                        track: run.track,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 72,
                    height: 56,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.directions_run,
                      color: theme.colorScheme.primary.withOpacity(0.6),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        run.distanceMetres < 50
                            ? l10n.runLastActivity
                            : l10n.runLastRun,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatAgo(context, run.startedAt),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _metricPill(
                            theme,
                            '${_formatKm(run.distanceMetres)} km',
                          ),
                          const SizedBox(width: 6),
                          _metricPill(
                            theme,
                            '${_formatPace(run.duration, run.distanceMetres)} /km',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricPill(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Idle-state banner that surfaces a live race. Armed → tells the user
/// to get ready; running → shows elapsed since the server's start and a
/// prompt to tap Start.
class _RaceBanner extends StatefulWidget {
  final ActiveRace race;
  const _RaceBanner({required this.race});

  @override
  State<_RaceBanner> createState() => _RaceBannerState();
}

class _RaceBannerState extends State<_RaceBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.race.isRunning) {
      _tick = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) { if (mounted) setState(() {}); },
      );
    }
  }

  @override
  void didUpdateWidget(covariant _RaceBanner old) {
    super.didUpdateWidget(old);
    if (!old.race.isRunning && widget.race.isRunning) {
      _tick = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) { if (mounted) setState(() {}); },
      );
    } else if (old.race.isRunning && !widget.race.isRunning) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final race = widget.race;
    final isRunning = race.isRunning && race.startedAt != null;
    final elapsed = isRunning
        ? DateTime.now().difference(race.startedAt!).inSeconds
        : 0;
    final label = race.eventTitle ?? l10n.runRaceFallbackTitle;
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        border: Border.all(color: primary, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            race.isArmed ? Icons.sports_score : Icons.directions_run,
            color: primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  race.isArmed ? l10n.runRaceArmed : l10n.runRaceLive,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  race.isArmed
                      ? l10n.runRaceWaitingForGo(label)
                      : l10n.runRaceElapsedTapStart(label, _fmt(elapsed)),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

class _RoutePreviewCard extends StatelessWidget {
  final cm.Route route;
  const _RoutePreviewCard({required this.route});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            height: 56,
            child: route.waypoints.length >= 2
                ? CustomPaint(
                    painter: _TrackSparkPainter(
                      track: route.waypoints,
                      color: theme.colorScheme.secondary,
                    ),
                  )
                : Icon(Icons.route, color: theme.colorScheme.secondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.runFollowing,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  route.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.straighten,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatKm(route.distanceMetres)} km',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (route.elevationGainMetres > 0) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.terrain,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${route.elevationGainMetres.round()} m',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstRunPrompt extends StatelessWidget {
  final ThemeData theme;
  const _FirstRunPrompt({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.rocket_launch, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppLocalizations.of(context).runFirstRunPrompt,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scales a waypoint list to fit a small rect and paints a rounded polyline.
/// Cheap — used for last-run and route-preview cards on the Run tab idle view.
///
/// Projection is delegated to `projectTrack`, the same helper the routes-list
/// thumbnails use, so the finish card and the routes list draw one shape for
/// one run. Its own copy scaled latitude and longitude by the same factor,
/// which stretched a square loop 1.61× too wide at 51.5 °N and exactly 2×
/// at 60 °N — the distortion `decisions.md § 51` exists to prevent.
class _TrackSparkPainter extends CustomPainter {
  final List<cm.Waypoint> track;
  final Color color;

  _TrackSparkPainter({required this.track, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (track.length < 2 || size.width <= 0 || size.height <= 0) return;
    final projected = projectTrack(track, size.width, size.height, pad: 4);
    if (projected.length < 2) return;

    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (int i = 1; i < projected.length; i++) {
      path.lineTo(projected[i].dx, projected[i].dy);
    }

    final bg = Paint()
      ..color = color.withOpacity(0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(10),
      ),
      bg,
    );

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _TrackSparkPainter old) =>
      old.track != track || old.color != color;
}

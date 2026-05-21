import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'social_service.dart';

/// Tracks live race sessions for events the user has RSVP'd to and is
/// therefore likely participating in. When the organiser arms a race, the
/// run screen surfaces a "Race armed — waiting for GO" banner. When the
/// session flips to `running`, clients hosting a recorder tag the
/// resulting run with `event_id` and push pings while it's in progress.
///
/// This is deliberately a lightweight notifier rather than a full state
/// machine — the existing `RunRecorder` state machine in run_screen is
/// complex enough already. When the race flips to running the user still
/// taps Start manually for v1 (the recorder already handles permissions
/// + countdown correctly); auto-start from the remote signal is a
/// follow-up that needs permission-flow plumbing.
class ActiveRace {
  final String eventId;
  final DateTime instanceStart;
  final String status; // armed | running | finished | cancelled
  final DateTime? startedAt;
  final String? eventTitle;

  const ActiveRace({
    required this.eventId,
    required this.instanceStart,
    required this.status,
    required this.startedAt,
    required this.eventTitle,
  });

  bool get isArmed => status == 'armed';
  bool get isRunning => status == 'running';
}

class RaceController extends ChangeNotifier {
  RaceController(this._social);

  final SocialService _social;
  SupabaseClient get _c {
    if (!ApiClient.isInitialized) {
      throw StateError(
        'RaceController called before Supabase.initialize() resolved.',
      );
    }
    return Supabase.instance.client;
  }

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  Timer? _pingTimer;

  ActiveRace? _active;
  ActiveRace? get active => _active;

  /// Set by the run screen while a run that's been stamped with a race
  /// is in progress. The controller polls for the session's status
  /// changing to `finished/cancelled` and posts pings until then.
  String? _hostingEventId;
  DateTime? _hostingInstance;

  /// Attach the controller to a user session. Starts polling for armed
  /// sessions on events the user has RSVP'd to. Idempotent.
  Future<void> start() async {
    if (_pollTimer != null) return;
    await _refresh();
    // Realtime on race_sessions handles the live case (any change fires
    // a refresh). The 60 s timer is a watchdog for when the channel
    // silently disconnects — short enough to recover quickly, long
    // enough not to duplicate the realtime path. Was 15 s; that did 4×
    // the round-trips for no functional gain.
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    // Realtime on race_sessions — the server-published filter scopes to
    // all rows; we narrow in-client against the user's RSVPed events
    // because Postgres-level filtering by a join is awkward. For a v1
    // this is fine: a user is in at most a handful of upcoming races.
    _channel = _c
        .channel('race-controller-${_c.auth.currentUser?.id ?? 'anon'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'race_sessions',
          callback: (_) => _refresh(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pingTimer?.cancel();
    final ch = _channel;
    if (ch != null) _c.removeChannel(ch);
    super.dispose();
  }

  Future<void> _refresh() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) {
      if (_active != null) {
        _active = null;
        notifyListeners();
      }
      return;
    }
    // Events the user is `going` to within the next 24h (window for
    // live races). Keeps the fetch small for a single user.
    final now = DateTime.now().toUtc();
    final horizon = now.add(const Duration(hours: 24));
    final past = now.subtract(const Duration(hours: 6));
    try {
      final rsvps = await _c
          .from('event_attendees')
          .select('event_id, instance_start, status')
          .eq('user_id', uid)
          .eq('status', 'going')
          .gte('instance_start', past.toIso8601String())
          .lte('instance_start', horizon.toIso8601String());
      final list = (rsvps as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) { _setActive(null); return; }

      // Check each for an armed/running race session. In practice a user
      // has 1-3 upcoming RSVPs at most, but firing the per-RSVP fetches
      // in parallel via Future.wait means we get done in the wall time
      // of the slowest one rather than the sum of all of them.
      final sessionResults = await Future.wait(list.map((r) async {
        final eventId = r['event_id'] as String;
        final inst = DateTime.parse(r['instance_start'] as String);
        final res = await _c
            .from('race_sessions')
            .select('status, started_at')
            .eq('event_id', eventId)
            .eq('instance_start', inst.toIso8601String())
            .inFilter('status', ['armed', 'running'])
            .maybeSingle();
        return (eventId: eventId, inst: inst, row: res);
      }));

      ActiveRace? next;
      for (final s in sessionResults) {
        final res = s.row;
        if (res == null) continue;
        final title = await _eventTitle(s.eventId);
        next = ActiveRace(
          eventId: s.eventId,
          instanceStart: s.inst,
          status: res['status'] as String,
          startedAt: res['started_at'] == null
              ? null
              : DateTime.parse(res['started_at'] as String),
          eventTitle: title,
        );
        // Prefer running over armed if we somehow see both.
        if (next.isRunning) break;
      }
      _setActive(next);
    } catch (e) {
      debugPrint('[RaceController._refresh] $e');
    }
  }

  // LinkedHashMap-style cache with a simple LRU cap. Was unbounded —
  // a user attending many events over an app session would accumulate
  // titles indefinitely.
  static const _titleCacheMax = 32;
  final Map<String, String?> _titleCache = <String, String?>{};
  Future<String?> _eventTitle(String eventId) async {
    if (_titleCache.containsKey(eventId)) {
      // Bump to most-recent by re-inserting.
      final v = _titleCache.remove(eventId);
      _titleCache[eventId] = v;
      return v;
    }
    final row = await _c
        .from('events')
        .select('title')
        .eq('id', eventId)
        .maybeSingle();
    final title = (row as Map?)?['title'] as String?;
    _titleCache[eventId] = title;
    if (_titleCache.length > _titleCacheMax) {
      _titleCache.remove(_titleCache.keys.first);
    }
    return title;
  }

  /// Visible-for-testing — RaceControllerTest exercises the change-
  /// detection directly without a live Supabase. Keeps the test
  /// honest about which fields are part of an ActiveRace's
  /// observed-by-listeners identity.
  @visibleForTesting
  void setActiveForTest(ActiveRace? next) => _setActive(next);

  void _setActive(ActiveRace? next) {
    // instanceStart is part of an ActiveRace's identity — Instance 1
    // of recurring event E is a DIFFERENT race from Instance 2 of E
    // (different start time, different RSVP row, different
    // race_sessions PK). Omitting it from change-detection let a
    // back-to-back armed transition (Instance 1 finishes → Instance
    // 2 armed; same eventId, same 'armed' status, both null
    // startedAt) silently update `_active` without firing
    // notifyListeners, leaving the banner rendering Instance 1's
    // time until something else triggered a rebuild.
    final changed = next?.eventId != _active?.eventId ||
        next?.instanceStart != _active?.instanceStart ||
        next?.status != _active?.status ||
        next?.startedAt != _active?.startedAt;
    _active = next;
    if (changed) notifyListeners();
  }

  /// Called by the run screen when it starts a recorder while a race is
  /// running. Enables live pings at a 10s cadence.
  void attachRecorder({
    required String eventId,
    required DateTime instance,
  }) {
    _hostingEventId = eventId;
    _hostingInstance = instance;
  }

  void detachRecorder() {
    _hostingEventId = null;
    _hostingInstance = null;
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Fire once per GPS sample the recorder produces while a race is
  /// running. Posts a ping at most every 10s — more than that would
  /// spam `race_pings` and the spectator map.
  DateTime _lastPingAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> pushPing({
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
  }) async {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    if (eid == null || inst == null) return;
    final now = DateTime.now();
    if (now.difference(_lastPingAt) < const Duration(seconds: 10)) return;
    _lastPingAt = now;
    try {
      await _c.from('race_pings').insert({
        'event_id': eid,
        'instance_start': inst.toIso8601String(),
        'user_id': _c.auth.currentUser?.id,
        'lat': lat,
        'lng': lng,
        if (distanceM != null) 'distance_m': distanceM,
        if (elapsedS != null) 'elapsed_s': elapsedS,
        if (bpm != null) 'bpm': bpm,
      });
    } catch (e) {
      debugPrint('[RaceController.pushPing] $e');
    }
  }

  /// Submit an event result tied to the currently hosted race, then
  /// detach. Called by the run screen once the recorder finishes.
  Future<void> submitResult({
    required String runId,
    required int durationS,
    required double distanceM,
  }) async {
    final eid = _hostingEventId;
    final inst = _hostingInstance;
    if (eid == null || inst == null) return;
    try {
      await _social.submitEventResult(
        eventId: eid,
        instance: inst,
        durationS: durationS,
        distanceM: distanceM,
        runId: runId,
        finisherStatus: 'finished',
      );
    } catch (e) {
      debugPrint('[RaceController.submitResult] $e');
    }
    detachRecorder();
  }
}

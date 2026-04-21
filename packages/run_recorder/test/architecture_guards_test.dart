// Guard-rail tests for the RunRecorder efficiency invariants. Each test
// explains why the rule exists so a future editor knows whether it's safe
// to break. When one fails, read the reason before rubber-stamping a fix.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _extractMethodBody(String source, String signaturePattern) {
  final match = RegExp(signaturePattern).firstMatch(source);
  if (match == null) {
    fail('Could not find "$signaturePattern" — update the guard.');
  }
  final start = match.end;
  int depth = 1;
  int i = start;
  while (depth > 0 && i < source.length) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') depth--;
    i++;
  }
  return source.substring(start, i - 1);
}

void main() {
  late String source;
  setUpAll(() {
    source = File('lib/src/run_recorder.dart').readAsStringSync();
  });

  test('_emitSnapshot reuses the shared track view', () {
    // Reason: List.unmodifiable(_track) allocated a new wrapper on every
    // emit (1 Hz minimum). Replaced by a single UnmodifiableListView
    // stored as `_trackView` — same wrapper across every snapshot. If
    // someone goes back to List.unmodifiable, the allocation comes back.
    final body = _extractMethodBody(
      source,
      r'void _emitSnapshot\(\)\s*\{',
    );
    expect(
      body.contains('List.unmodifiable(_track)'),
      isFalse,
      reason: '_emitSnapshot must pass the shared _trackView, '
          'not allocate a fresh unmodifiable list per emit.',
    );
    expect(
      body,
      contains('track: _trackView'),
      reason: '_emitSnapshot must hand out the shared _trackView.',
    );
  });

  test('_emitSnapshot caches route math by current waypoint identity', () {
    // Reason: the 1-second timer can fire without a new GPS fix (indoor
    // mode, warmup, stationary runner). Re-running the full-route
    // segment projection each tick is wasteful — the cache short-circuits
    // when _currentWaypoint hasn't changed.
    final body = _extractMethodBody(
      source,
      r'void _emitSnapshot\(\)\s*\{',
    );
    expect(
      body,
      contains('identical(current, _lastRouteCalcFor)'),
      reason: '_emitSnapshot must skip route math when _currentWaypoint '
          'hasn\'t changed (identity check against _lastRouteCalcFor).',
    );
  });

  test('1-second timer emits regardless of GPS fix availability', () {
    // Reason: the stopwatch has to keep advancing for indoor / treadmill
    // runs where `_currentWaypoint` stays null. Gating the timer on
    // `_currentWaypoint != null` would freeze the clock for those runs.
    final beginBody = _extractMethodBody(
      source,
      r'void begin\(\)\s*\{',
    );
    expect(
      beginBody.contains('_currentWaypoint == null'),
      isFalse,
      reason: 'begin()\'s periodic timer must not gate snapshot emission '
          'on _currentWaypoint — indoor runs depend on null-position '
          'snapshots firing every second.',
    );
  });

  test('prepare throws typed errors, not a generic Exception', () {
    // Reason: callers (run_screen) branch on LocationServiceDisabledError
    // vs LocationPermissionDeniedError to pick the right snackbar message
    // (Settings shortcut for services vs app-settings for permission).
    // A generic Exception loses that information.
    expect(
      source,
      contains('throw LocationServiceDisabledError()'),
      reason: 'prepare() must throw LocationServiceDisabledError when '
          'isLocationServiceEnabled() is false — the run_screen snackbar '
          'branches on this type.',
    );
    expect(
      source,
      contains('throw LocationPermissionDeniedError'),
      reason: 'prepare() must throw LocationPermissionDeniedError on '
          'denied permission — the run_screen snackbar branches on this.',
    );
  });

  test('prepare flips _prepared before the GPS checks', () {
    // Reason: indoor runs require begin() to work even when GPS is
    // unavailable. If _prepared is only set after the checks succeed,
    // a failed prepare throws out the whole run.
    final body = _extractMethodBody(
      source,
      r'Future<void> prepare\(\{[^)]*\}\)\s*async\s*\{',
    );
    final preparedIdx = body.indexOf('_prepared = true');
    final serviceCheckIdx = body.indexOf('isLocationServiceEnabled');
    expect(preparedIdx, greaterThan(-1),
        reason: 'prepare() must set _prepared = true somewhere.');
    expect(serviceCheckIdx, greaterThan(-1),
        reason: 'prepare() must call isLocationServiceEnabled.');
    expect(
      preparedIdx < serviceCheckIdx,
      isTrue,
      reason: '_prepared must be flipped BEFORE the service/permission '
          'checks so begin() works in indoor mode even if prepare throws.',
    );
  });

  test('GPS retry loop exists and is cancelled on stop/dispose', () {
    // Reason: the retry loop is what reopens the stream after a
    // mid-run Location toggle. If it's not started in prepare or not
    // stopped in stop/dispose, we get a leaked timer or a dead run.
    expect(source, contains('_gpsRetryTimer'));
    expect(source, contains('_startGpsRetryLoop'));
    final stopBody = _extractMethodBody(
      source,
      r'Future<Run> stop\(\)\s*async\s*\{',
    );
    expect(
      stopBody,
      contains('_gpsRetryTimer?.cancel()'),
      reason: 'stop() must cancel the GPS retry timer.',
    );
    final disposeBody = _extractMethodBody(
      source,
      r'void dispose\(\)\s*\{',
    );
    expect(
      disposeBody,
      contains('_gpsRetryTimer?.cancel()'),
      reason: 'dispose() must cancel the GPS retry timer.',
    );
  });

  test('RunSnapshot.currentPosition is nullable', () {
    // Reason: the 1-second timer emits without a GPS fix. A non-nullable
    // currentPosition would force callers to invent a sentinel.
    final snapshotSource =
        File('lib/src/run_snapshot.dart').readAsStringSync();
    expect(
      snapshotSource,
      contains('Waypoint? currentPosition'),
      reason: 'RunSnapshot.currentPosition must be nullable so indoor / '
          'warmup snapshots can carry a null.',
    );
  });
}

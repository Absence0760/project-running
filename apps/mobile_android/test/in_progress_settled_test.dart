// The in-progress recording path is off the store's write chain by design, so
// `debugWritesSettled()` cannot see it — and both of its drivers discard the
// future (a `Timer.periodic` tick, and a bare `clearInProgress()` in
// `run_screen._discard`). That left a real file write under the store's own
// directory with NO observable completion, the shape decisions § 991 closed one
// layer up: a widget test's `tearDown` deletes the directory while the append
// is still in the air. decisions § 1012.

import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';

Run _run(int points) => Run(
      id: 'in-progress-run',
      startedAt: DateTime.utc(2026, 6, 1, 6),
      duration: const Duration(minutes: 5),
      distanceMetres: 800,
      source: RunSource.app,
      track: [
        for (var i = 0; i < points; i++)
          Waypoint(
            lat: 51.5 + i * 0.0001,
            lng: -0.12 + i * 0.0001,
            timestamp: DateTime.utc(2026, 6, 1, 6, 0, i),
          ),
      ],
    );

void main() {
  late Directory dir;
  late LocalRunStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('in-progress-settled');
    store = LocalRunStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() async {
    // The point of the whole file: a teardown that races the write it is
    // deleting under is the § 723 failure. Wait on the path's own signal.
    await store.debugInProgressSettled();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('the signal covers an append the caller discarded', () async {
    // Exactly what the Timer.periodic tick does: no await, no handle.
    store.saveInProgress(_run(50));
    await store.debugInProgressSettled();
    expect(
      File('${dir.path}/in_progress.json').existsSync(),
      isTrue,
      reason: 'the append had not landed when the signal said it was quiet',
    );
  });

  test('the signal covers a clear the caller discarded', () async {
    store.saveInProgress(_run(20));
    await store.debugInProgressSettled();
    // Exactly what `run_screen._discard` does: a bare statement in a `void`
    // method, so the future is dropped at the call site.
    store.clearInProgress();
    await store.debugInProgressSettled();
    expect(
      File('${dir.path}/in_progress.json').existsSync(),
      isFalse,
      reason: 'the delete had not landed when the signal said it was quiet',
    );
  });

  test('the signal returns immediately when the path is quiet', () async {
    await store.debugInProgressSettled();
    await store.debugInProgressSettled();
  });

  test('the recording path is still OFF the serialised write chain', () {
    // The signal must not be bought by joining the two. `_chainKey`'s own
    // comment forbids it: nothing on the chain may delay an L1 write during a
    // recording. Asserted in source rather than by timing, because a race that
    // happens to resolve in the right order proves nothing either way.
    final src = File('lib/local_run_store.dart').readAsStringSync();
    String body(String signature) {
      final at = src.indexOf(signature);
      expect(at, greaterThan(-1), reason: '$signature moved — re-anchor this');
      var depth = 0;
      for (var i = src.indexOf('{', at); i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) return src.substring(at, i);
        }
      }
      return src.substring(at);
    }

    expect(body('Future<void> saveInProgress(').contains('_serialised'), isFalse,
        reason: 'the recording append joined the chain');
    // A clear issued while an append is in flight settles only if its own
    // future was published. Asserted here rather than by timing: the delete
    // that follows lands within a turn or two either way on a fast disk, so a
    // behavioural test passes whether or not the future was recorded — it was
    // measured doing exactly that before this assertion replaced it.
    expect(body('Future<void> clearInProgress(').contains('_inFlightClear'),
        isTrue,
        reason: 'clearInProgress no longer publishes its future, so a clear '
            'the caller discarded is invisible to debugInProgressSettled');
    expect(body('Future<void> _clearInProgress(').contains('_serialised'),
        isFalse,
        reason: 'the recording clear joined the chain');
    expect(
      body('Future<void> debugInProgressSettled(')
          .contains('storeWritesSettled'),
      isFalse,
      reason: 'the two signals were joined, which puts the recording path on '
          'the chain by the back door',
    );
  });
}

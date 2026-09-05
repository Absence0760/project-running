import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_until.dart';

/// Whether a store write that outlives the current test is this test's subject
/// rather than its defect. Reset for every test by [installStoreWriteWatch].
bool _outlivingWritesExpected = false;

final _InFlightWrites _inFlight = _InFlightWrites();

/// Declare that this test deliberately ends with an operation still on the
/// write chain, and why.
///
/// The only honest use is a test whose SUBJECT is an unsettleable write — the
/// zone precondition of `storeWritesSettled` cannot be pinned without queueing
/// one from a zone nothing will drain. It is not an escape hatch for a screen
/// test that taps and does not wait: that test's write is racing the temp
/// directory its own `tearDown` deletes, which is the defect this watch exists
/// to name.
void allowStoreWritesToOutliveTest(String why) {
  assert(why.isNotEmpty);
  _outlivingWritesExpected = true;
}

/// What the watch has to say about the operations still on the write chain,
/// or null if there are none to answer for.
///
/// Reading CLEARS the record: the harness asks once per test, and a test that
/// left a write open must not make every test after it fail for a write it did
/// not start. A test may ask first to assert on the answer itself.
String? takeStoreWriteWatchVerdict() => _inFlight.take();

/// Pump until every operation the write chain has open has finished.
///
/// The wait a widget test needs after a tap — or a `pumpWidget` of a screen
/// that inits its own stores — when the store is the screen's and offers no
/// signal of its own to watch: the chain being empty IS the observable
/// outcome. Bounded and loud like every other [pumpUntil], never a fixed delay.
Future<void> pumpUntilStoreWritesSettle(WidgetTester tester) => pumpUntil(
      tester,
      () => !_inFlight.anyOpen,
      describe: 'every queued store write to finish',
    );

/// Wire the write chain's two test-only instruments for every test in this
/// suite. Called once from `flutter_test_config.dart`.
void installStoreWriteWatch() {
  debugStoreWritesSettledSink = (error, callSite) {
    debugPrint('$error\n\nasked for at:\n$callSite');
  };
  debugStoreWriteObserver = _inFlight;
  setUp(() {
    _outlivingWritesExpected = false;
    _inFlight.take();
  });
  tearDown(() {
    final verdict = takeStoreWriteWatchVerdict();
    if (verdict != null) fail(verdict);
  });
}

class _QueuedWrite {
  _QueuedWrite(this.key, this.queuedAt);

  final String key;
  final StackTrace queuedAt;
}

class _InFlightWrites implements StoreWriteObserver {
  final Map<int, _QueuedWrite> _open = <int, _QueuedWrite>{};

  @override
  void onQueued(int id, String key, StackTrace queuedAt) {
    _open[id] = _QueuedWrite(key, queuedAt);
  }

  @override
  void onSettled(int id) {
    _open.remove(id);
  }

  bool get anyOpen => _open.isNotEmpty;

  String? take() {
    if (_open.isEmpty) return null;
    final open = _open.values.toList();
    _open.clear();
    if (_outlivingWritesExpected) return null;
    final where = open
        .map((w) => '  ${w.key}\n${w.queuedAt.toString().trimRight()}')
        .join('\n\n');
    return '${open.length} store write(s) were still in flight when this test '
        'ended, so the file I/O they started is racing the temp directory the '
        'teardown is about to delete. Wait for the write: an observable '
        'outcome via pumpUntil, or the store\'s own debugWritesSettled from '
        'inside tester.runAsync. See decisions.md § 1093 and § 1097.\n\n'
        'Queued at:\n$where';
  }
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/undo_queue.dart';

/// Mirror of web `core/undo_queue.test.ts` — same 14 cases, same order.
/// Deterministic clock + timer pair: `advance` fires every timer whose
/// deadline has passed, in deadline order, so a re-armed timer created
/// mid-advance still lands correctly.
class _Harness {
  _Harness([this.windowMs = 8000]);

  int windowMs;
  int _clock = 0;
  int _nextHandle = 1;
  final Map<int, _FakeTimer> _timers = {};
  final List<PendingUndo?> published = [];
  late final UndoQueue queue;

  _Harness init() {
    queue = UndoQueue(UndoQueueDeps(
      windowMs: () => windowMs,
      setTimer: (cb, ms) {
        final handle = _nextHandle++;
        _timers[handle] = _FakeTimer(_clock + ms, cb);
        return handle;
      },
      clearTimer: (handle) => _timers.remove(handle as int),
      now: () => _clock,
      onChange: published.add,
    ));
    return this;
  }

  int get armedTimers => _timers.length;

  /// Moves the clock without letting any timer fire — a long "hover"
  /// that must consume none of a paused window.
  void tick(int ms) => _clock += ms;

  Future<void> advance(int ms) async {
    final target = _clock + ms;
    for (;;) {
      int? dueHandle;
      _FakeTimer? due;
      _timers.forEach((handle, timer) {
        if (timer.at <= target && (due == null || timer.at < due!.at)) {
          dueHandle = handle;
          due = timer;
        }
      });
      if (due == null) break;
      _clock = due!.at;
      _timers.remove(dueHandle);
      due!.cb();
      // Let the awaited commit() inside flush() settle.
      await Future<void>.value();
      await Future<void>.value();
    }
    _clock = target;
  }
}

class _FakeTimer {
  _FakeTimer(this.at, this.cb);
  final int at;
  final void Function() cb;
}

class _Spy {
  int count = 0;
  final List<Object> args = [];
  void call() => count++;
  void withArg(Object a) {
    count++;
    args.add(a);
  }
}

void main() {
  // -------------------------------------------------------------------------
  // The central contract: nothing is destroyed while undo is on offer
  // -------------------------------------------------------------------------

  test('defer holds the mutation — commit has not run when the bar appears',
      () {
    final h = _Harness().init();
    final commit = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: () {},
    ));
    expect(commit.count, 0);
    expect(h.queue.hasPending(), true);
    final last = h.published.last!;
    expect(last.id, 1);
    expect(last.message, 'Removed');
    expect(last.windowMs, 8000);
    expect(last.paused, false);
  });

  test('undo cancels the pending mutation entirely — commit never runs, '
      'restore does', () {
    final h = _Harness().init();
    final commit = _Spy();
    final restore = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: restore.call,
    ));
    h.queue.undo();
    expect(commit.count, 0);
    expect(restore.count, 1);
    expect(h.queue.hasPending(), false);
    expect(h.published.last, isNull);
    expect(h.armedTimers, 0);
  });

  test('the window elapsing commits, and does NOT restore', () async {
    final h = _Harness().init();
    final commit = _Spy();
    final restore = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: restore.call,
    ));
    await h.advance(7999);
    expect(commit.count, 0);
    await h.advance(1);
    expect(commit.count, 1);
    expect(restore.count, 0);
    expect(h.queue.hasPending(), false);
  });

  test('a failed commit restores the caller state and reports the error',
      () async {
    final h = _Harness().init();
    final restore = _Spy();
    final onCommitError = _Spy();
    final boom = StateError('23503');
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => throw boom,
      restore: restore.call,
      onCommitError: onCommitError.withArg,
    ));
    await h.advance(8000);
    expect(restore.count, 1);
    expect(onCommitError.args, [boom]);
  });

  // -------------------------------------------------------------------------
  // One slot
  // -------------------------------------------------------------------------

  test('a second destruction commits the first immediately and takes the slot',
      () async {
    final h = _Harness().init();
    final firstCommit = _Spy();
    final secondCommit = _Spy();
    final firstRestore = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'One',
      commit: () async => firstCommit.call(),
      restore: firstRestore.call,
    ));
    h.queue.defer(DeferredDestruction(
      message: 'Two',
      commit: () async => secondCommit.call(),
      restore: () {},
    ));
    await Future<void>.value();
    expect(firstCommit.count, 1, reason: 'the displaced entry commits');
    expect(firstRestore.count, 0,
        reason: 'and is not restored — the user did not undo it');
    expect(secondCommit.count, 0);
    expect(h.published.last!.message, 'Two');
    expect(h.armedTimers, 1, reason: 'the displaced timer was disarmed');
  });

  test('undo after the window closed is a no-op — a stale tap cannot '
      'double-fire', () async {
    final h = _Harness().init();
    final commit = _Spy();
    final restore = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: restore.call,
    ));
    await h.advance(8000);
    h.queue.undo();
    expect(commit.count, 1);
    expect(restore.count, 0,
        reason: 'the row is genuinely gone — undo must not claim otherwise');
  });

  test('flush is idempotent and a no-op with nothing pending', () async {
    final h = _Harness().init();
    final commit = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: () {},
    ));
    await h.queue.flush();
    await h.queue.flush();
    expect(commit.count, 1);
  });

  // -------------------------------------------------------------------------
  // WCAG 2.2.1 — pause while the window is not the user's to spend, and
  // turn the limit off
  // -------------------------------------------------------------------------

  test('pause disarms the timer; resume re-arms with only the remaining time',
      () async {
    final h = _Harness().init();
    final commit = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: () {},
    ));
    await h.advance(3000);
    h.queue.pause();
    expect(h.armedTimers, 0);
    expect(h.published.last!.paused, true);

    // A long interruption must not consume any of the window.
    h.tick(60000);
    expect(commit.count, 0);

    h.queue.resume();
    expect(h.published.last!.paused, false);
    await h.advance(4999);
    expect(commit.count, 0, reason: '5 s of the 8 s window remained');
    await h.advance(1);
    expect(commit.count, 1);
  });

  test('pause/resume keep the published id and windowMs stable so the bar '
      'animation does not restart', () async {
    final h = _Harness().init();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async {},
      restore: () {},
    ));
    await h.advance(2000);
    h.queue.pause();
    h.queue.resume();
    final ids = h.published.whereType<PendingUndo>().map((p) => p.id).toList();
    expect(ids, [1, 1, 1]);
    for (final p in h.published) {
      if (p != null) expect(p.windowMs, 8000);
    }
  });

  test('a zero window arms no timer at all — the limit is off until dismiss '
      'or undo', () async {
    final h = _Harness(0).init();
    final commit = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: () {},
    ));
    expect(h.armedTimers, 0);
    expect(h.published.last!.windowMs, 0);
    await h.advance(10 * 60000);
    expect(commit.count, 0, reason: 'ten minutes later it is still undoable');
    await h.queue.flush();
    expect(commit.count, 1);
  });

  test('pause and resume are inert when there is no time limit to pause', () {
    final h = _Harness(0).init();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async {},
      restore: () {},
    ));
    h.queue.pause();
    h.queue.resume();
    expect(h.published.last!.paused, false);
  });

  test('a negative window is clamped to no-limit rather than firing instantly',
      () {
    final h = _Harness(-5000).init();
    final commit = _Spy();
    h.queue.defer(DeferredDestruction(
      message: 'Removed',
      commit: () async => commit.call(),
      restore: () {},
    ));
    expect(h.armedTimers, 0);
    expect(commit.count, 0);
  });

  // -------------------------------------------------------------------------
  // undoWindowSFromPref — the stored preference
  // -------------------------------------------------------------------------

  test('undoWindowSFromPref: every offered choice round-trips', () {
    for (final choice in kUndoWindowChoicesS) {
      expect(undoWindowSFromPref(choice), choice);
    }
  });

  test('undoWindowSFromPref: absent or corrupt values fall back to the '
      'default, never to no-limit', () {
    final corrupt = <Object?>[
      null,
      '8',
      '',
      <String, Object?>{},
      <Object?>[],
      double.nan,
      double.infinity,
      7,
      -1,
      3600,
      8.5,
      true,
    ];
    for (final raw in corrupt) {
      expect(undoWindowSFromPref(raw), kDefaultUndoWindowS,
          reason: 'raw = $raw');
    }
  });
}

import 'dart:async';

/// Deferred-commit undo — the widget-free core of the mobile app's undo
/// contract, and the Dart twin of web `core/undo_queue.ts`.
///
/// Three contracts were on the table and only one of them can be honest
/// for the actions we adopt it on:
///
///   1. A compensating inverse (re-insert what was deleted) mints a NEW
///      server id, and anything the original row owned — cascaded
///      replies, a Storage object's bytes — is already unrecoverable. An
///      "Undo" that hands back a different row is a lie.
///   2. A soft delete + restore is the honest answer for a *trash*
///      feature, but it costs a `deleted_at` column on every adopting
///      table, an RLS/read-path filter everywhere, and a retention story.
///   3. Deferring the mutation until the undo window closes means
///      **nothing is destroyed while undo is on offer**, so undo cannot
///      fail. That is this module.
///
/// The row leaves the caller's local list immediately (the action feels
/// done) while `commit` is held. Undo cancels the pending commit and
/// calls `restore`; the server was never touched. A commit that later
/// fails also calls `restore`, so a list never claims a row is gone
/// while the server still holds it.
///
/// One slot, deliberately: a second destruction commits the first
/// immediately rather than stacking bars whose ordering the user would
/// have to reason about.
///
/// Kept free of Flutter and of `Timer` so it is host-testable against a
/// fake clock (see test/undo_queue_test.dart); the overlay host lives in
/// widgets/undo_bar.dart.

/// The undo window in seconds, keyed by the `undo_window_s` pref.
/// `0` turns the time limit off entirely — the WCAG 2.2.1 "Turn off"
/// route, so a screen-reader or motor-impaired user is never racing a
/// countdown to reach the only undo affordance.
const List<int> kUndoWindowChoicesS = [8, 30, 0];
const int kDefaultUndoWindowS = 8;

/// Normalises a stored `undo_window_s` bag value. An absent, corrupt, or
/// unrecognised value falls back to the default rather than to `0` — a
/// garbage bag must not silently pin every destructive action open
/// forever, which would leave the user's list disagreeing with the
/// server until they navigate.
int undoWindowSFromPref(Object? raw) {
  if (raw is! num || !raw.isFinite) return kDefaultUndoWindowS;
  final value = raw.toInt();
  if (value != raw) return kDefaultUndoWindowS;
  return kUndoWindowChoicesS.contains(value) ? value : kDefaultUndoWindowS;
}

class DeferredDestruction {
  const DeferredDestruction({
    required this.message,
    required this.commit,
    required this.restore,
    this.onCommitError,
  });

  /// Already-localized sentence for the undo bar ("Porridge removed").
  final String message;

  /// The server mutation. Runs when the window closes — never at the
  /// moment the user taps delete.
  final Future<void> Function() commit;

  /// Puts the caller's local state back exactly as it was. Run on undo
  /// and on a commit failure.
  final void Function() restore;

  /// Surfaces a commit failure at the call site (a banner).
  final void Function(Object error)? onCommitError;
}

class PendingUndo {
  const PendingUndo({
    required this.id,
    required this.message,
    required this.windowMs,
    required this.paused,
  });

  final int id;
  final String message;

  /// How long the bar has to run, in ms. `0` means there is no time
  /// limit at all — the user's chosen "until I dismiss it" window.
  final int windowMs;
  final bool paused;
}

class UndoQueueDeps {
  const UndoQueueDeps({
    required this.windowMs,
    required this.setTimer,
    required this.clearTimer,
    required this.now,
    required this.onChange,
  });

  /// The undo window in ms, read at defer time. `0` or less disables
  /// the timer entirely (WCAG 2.2.1 "turn off").
  final int Function() windowMs;
  final Object Function(void Function() cb, int ms) setTimer;
  final void Function(Object handle) clearTimer;
  final int Function() now;
  final void Function(PendingUndo? pending) onChange;
}

class _Entry {
  _Entry({
    required this.id,
    required this.destruction,
    required this.windowMs,
    required this.remainingMs,
    required this.startedAt,
  });

  final int id;
  final DeferredDestruction destruction;
  final int windowMs;
  int remainingMs;
  int startedAt;
  bool paused = false;
  Object? timer;
  bool settled = false;
}

class UndoQueue {
  UndoQueue(this._deps);

  final UndoQueueDeps _deps;
  int _nextId = 1;
  _Entry? _current;

  bool hasPending() => _current != null;

  void _publish() {
    final c = _current;
    _deps.onChange(c == null
        ? null
        : PendingUndo(
            id: c.id,
            message: c.destruction.message,
            windowMs: c.windowMs,
            paused: c.paused,
          ));
  }

  void _disarm() {
    final c = _current;
    final timer = c?.timer;
    if (timer != null) {
      _deps.clearTimer(timer);
      c!.timer = null;
    }
  }

  void _arm() {
    final c = _current;
    if (c == null || c.windowMs <= 0) return;
    c.startedAt = _deps.now();
    c.timer = _deps.setTimer(() => unawaited(flush()), c.remainingMs);
  }

  /// Detaches the pending entry so a concurrent flush/undo/defer can't
  /// act on it twice. Returns null when there was nothing pending.
  DeferredDestruction? _take() {
    final c = _current;
    if (c == null || c.settled) return null;
    c.settled = true;
    _disarm();
    _current = null;
    _publish();
    return c.destruction;
  }

  /// Commit the pending destruction now — the dismiss button, a
  /// navigation, or a second destruction arriving.
  Future<void> flush() async {
    final destruction = _take();
    if (destruction == null) return;
    try {
      await destruction.commit();
    } catch (error) {
      destruction.restore();
      destruction.onCommitError?.call(error);
    }
  }

  void defer(DeferredDestruction destruction) {
    unawaited(flush());
    final requested = _deps.windowMs();
    final windowMs = requested < 0 ? 0 : requested;
    _current = _Entry(
      id: _nextId++,
      destruction: destruction,
      windowMs: windowMs,
      remainingMs: windowMs,
      startedAt: _deps.now(),
    );
    _arm();
    _publish();
  }

  void undo() {
    final destruction = _take();
    if (destruction == null) return;
    destruction.restore();
  }

  void pause() {
    final c = _current;
    if (c == null || c.paused || c.windowMs <= 0) return;
    final elapsed = _deps.now() - c.startedAt;
    final remaining = c.remainingMs - elapsed;
    c.remainingMs = remaining < 0 ? 0 : remaining;
    _disarm();
    c.paused = true;
    _publish();
  }

  void resume() {
    final c = _current;
    if (c == null || !c.paused || c.windowMs <= 0) return;
    c.paused = false;
    _arm();
    _publish();
  }
}

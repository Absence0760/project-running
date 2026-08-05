import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../undo_queue.dart';
import 'top_banner.dart';

/// Host for the deferred-commit undo offer — the mobile counterpart of web's
/// `UndoBar.svelte`. The contract, the one-slot rule and the WCAG rationale
/// live in [UndoQueue]; this file holds only the real timer wiring and the
/// pill.
///
/// **Why a root [Overlay] entry and not a `SnackBar`.** Two independent
/// reasons, either of which is disqualifying. First, Material's snack bar is
/// already banned in `lib/screens` + `lib/widgets` by an architecture guard:
/// it docks at the bottom, where on the recording screen it covered
/// Pause / Stop / Lap. Second, and specific to undo: a snack bar is
/// rendered inside its `Scaffold`, which sits *below* a dialog or bottom
/// sheet in the Navigator stack — and a modal route's barrier carries
/// `BlockSemantics`, so the whole route under it is dropped from the
/// compiled semantics tree. Measured, not assumed: a snack bar raised while
/// a dialog is up produces no semantics node at all, so TalkBack and
/// VoiceOver can neither announce nor reach it. An undo only sighted
/// pointer users can operate is not an undo (WCAG 2.1.1). A root-overlay
/// entry inserted by [Overlay.insert] lands above every existing entry,
/// including a modal barrier, so it stays in the semantics tree with the
/// dialog — which is what lets an in-sheet delete adopt undo on this
/// platform even though web had to widen a Tab trap to get there.
///
/// **Why the offer survives a route pop.** The queue is a top-level
/// singleton and its timer belongs to it, not to any [State], so popping
/// the surface the row was deleted from cannot cancel the pending commit —
/// the mutation still lands on schedule. Web flushes on navigation because
/// its bar describes a list the user has left; here forcing an early commit
/// would be the only way to *lose* the offer, so we do not. The cost is
/// paid at the call site instead: every `restore` is mount-guarded, and
/// because each adopting list is rebuilt from the server (or from the local
/// store) on its next load, an undo whose surface has gone self-heals.

int _windowS = kDefaultUndoWindowS;

/// Hydrated from the `undo_window_s` universal pref. Read at defer time, so
/// changing it never shortens a window already running.
void setUndoWindowS(Object? raw) {
  _windowS = undoWindowSFromPref(raw);
}

final ValueNotifier<PendingUndo?> _pending = ValueNotifier<PendingUndo?>(null);

OverlayState? _overlay;
OverlayEntry? _entry;

/// Distance from the top of the screen to the pill, captured at defer time
/// from the calling screen's [Scaffold] exactly as `showTopBanner` does — the
/// overlay sits above every route, so the entry's own builder cannot see the
/// AppBar it must not cover.
double _topInset = 0;

final UndoQueue undoQueue = UndoQueue(
  UndoQueueDeps(
    windowMs: () => _windowS * 1000,
    setTimer: (cb, ms) => Timer(Duration(milliseconds: ms), cb),
    clearTimer: (handle) => (handle as Timer).cancel(),
    now: () => DateTime.now().millisecondsSinceEpoch,
    onChange: _onChange,
  ),
);

void _onChange(PendingUndo? next) {
  _pending.value = next;
  if (next == null) {
    final entry = _entry;
    _entry = null;
    if (entry != null && entry.mounted) entry.remove();
    return;
  }
  if (_entry != null) return;
  final overlay = _overlay;
  if (overlay == null) return;
  _entry = OverlayEntry(builder: (_) => _UndoPill(pending: _pending));
  overlay.insert(_entry!);
}

/// Remove the row from the caller's local state first, then hand the server
/// mutation here. It runs when the undo window closes — never before — so
/// [UndoQueue.undo] only has to cancel a timer.
///
/// [destruction.commit] and [destruction.restore] outlive the calling
/// widget: capture app-scoped services (the api client, a store) and never a
/// [BuildContext], and resolve [destruction.message] before the call.
void deferDestructive(BuildContext context, DeferredDestruction destruction) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) _overlay = overlay;
  final mq = MediaQuery.of(context);
  _topInset =
      mq.padding.top + (Scaffold.maybeOf(context)?.appBarMaxHeight ?? 0) + 12;
  // The pill and the top banner share the one notification anchor, and the
  // pill is the non-transient of the two — it carries the only affordance
  // for an action the user may still want to take back.
  hideTopBanner();
  undoQueue.defer(destruction);
}

@visibleForTesting
void debugResetUndo() {
  final entry = _entry;
  _entry = null;
  if (entry != null && entry.mounted) entry.remove();
  _overlay = null;
  _pending.value = null;
  _windowS = kDefaultUndoWindowS;
  _topInset = 0;
}

class _UndoPill extends StatefulWidget {
  const _UndoPill({required this.pending});

  final ValueNotifier<PendingUndo?> pending;

  @override
  State<_UndoPill> createState() => _UndoPillState();
}

class _UndoPillState extends State<_UndoPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown = AnimationController(vsync: this);
  late final AppLifecycleListener _lifecycle;
  int? _armedFor;

  @override
  void initState() {
    super.initState();
    widget.pending.addListener(_sync);
    // Backgrounding is not the user spending their window: an incoming call
    // or a notification tap must not silently burn the offer down.
    _lifecycle = AppLifecycleListener(
      onPause: undoQueue.pause,
      onRestart: undoQueue.resume,
    );
    _sync();
  }

  void _sync() {
    final p = widget.pending.value;
    if (p == null) return;
    if (p.windowMs <= 0) {
      _countdown.stop();
      return;
    }
    if (_armedFor != p.id) {
      _armedFor = p.id;
      _countdown.duration = Duration(milliseconds: p.windowMs);
      _countdown.forward(from: 0);
    }
    if (p.paused) {
      _countdown.stop();
    } else if (!_countdown.isAnimating && _countdown.value < 1) {
      _countdown.forward();
    }
  }

  @override
  void dispose() {
    widget.pending.removeListener(_sync);
    _lifecycle.dispose();
    _countdown.dispose();
    super.dispose();
  }

  void _undo(AppLocalizations l10n) {
    // Banner first: `undo()` publishes a null pending, which removes this
    // entry and unmounts the context the banner needs.
    showTopBanner(context, l10n.undoRestored);
    undoQueue.undo();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<PendingUndo?>(
      valueListenable: widget.pending,
      builder: (context, p, _) {
        if (p == null) return const SizedBox.shrink();
        return Positioned(
          top: _topInset,
          left: 16,
          right: 16,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.98),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.outlineVariant),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Semantics(
                              liveRegion: true,
                              // The countdown is deliberately outside the
                              // announced label: a ticking number would
                              // re-announce on every tick.
                              label: '${p.message}. ${l10n.undoHint}',
                              child: ExcludeSemantics(
                                child: Text(
                                  p.message,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _undo(l10n),
                            child: Text(
                              l10n.undoAction,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.undoDismiss,
                            onPressed: () => unawaited(undoQueue.flush()),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                    if (p.windowMs > 0)
                      ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: _countdown,
                          builder: (context, _) => FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 1 - _countdown.value,
                            child: Container(height: 2, color: cs.primary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

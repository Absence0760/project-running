import 'dart:async';

import 'package:api_client/api_client.dart'
    hide SessionPlanBlockInput, SessionPlanItemInput;
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio_cues.dart';
import '../event_gym_template.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../session_steps.dart';
import '../widgets/top_banner.dart';

/// Read-only mobile view of a session plan's expanded sequence
/// (session_planner.md P1) plus the timed follow-along runner (P2). The editor
/// lives on web first; mobile reads + plays back.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.api,
    required this.gymStore,
    required this.planId,
    this.titleHint,
  });

  final ApiClient api;
  final LocalGymStore gymStore;
  final String planId;
  final String? titleHint;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

SessionItemKind sessionKindFromString(String raw) {
  switch (raw) {
    case 'reps':
      return SessionItemKind.reps;
    case 'flow':
      return SessionItemKind.flow;
    default:
      return SessionItemKind.hold;
  }
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  bool _loading = true;
  String? _title;
  String? _discipline;
  List<SessionStep> _steps = const [];

  @override
  void initState() {
    super.initState();
    _title = widget.titleHint;
    _load();
  }

  Future<void> _load() async {
    final data = await widget.api.fetchSessionPlan(widget.planId);
    if (!mounted) return;
    if (data == null) {
      setState(() => _loading = false);
      return;
    }
    final input = SessionPlanInput(
      blocks: [
        for (final b in data.blocks)
          SessionPlanBlockInput(id: b.id, position: b.position, name: b.name),
      ],
      items: [
        for (final it in data.items)
          SessionPlanItemInput(
            id: it.id,
            blockId: it.blockId,
            position: it.position,
            movementName: it.movementName,
            kind: sessionKindFromString(it.kind),
            durationS: it.durationS,
            reps: it.reps,
            perSide: it.perSide,
            tempo: it.tempo,
            cue: it.cue,
          ),
      ],
    );
    setState(() {
      _title = data.plan.title;
      _discipline = data.plan.discipline;
      _steps = expandSessionSteps(input).steps;
      _loading = false;
    });
  }

  String _stepName(AppLocalizations l10n, SessionStep s) {
    switch (s.side) {
      case SessionSide.left:
        return l10n.sessionSideLeft(s.movementName);
      case SessionSide.right:
        return l10n.sessionSideRight(s.movementName);
      case null:
        return s.movementName;
    }
  }

  String _stepLabel(AppLocalizations l10n, SessionStep s) {
    final name = _stepName(l10n, s);
    switch (s.kind) {
      case SessionItemKind.reps:
        return l10n.sessionStepReps(name, s.reps ?? 0);
      case SessionItemKind.flow:
        return l10n.sessionStepFlow(name, s.durationS ?? 0);
      case SessionItemKind.hold:
        return l10n.sessionStepHold(name, s.durationS ?? 0);
    }
  }

  Future<void> _play() async {
    final l10n = AppLocalizations.of(context);
    final result = await Navigator.of(context).push<_SessionRunOutcome>(
      MaterialPageRoute(
        builder: (_) => _SessionRunnerPage(steps: _steps, title: _title),
      ),
    );
    if (result == null || !mounted) return;
    await _logSession(result, l10n);
  }

  Future<void> _logSession(
      _SessionRunOutcome outcome, AppLocalizations l10n) async {
    final expanded = ExpandedSession(
      steps: _steps,
      totalS: _steps.isEmpty ? 0 : _steps.last.cumulativeS,
    );
    final draft = workoutDraftFromSession(expanded, _title, _discipline);
    final adherence = computeSessionAdherence(_steps, outcome.results);
    try {
      await widget.gymStore.createLocal(
        title: draft.title,
        startedAt: DateTime.now().toUtc(),
        durationS: draft.durationS,
        sets: [
          for (final s in draft.sets)
            (
              exerciseName: s.exerciseName,
              reps: s.reps,
              weightKg: null,
              rpe: null,
              durationS: s.durationS,
            ),
        ],
        metadata: {
          MetadataKeys.sessionPlanId: widget.planId,
          MetadataKeys.sessionStepResults: [
            for (final r in outcome.results) _stepResultJson(r),
          ],
          MetadataKeys.sessionAdherence: _verdictWire(adherence.verdict),
        },
      );
      unawaited(widget.gymStore.syncWithServer(widget.api));
      if (mounted) showTopBanner(context, l10n.sessionRunSaved);
    } catch (e) {
      debugPrint('session run save failed: $e');
      if (mounted) showTopBanner(context, l10n.sessionRunSaveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title ?? l10n.sessionTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _steps.isEmpty
              ? Center(child: Text(l10n.sessionNotFound))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(l10n.sessionSteps,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final s in _steps)
                      ListTile(
                        dense: true,
                        title: Text(_stepLabel(l10n, s)),
                        subtitle: s.cue == null ? null : Text(s.cue!),
                      ),
                  ],
                ),
      floatingActionButton: (_loading || _steps.isEmpty)
          ? null
          : FloatingActionButton.extended(
              onPressed: _play,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.sessionRunStart),
            ),
    );
  }
}

Map<String, dynamic> _stepResultJson(SessionStepResult r) => {
      'item_id': r.itemId,
      'movement_name': r.movementName,
      'kind': switch (r.kind) {
        SessionItemKind.reps => 'reps',
        SessionItemKind.flow => 'flow',
        SessionItemKind.hold => 'hold',
      },
      if (r.side != null)
        'side': r.side == SessionSide.left ? 'left' : 'right',
      'target_duration_s': r.targetDurationS,
      'actual_duration_s': r.actualDurationS,
      'status': r.status == SessionStepStatus.completed ? 'completed' : 'skipped',
    };

String _verdictWire(SessionVerdict v) => switch (v) {
      SessionVerdict.completed => 'completed',
      SessionVerdict.partial => 'partial',
      SessionVerdict.abandoned => 'abandoned',
    };

class _SessionRunOutcome {
  const _SessionRunOutcome(this.results);
  final List<SessionStepResult> results;
}

class SessionBandState {
  const SessionBandState({
    required this.step,
    required this.index,
    required this.total,
    required this.remainingS,
  });

  final SessionStep? step;
  final int index;
  final int total;

  /// Seconds remaining on a timed step, else null (a reps step waits on Done).
  final int? remainingS;
}

/// The keep-alive follow-along player page. Drives a [SessionBandState] through
/// a [ValueNotifier]; timed (hold/flow) steps auto-advance via a wall-clock
/// anchored [Timer] so a backgrounded timer can't drift, reps steps wait on the
/// Done tap. Pops a [_SessionRunOutcome] on finish (the per-step results); pops
/// null on a discarded abandon.
class _SessionRunnerPage extends StatefulWidget {
  const _SessionRunnerPage({required this.steps, required this.title});

  final List<SessionStep> steps;
  final String? title;

  @override
  State<_SessionRunnerPage> createState() => _SessionRunnerPageState();
}

class _SessionRunnerPageState extends State<_SessionRunnerPage> {
  final ValueNotifier<SessionBandState> _band =
      ValueNotifier(const SessionBandState(
    step: null,
    index: 0,
    total: 0,
    remainingS: null,
  ));
  final AudioCues _cues = AudioCues();
  final List<SessionStepResult> _results = [];

  int _index = 0;
  Timer? _timer;
  bool _paused = false;
  DateTime? _segmentStartWall;
  int _prePauseElapsedMs = 0;
  bool _lastFiftyAnnounced = false;

  @override
  void initState() {
    super.initState();
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('session runner wakelock enable failed: $e');
    }
    _enterStep();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _band.dispose();
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('session runner wakelock disable failed: $e');
    }
    try {
      _cues.stop();
    } catch (e) {
      debugPrint('session runner cue stop failed: $e');
    }
    super.dispose();
  }

  SessionStep? get _current =>
      _index < widget.steps.length ? widget.steps[_index] : null;

  bool _isTimed(SessionStep s) =>
      s.kind != SessionItemKind.reps && (s.durationS ?? 0) > 0;

  void _enterStep() {
    _timer?.cancel();
    _lastFiftyAnnounced = false;
    _prePauseElapsedMs = 0;
    final step = _current;
    if (step == null) {
      _finish();
      return;
    }
    _announceEnter(step);
    final timed = _isTimed(step);
    if (timed && !_paused) {
      _segmentStartWall = DateTime.now();
      _startTicker(step);
    } else {
      _segmentStartWall = null;
    }
    _publish(step, timed ? (step.durationS ?? 0) : null);
  }

  void _startTicker(SessionStep step) {
    final target = step.durationS ?? 0;
    _timer?.cancel();
    try {
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        // Wall-clock anchored: derive remaining from real elapsed, not a
        // per-tick counter, so a backgrounded / throttled timer can't drift.
        final start = _segmentStartWall;
        if (start == null) return;
        final elapsed = (_prePauseElapsedMs +
                DateTime.now().difference(start).inMilliseconds) /
            1000.0;
        final remaining = (target - elapsed).ceil();
        if (remaining <= 0) {
          _advance(SessionStepStatus.completed);
          return;
        }
        if (remaining <= 3 && !_lastFiftyAnnounced) {
          _lastFiftyAnnounced = true;
          _announceCountdown(remaining);
        }
        _publish(step, remaining < 0 ? 0 : remaining);
      });
    } catch (e) {
      // L4 auxiliary: a timer-start failure must never wedge the runner — the
      // user can still tap Done. Surface it and leave the timer off.
      debugPrint('session runner timer start failed: $e');
    }
  }

  void _publish(SessionStep? step, int? remainingS) {
    _band.value = SessionBandState(
      step: step,
      index: _index,
      total: widget.steps.length,
      remainingS: remainingS,
    );
  }

  void _recordCurrent(SessionStepStatus status) {
    final step = _current;
    if (step == null) return;
    int? actual;
    if (_isTimed(step)) {
      final start = _segmentStartWall;
      actual = start == null
          ? null
          : ((_prePauseElapsedMs +
                      DateTime.now().difference(start).inMilliseconds) /
                  1000)
              .round();
    }
    _results.add(SessionStepResult(
      itemId: step.itemId,
      movementName: step.movementName,
      kind: step.kind,
      side: step.side,
      targetDurationS: step.durationS,
      actualDurationS: actual,
      status: status,
    ));
  }

  void _advance(SessionStepStatus status) {
    _recordCurrent(status);
    _index += 1;
    _enterStep();
  }

  void _finish() {
    _timer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(_SessionRunOutcome(List.of(_results)));
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    final step = _current;
    if (step == null || !_isTimed(step)) return;
    if (_paused) {
      final start = _segmentStartWall;
      if (start != null) {
        _prePauseElapsedMs += DateTime.now().difference(start).inMilliseconds;
      }
      _timer?.cancel();
    } else {
      _segmentStartWall = DateTime.now();
      _startTicker(step);
    }
  }

  Future<void> _confirmAbandon() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.sessionRunDiscardTitle),
            content: Text(l10n.sessionRunDiscardBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.sessionRunResume),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: Text(l10n.sessionRunDiscardConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && mounted) Navigator.of(context).pop();
  }

  // ── Audio cues — each effect in its own try/catch so a TTS failure never
  // stops the timer or the runner (L4 layered resilience). ──

  void _announceEnter(SessionStep step) {
    final l10n = AppLocalizations.of(context);
    final movement = switch (step.side) {
      SessionSide.left => l10n.sessionSideLeft(step.movementName),
      SessionSide.right => l10n.sessionSideRight(step.movementName),
      null => step.movementName,
    };
    // A right-side step is the second half of a per-side movement: announce the
    // switch-sides cue first, then the movement + its coaching cue.
    if (step.side == SessionSide.right) {
      try {
        _cues.speakGuidedCue(l10n.sessionRunSwitchSides);
      } catch (e) {
        debugPrint('session runner switch-sides cue failed: $e');
      }
    }
    try {
      final cue = step.cue;
      _cues.speakGuidedCue(
          cue == null || cue.isEmpty ? movement : '$movement. $cue');
    } catch (e) {
      debugPrint('session runner movement cue failed: $e');
    }
  }

  void _announceCountdown(int seconds) {
    try {
      _cues.speakGuidedCue('$seconds');
    } catch (e) {
      debugPrint('session runner countdown cue failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? l10n.sessionTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.sessionRunAbandon,
          onPressed: _confirmAbandon,
        ),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<SessionBandState>(
          valueListenable: _band,
          builder: (_, state, child) => _SessionExecutionBand(
            state: state,
            paused: _paused,
            onDone: () => _advance(SessionStepStatus.completed),
            onSkip: () => _advance(SessionStepStatus.skipped),
            onPause: _togglePause,
            onAbandon: _confirmAbandon,
          ),
        ),
      ),
    );
  }
}

class _SessionExecutionBand extends StatelessWidget {
  const _SessionExecutionBand({
    required this.state,
    required this.paused,
    required this.onDone,
    required this.onSkip,
    required this.onPause,
    required this.onAbandon,
  });

  final SessionBandState state;
  final bool paused;
  final VoidCallback onDone;
  final VoidCallback onSkip;
  final VoidCallback onPause;
  final VoidCallback onAbandon;

  String _movementName(AppLocalizations l10n, SessionStep s) {
    switch (s.side) {
      case SessionSide.left:
        return l10n.sessionSideLeft(s.movementName);
      case SessionSide.right:
        return l10n.sessionSideRight(s.movementName);
      case null:
        return s.movementName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final step = state.step;
    if (step == null) {
      return Center(child: Text(l10n.sessionRunComplete));
    }
    final isTimed = step.kind != SessionItemKind.reps &&
        (step.durationS ?? 0) > 0 &&
        state.remainingS != null;
    final target = step.durationS ?? 0;
    final progress = (isTimed && target > 0)
        ? ((target - state.remainingS!) / target).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.sessionRunStepCount(state.index + 1, state.total),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          Text(
            _movementName(l10n, step),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          if (isTimed) ...[
            const SizedBox(height: 24),
            Text(
              l10n.sessionRunRemaining(state.remainingS!),
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: theme.dividerColor,
              ),
            ),
          ],
          if (step.cue != null && step.cue!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              step.cue!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
          const SizedBox(height: 32),
          FilledButton(
            onPressed: onDone,
            child: Text(l10n.sessionRunDone),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onSkip,
            child: Text(l10n.sessionRunSkip),
          ),
          if (isTimed) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onPause,
              child: Text(paused ? l10n.sessionRunResume : l10n.sessionRunPause),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: onAbandon,
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error),
            child: Text(l10n.sessionRunAbandon),
          ),
        ],
      ),
    );
  }
}

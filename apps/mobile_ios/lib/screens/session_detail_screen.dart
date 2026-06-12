import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../session_steps.dart';

/// Read-only mobile view of a session plan's expanded sequence
/// (session_planner.md P1). The editor lives on web first; mobile reads.
class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.api,
    required this.planId,
    this.titleHint,
  });

  final ApiClient api;
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
      _steps = expandSessionSteps(input).steps;
      _loading = false;
    });
  }

  String _stepLabel(AppLocalizations l10n, SessionStep s) {
    switch (s.kind) {
      case SessionItemKind.reps:
        return l10n.sessionStepReps(s.movementName, s.reps ?? 0);
      case SessionItemKind.flow:
        return l10n.sessionStepFlow(s.movementName, s.durationS ?? 0);
      case SessionItemKind.hold:
        return l10n.sessionStepHold(s.movementName, s.durationS ?? 0);
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
    );
  }
}

/// expandSessionSteps — the session-plan analogue of the gym routine engine's
/// expand-once helper. Flattens a plan's blocks + items into the ordered list
/// of SessionSteps the editor preview, the read view, and (in P2) the
/// follow-along runner all consume.
///
/// Pure + deterministic + clock-free so both platforms render an identical step
/// list and the future runner is unit-testable without a timer.
///
/// Rules (session_planner.md § The expand-once helper):
///  - order: blocks ascending by `position`, each block's items ascending by
///    `position`; any blockless items (a flat plan) follow, ascending by
///    `position`. Ties broken by input order (a stable sort).
///  - a `perSide` item splits into two consecutive steps, "<name> (Left)" then
///    "<name> (Right)", each carrying the same kind/duration/reps/cue/tempo.
///  - each step carries cumulative time = sum of every prior step's
///    contribution plus its own; a `reps` step (or any step with no positive
///    duration) contributes 0 to the time estimate (the runner waits on a Done
///    tap).
///
/// Web twin: apps/web/src/lib/social/session_steps.ts — keep in lockstep
/// (same algorithm, edge cases, outputs, and test count).
library;

enum SessionItemKind { hold, reps, flow }

class SessionPlanItemInput {
  const SessionPlanItemInput({
    required this.id,
    required this.blockId,
    required this.position,
    required this.movementName,
    required this.kind,
    this.durationS,
    this.reps,
    this.perSide = false,
    this.tempo,
    this.cue,
  });

  final String id;
  final String? blockId;
  final int position;
  final String movementName;
  final SessionItemKind kind;
  final int? durationS;
  final int? reps;
  final bool perSide;
  final String? tempo;
  final String? cue;
}

class SessionPlanBlockInput {
  const SessionPlanBlockInput({
    required this.id,
    required this.position,
    this.name,
  });

  final String id;
  final int position;
  final String? name;
}

class SessionPlanInput {
  const SessionPlanInput({required this.blocks, required this.items});

  final List<SessionPlanBlockInput> blocks;
  final List<SessionPlanItemInput> items;
}

enum SessionSide { left, right }

class SessionStep {
  const SessionStep({
    required this.itemId,
    required this.movementName,
    required this.kind,
    required this.durationS,
    required this.reps,
    required this.tempo,
    required this.cue,
    required this.side,
    required this.cumulativeS,
  });

  final String itemId;
  final String movementName;
  final SessionItemKind kind;
  final int? durationS;
  final int? reps;
  final String? tempo;
  final String? cue;

  /// null for a non-per-side item, else SessionSide.left / right.
  final SessionSide? side;

  /// seconds elapsed at the end of this step (a no-duration step adds 0).
  final int cumulativeS;
}

class ExpandedSession {
  const ExpandedSession({required this.steps, required this.totalS});

  final List<SessionStep> steps;
  final int totalS;
}

/// The positive-duration contribution of a step to the time estimate (else 0).
int _stepDurationS(int? durationS) {
  if (durationS == null || durationS <= 0) return 0;
  return durationS;
}

/// Stable ascending sort by `position`, ties broken by original index.
List<T> _byPosition<T>(List<T> rows, int Function(T) positionOf) {
  final indexed = <MapEntry<int, T>>[
    for (var i = 0; i < rows.length; i++) MapEntry(i, rows[i]),
  ];
  indexed.sort((a, b) {
    final byPos = positionOf(a.value).compareTo(positionOf(b.value));
    if (byPos != 0) return byPos;
    return a.key.compareTo(b.key);
  });
  return [for (final entry in indexed) entry.value];
}

ExpandedSession expandSessionSteps(SessionPlanInput plan) {
  final orderedItems = <SessionPlanItemInput>[];

  for (final block in _byPosition(plan.blocks, (b) => b.position)) {
    final blockItems =
        plan.items.where((item) => item.blockId == block.id).toList();
    orderedItems.addAll(_byPosition(blockItems, (i) => i.position));
  }
  final blockless = plan.items.where((item) => item.blockId == null).toList();
  orderedItems.addAll(_byPosition(blockless, (i) => i.position));

  final steps = <SessionStep>[];
  var cumulative = 0;

  void pushStep(SessionPlanItemInput item, SessionSide? side) {
    cumulative += _stepDurationS(item.durationS);
    final suffix = side == SessionSide.left
        ? ' (Left)'
        : side == SessionSide.right
            ? ' (Right)'
            : '';
    steps.add(
      SessionStep(
        itemId: item.id,
        movementName: item.movementName + suffix,
        kind: item.kind,
        durationS: item.durationS,
        reps: item.reps,
        tempo: item.tempo,
        cue: item.cue,
        side: side,
        cumulativeS: cumulative,
      ),
    );
  }

  for (final item in orderedItems) {
    if (item.perSide) {
      pushStep(item, SessionSide.left);
      pushStep(item, SessionSide.right);
    } else {
      pushStep(item, null);
    }
  }

  return ExpandedSession(steps: steps, totalS: cumulative);
}

/// "How has this routine actually gone?" — the read-back half of the guided
/// session's execution trio (`routine_id` / `gym_step_results` /
/// `gym_adherence`, metadata.md). Every guided session stamps the link, so a
/// routine's own detail screen can answer when it was last run and whether it
/// gets finished.
///
/// The tallies arrive already reduced, from the `gym_routine_history` RPC
/// (migration 20270528_001): a count is an aggregate, and a windowed client
/// read cannot serve one honestly — the previous 500-row window silently
/// under-reported a decade of weekly sessions. What stays here is the display
/// shaping the server has no business deciding: which verdict each row of the
/// bounded recent page carries, its order, the floored days-since-last against
/// the READER's clock, and the completed-of-graded ratio.
///
/// Dart twin of `apps/web/src/lib/gym/routine_history.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Pure functions, no Flutter / Supabase deps.
library;

import 'dart:math' as math;

import 'package:core_models/core_models.dart';

import 'gym_session_draft.dart';

/// A session that carries the routine link but no verdict is [ungraded]: the
/// runner left mid-session and chose "Save as is", which strips the draft
/// marker and keeps `routine_id` while deliberately claiming no adherence. It
/// happened, so it counts as a session, but it can be neither a completion nor
/// a failure.
///
/// Web models this as `RoutineVerdict | 'ungraded'`; Dart reads a union as one
/// enum, so the three graded values here mirror [RoutineVerdict] in
/// `gym_adherence.dart`.
enum RoutineSessionVerdict { completed, partial, abandoned, ungraded }

class RoutineSessionRow {
  final String id;

  /// Raw `gym_workouts.started_at`, carried through unparsed so the caller
  /// formats the same string the row holds.
  final String startedAt;
  final String? title;
  final Object? metadata;

  const RoutineSessionRow({
    required this.id,
    required this.startedAt,
    this.title,
    this.metadata,
  });
}

/// One `gym_routine_history` row: complete tallies over every session the
/// routine has ever been run as, plus the explicitly bounded page of the most
/// recent ones the panel lists.
class RoutineHistoryAggregate {
  final int sessionCount;
  final String? lastPerformedAt;
  final int gradedCount;
  final int completedCount;
  final List<RoutineSessionRow> recentRows;

  const RoutineHistoryAggregate({
    required this.sessionCount,
    required this.lastPerformedAt,
    required this.gradedCount,
    required this.completedCount,
    required this.recentRows,
  });
}

class RoutineSession {
  final String id;
  final String startedAt;
  final int startedAtMs;
  final String? title;
  final RoutineSessionVerdict verdict;

  const RoutineSession({
    required this.id,
    required this.startedAt,
    required this.startedAtMs,
    required this.title,
    required this.verdict,
  });
}

class RoutineHistory {
  /// Only the page the aggregate carried — never the whole history. Named for
  /// what it is so no surface can present it as everything.
  final List<RoutineSession> recentSessions;
  final int sessionCount;
  final String? lastPerformedAt;
  final int? daysSinceLast;
  final int gradedCount;
  final int completedCount;
  final double? completedRate;

  const RoutineHistory({
    required this.recentSessions,
    required this.sessionCount,
    required this.lastPerformedAt,
    required this.daysSinceLast,
    required this.gradedCount,
    required this.completedCount,
    required this.completedRate,
  });
}

const int _dayMs = 86400000;

RoutineSessionVerdict _verdictOf(Object? metadata) {
  if (metadata is! Map) return RoutineSessionVerdict.ungraded;
  switch (metadata[MetadataKeys.gymAdherence]) {
    case 'completed':
      return RoutineSessionVerdict.completed;
    case 'partial':
      return RoutineSessionVerdict.partial;
    case 'abandoned':
      return RoutineSessionVerdict.abandoned;
  }
  return RoutineSessionVerdict.ungraded;
}

/// Shape one routine's server-side aggregate into what the history panel reads.
///
/// Rows still carrying a `gym_session_draft` snapshot are dropped from the
/// page: an in-flight session is not a session performed. The RPC applies the
/// same exclusion to the tallies, so filtering here keeps the listed rows from
/// ever contradicting the count they sit under.
RoutineHistory routineHistoryFromAggregate(
  RoutineHistoryAggregate agg,
  int nowMs,
) {
  final kept = <({int index, RoutineSession session})>[];
  for (final row in agg.recentRows) {
    if (row.id.isEmpty) continue;
    if (hasGymSessionDraft(row.metadata)) continue;
    final at = DateTime.tryParse(row.startedAt);
    if (at == null) continue;
    kept.add((
      index: kept.length,
      session: RoutineSession(
        id: row.id,
        startedAt: row.startedAt,
        startedAtMs: at.millisecondsSinceEpoch,
        title: row.title,
        verdict: _verdictOf(row.metadata),
      ),
    ));
  }
  // Dart's List.sort is unstable where JS's is stable, so without the index
  // fallback two rows sharing a started_at would order differently here than
  // in the web twin.
  kept.sort((a, b) {
    final c = b.session.startedAtMs.compareTo(a.session.startedAtMs);
    return c != 0 ? c : a.index.compareTo(b.index);
  });

  // Taken from the aggregate, not from the page: a bounded page can be empty
  // while the routine has been run hundreds of times.
  final last = agg.lastPerformedAt == null
      ? null
      : DateTime.tryParse(agg.lastPerformedAt!);
  final graded = math.max(0, agg.gradedCount);
  final completed = math.max(0, agg.completedCount);

  return RoutineHistory(
    recentSessions: [for (final k in kept) k.session],
    sessionCount: math.max(0, agg.sessionCount),
    lastPerformedAt: agg.lastPerformedAt,
    // A row stamped ahead of the reader's clock reads as today, never as a
    // negative "in -2 days".
    daysSinceLast: last == null
        ? null
        : math.max(0, (nowMs - last.millisecondsSinceEpoch) ~/ _dayMs),
    gradedCount: graded,
    completedCount: completed,
    completedRate: graded == 0 ? null : completed / graded,
  );
}

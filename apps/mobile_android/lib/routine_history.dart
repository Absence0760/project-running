/// "How has this routine actually gone?" — the read-back half of the guided
/// session's execution trio (`routine_id` / `gym_step_results` /
/// `gym_adherence`, metadata.md). Every guided session stamps the link, so a
/// routine's own detail screen can answer when it was last run and whether it
/// gets finished.
///
/// Dart twin of `apps/web/src/lib/gym/routine_history.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Pure functions, no Flutter / Supabase deps.
library;

import 'dart:math' as math;

import 'package:core_models/core_models.dart';

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
  final List<RoutineSession> sessions;
  final int sessionCount;
  final String? lastPerformedAt;
  final int? daysSinceLast;
  final int gradedCount;
  final int completedCount;
  final double? completedRate;

  const RoutineHistory({
    required this.sessions,
    required this.sessionCount,
    required this.lastPerformedAt,
    required this.daysSinceLast,
    required this.gradedCount,
    required this.completedCount,
    required this.completedRate,
  });
}

const int _dayMs = 86400000;

bool _hasSessionDraft(Object? metadata) {
  if (metadata is! Map) return false;
  return metadata[MetadataKeys.gymSessionDraft] is Map;
}

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

/// Reduce the workout rows linked to one routine into its performance history.
///
/// Rows still carrying a `gym_session_draft` snapshot are dropped: an in-flight
/// session is not a session performed, and counting one would let a resume
/// inflate the routine's usage.
RoutineHistory summariseRoutineHistory(
  List<RoutineSessionRow> rows,
  int nowMs,
) {
  final kept = <({int index, RoutineSession session})>[];
  for (final row in rows) {
    if (row.id.isEmpty) continue;
    if (_hasSessionDraft(row.metadata)) continue;
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
  final sessions = [for (final k in kept) k.session];

  final gradedCount = sessions
      .where((s) => s.verdict != RoutineSessionVerdict.ungraded)
      .length;
  final completedCount = sessions
      .where((s) => s.verdict == RoutineSessionVerdict.completed)
      .length;
  final last = sessions.isEmpty ? null : sessions.first;

  return RoutineHistory(
    sessions: sessions,
    sessionCount: sessions.length,
    lastPerformedAt: last?.startedAt,
    // A row stamped ahead of the reader's clock reads as today, never as a
    // negative "in -2 days".
    daysSinceLast: last == null
        ? null
        : math.max(0, (nowMs - last.startedAtMs) ~/ _dayMs),
    gradedCount: gradedCount,
    completedCount: completedCount,
    completedRate: gradedCount == 0 ? null : completedCount / gradedCount,
  );
}

import 'dart:io';

import 'package:test/test.dart';

/// Pins where the run-detail segment chips get their rank.
///
/// `fetchEffortsForRunWithSegments` used to count, per effort, the
/// `segment_efforts` rows with a strictly faster time on the same segment.
/// That is the population `segment_leaderboard_tiered` stopped ranking over in
/// migration `20270424000003` (issue #393) and `segment_effort_ranks` stopped
/// ranking over in `20270523_001` (decisions §594): an athlete's repeat effort
/// is a second ROW but not a second competitor, so the count reported a rank
/// the board the chip links to does not give — #3 where the board seats the
/// athlete #2 — and it drifts further with every repetition. It also counted
/// the caller's own faster efforts against them, and could not subtract
/// blocked athletes, which `segment_efforts` RLS does not carry. Web moved to
/// the RPC when it landed; the mobile v1 path did not, while its own catalogue
/// twin `fetchGlobalEffortsForRun` did.
///
/// A source guard rather than a wire test, following
/// `public_run_counts_source_test.dart`: the old query is well-formed and
/// succeeds, it just answers a different question. Reproducing the divergence
/// live needs one segment, two athletes and three runs — which
/// `api_client_integration_test.dart` has no fixture for, and which
/// `segment_effort_ranks_per_athlete_test.sql` already pins server-side.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();
  final start = src.indexOf(
      'Future<List<SegmentEffortWithSegment>> fetchEffortsForRunWithSegments(');
  final end = start < 0 ? -1 : src.indexOf('\n  // -- Row mapping', start);
  final body =
      start < 0 || end < 0 ? '' : src.substring(start, end);

  test('fetchEffortsForRunWithSegments is where the rank is built', () {
    expect(body, isNotEmpty, reason: 'the method moved or was renamed');
  });

  test('ranks come from the segment_effort_ranks RPC', () {
    expect(
      body.contains("rpc(\n      'segment_effort_ranks',"),
      isTrue,
      reason: 'the rank must come from the RPC so the chip and the '
          'per-athlete leaderboard cannot disagree',
    );
    expect(
      body.contains("params: {'p_run_id': runId}"),
      isTrue,
      reason: 'the RPC takes the run id',
    );
  });

  test('the per-effort count loop is gone', () {
    expect(
      body.contains('CountOption.exact'),
      isFalse,
      reason: 'counting strictly-faster effort ROWS ranks over a population '
          'no leaderboard uses, and is an N+1 besides',
    );
    expect(
      body.contains('SegmentEffortRow.colTimeSeconds'),
      isFalse,
      reason: 'the client must not compare times itself — the RPC owns the '
          'comparison set, including the block filter',
    );
  });

  test('a missing rank row degrades to 1, matching web', () {
    // The RPC deliberately returns a row for every effort the caller can see,
    // including on a blocked athlete's public run, precisely because both
    // clients render a missing row as #1 — a crown. Keep the two the same.
    expect(
      body.contains('rankByEffort[eff.id] ?? 1'),
      isTrue,
      reason: 'web fetchEffortsForRun uses `?? 1`; the twin must not drift',
    );
  });
}

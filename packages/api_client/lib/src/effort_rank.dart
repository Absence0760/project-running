/// Reading a segment effort's standing off the wire.
///
/// Rank is not a property of the effort row — it arrives separately, from
/// `segment_effort_ranks` / `global_segment_effort_ranks` — so an effort the
/// RPC did not answer for has a genuinely UNKNOWN standing. Both clients used
/// to spend that absence as `?? 1`, the single most flattering claim these
/// surfaces can make, produced by having no answer at all (decisions §746).
///
/// Mirrors the read half of `apps/web/src/lib/segments/effort_rank.ts`. The
/// render half is not here and cannot be: it resolves theme colours, and this
/// package does not depend on Flutter. It lives in `run_segment_efforts.dart`
/// on each twin.
library;

/// Index the rank RPC's rows by effort id, dropping anything unusable.
///
/// Unlike web — where `supabase.rpc` resolves with `{ data: null, error }` —
/// postgrest-dart THROWS on a non-2xx, so a failed call never reaches here at
/// all; it propagates out of the fetcher to the caller's own guard. What this
/// does absorb is a call that SUCCEEDS while omitting an effort, and a rank
/// that arrives in a shape the client cannot use. Both are the same answer:
/// no standing.
Map<String, int> readEffortRankRows(Object? rows) {
  final out = <String, int>{};
  if (rows is! List) return out;
  for (final row in rows) {
    if (row is! Map) continue;
    final id = row['effort_id'];
    if (id is! String || id.isEmpty) continue;
    final rank = _usableRank(row['rank']);
    if (rank != null) out[id] = rank;
  }
  return out;
}

/// The RPC returns `1 + count(...)::integer`, so anything else came from a
/// wire coercion going wrong and is treated as no answer rather than as a
/// position — least of all as first.
int? _usableRank(Object? raw) {
  final n = raw is num ? raw : (raw is String ? num.tryParse(raw) : null);
  if (n == null || !n.isFinite) return null;
  final i = n.toInt();
  return i >= 1 ? i : null;
}

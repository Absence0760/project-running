/// Conservative chunk size for `.inFilter(col, ids)` id lists. PostgREST
/// serialises an `in` filter into the request URL, so a list of many hundreds
/// of ids overflows the gateway's request-line limit and the query silently
/// returns an empty result. A UUID serialises to ~38 chars inside `in(...)`, so
/// 100 ids keep the clause well under the header budget alongside the other
/// query params. Mirrors web's `feed_merge.ts` `FEED_FOLLOWEE_CHUNK`.
const int kInFilterChunk = 100;

/// Split [items] into consecutive sublists of at most [size]. The caller runs
/// one query per chunk and merges the results — see `fetchFollowingBadgeAwards`
/// and `SocialService.fetchAttendees`.
List<List<T>> chunkList<T>(List<T> items, [int size = kInFilterChunk]) {
  if (size <= 0) {
    throw ArgumentError.value(size, 'size', 'must be positive');
  }
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += size) {
    final end = i + size < items.length ? i + size : items.length;
    out.add(items.sublist(i, end));
  }
  return out;
}

/// Run [query] once per [chunkList] chunk of [ids] and concatenate the rows.
/// The closure's parameter is named `chunk` by convention: `in_filter_bound_
/// test.dart` reads that name to tell a chunked `.inFilter(...)` from an
/// unguarded one.
Future<List<T>> readChunked<T>(
  List<String> ids,
  Future<List<T>> Function(List<String> chunk) query,
) async {
  if (ids.isEmpty) return const [];
  final pages = await Future.wait(chunkList(ids).map(query));
  return [for (final page in pages) ...page];
}

/// Reduce the concatenated rows of a chunked cursor page down to the single
/// global page. Every chunk query applied the same cursor, ordering and limit,
/// so the global top-[limit] rows are a subset of the union: dedupe by id,
/// re-sort by [recencyOf] desc then id desc, and trim. Mirrors the merge half
/// of web's `feed_merge.ts`.
List<T> topByRecency<T>(
  List<T> rows, {
  required int limit,
  required String Function(T row) idOf,
  required DateTime Function(T row) recencyOf,
}) {
  if (limit <= 0) return const [];
  final byId = <String, T>{};
  for (final row in rows) {
    byId[idOf(row)] = row;
  }
  final merged = byId.values.toList()
    ..sort((a, b) {
      final byRecency = recencyOf(b).compareTo(recencyOf(a));
      return byRecency != 0 ? byRecency : idOf(b).compareTo(idOf(a));
    });
  if (merged.length > limit) merged.removeRange(limit, merged.length);
  return merged;
}

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

/// Rows PostgREST returns for a single unbounded SELECT. The server caps at
/// `db.max-rows` and answers with the truncated page and a 200 — no error, no
/// flag — so a read whose contract is "every row" cannot be expressed as a
/// bare `.select()`. It has to ask for explicit ranges until a short page
/// proves the result set is exhausted.
const int kPostgrestPageSize = 1000;

/// Accumulate every row [fetchPage] can produce, one [pageSize] range at a
/// time. [fetchPage] is handed the INCLUSIVE `[from, to]` bounds of the next
/// range and must apply a total order — a range over an ambiguous ordering
/// lets a row on a page boundary come back twice or not at all.
///
/// Deliberately has no row ceiling: a ceiling would silently truncate, which
/// is the bug this exists to remove. The loop terminates on the first short
/// page, and a range past the end of the result set is always short.
///
/// Errors propagate. A caller archiving a history would rather fail loudly
/// than write a file that is partial but reads as complete.
Future<List<T>> readAllPages<T>(
  Future<List<T>> Function(int from, int to) fetchPage, {
  int pageSize = kPostgrestPageSize,
}) async {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
  }
  final out = <T>[];
  var from = 0;
  while (true) {
    final page = await fetchPage(from, from + pageSize - 1);
    out.addAll(page);
    if (page.length < pageSize) return out;
    from += pageSize;
  }
}

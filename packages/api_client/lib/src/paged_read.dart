/// Rows PostgREST returns for a single unbounded SELECT. The server caps at
/// `db.max-rows` and answers with the truncated page and a 200 — no error, no
/// flag — so a read whose contract is "every row" cannot be expressed as a
/// bare `.select()`. It has to ask for explicit ranges until the result set
/// proves exhausted.
///
/// This is the size [readAllPages] ASKS for. It is deliberately not assumed to
/// be the size it gets: see there.
const int kPostgrestPageSize = 1000;

/// Accumulate every row [fetchPage] can produce, one [pageSize] range at a
/// time. [fetchPage] is handed the INCLUSIVE `[from, to]` bounds of the next
/// range and must apply a total order — a range over an ambiguous ordering
/// lets a row on a page boundary come back twice or not at all. A range past
/// the end of the result set must answer with an empty list, which is what
/// PostgREST does (measured: `200 []`) as long as the caller does not ask for
/// an exact count, which turns the same request into a `416`.
///
/// Deliberately has no row ceiling: a ceiling would silently truncate, which
/// is the bug this exists to remove.
///
/// **A short page is not proof of exhaustion**, which is the same bug from the
/// other side. A deployment whose `db.max-rows` is below [pageSize] answers
/// the very first range with a short page and a 200, so a loop that stops
/// there reports a partial history as complete — and nothing anywhere asserts
/// that the server's cap and this constant agree. So the walk advances by the
/// rows it RECEIVED rather than by the size it asked for (a truncated page
/// must not skip the rows it did not return), and it stops only when a page is
/// empty, or is both short of the ask AND shorter than the page before it —
/// the shape a genuinely exhausted result set has and a consistently-capping
/// server does not.
///
/// The cost is one extra round trip when the FIRST page comes back short,
/// because a short first page has no predecessor to be shorter than and the
/// two causes are indistinguishable without asking again. Every other shape
/// costs exactly what it did before.
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
  int? previous;
  while (true) {
    final page = await fetchPage(from, from + pageSize - 1);
    out.addAll(page);
    if (page.isEmpty) return out;
    if (page.length < pageSize && previous != null && page.length < previous) {
      return out;
    }
    previous = page.length;
    from += page.length;
  }
}

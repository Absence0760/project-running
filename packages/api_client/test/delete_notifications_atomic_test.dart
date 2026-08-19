import 'dart:io';

import 'package:test/test.dart';

/// Pins that a bulk dismiss stays ONE transaction.
///
/// The method used to hand its id list to `.inFilter`, which PostgREST
/// serialises into the request URL: past the gateway's request-line budget the
/// DELETE matched nothing and still answered 200, so a >100-row dismiss
/// silently deleted zero rows. Chunking that list closed the no-op and opened a
/// partial one — chunk 3 of 5 can fail with the rows already gone from the list
/// and the undo offer already spent.
///
/// `delete_notifications(uuid[])` takes the array in the RPC's POST body, so
/// there is nothing left to chunk. Atomicity itself is a server property (the
/// pgTAP suite pins it against a trigger that fails mid-batch); what the client
/// can observe, and what regresses if someone reaches for the old shape, is
/// that exactly one call carries the whole list.
void main() {
  late String body;

  setUp(() {
    body = _methodBody('deleteNotifications');
  });

  test('the dismiss goes through the RPC, not an id filter', () {
    expect(
      body,
      contains("rpc('delete_notifications', params: {'p_ids': ids})"),
      reason: 'the whole id array must reach the server in one call',
    );
    expect(body, isNot(contains('.inFilter(')),
        reason: 'an `in` filter past the request-line budget matches nothing '
            'and still answers 200 — that is the bug the RPC closes');
  });

  test('nothing chunks or loops the id list', () {
    for (final shape in ['chunkList', 'readChunked', 'for (', 'while (']) {
      expect(body, isNot(contains(shape)),
          reason: '`$shape` splits one dismiss across several statements, '
              'which is exactly the partial dismiss the RPC exists to remove');
    }
    expect('await '.allMatches(body).length, 1,
        reason: 'a second awaited call is a second transaction');
  });

  test('ownership is left to the RLS policy, not re-derived here', () {
    // The RPC is SECURITY INVOKER and the notifications DELETE policy is
    // already exactly `auth.uid() = user_id`. A repeated user_id filter would
    // be a second copy of that predicate with nothing to catch a drift.
    expect(body, isNot(contains('colUserId')));
  });
}

String _methodBody(String name) {
  final src = File('lib/src/api_client.dart').readAsStringSync();
  final start = src.indexOf('Future<void> $name(');
  if (start < 0) throw StateError('$name moved or was renamed');
  final end = src.indexOf('\n  }', start);
  if (end <= start) throw StateError('could not bound $name');
  return src.substring(start, end);
}

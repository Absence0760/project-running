import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  test('operations on one key run one at a time, in call order', () async {
    final log = <String>[];
    Future<void> op(String tag) => serialiseStoreWrite('dir', () async {
          log.add('$tag start');
          await Future<void>.delayed(const Duration(milliseconds: 10));
          log.add('$tag end');
        });

    await Future.wait([op('a'), op('b'), op('c')]);

    expect(log, ['a start', 'a end', 'b start', 'b end', 'c start', 'c end']);
  });

  test('different keys do not block each other', () async {
    final log = <String>[];
    final slow = serialiseStoreWrite('slow', () async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      log.add('slow');
    });
    final fast = serialiseStoreWrite('fast', () async => log.add('fast'));
    await Future.wait([slow, fast]);

    expect(log, ['fast', 'slow']);
  });

  test('a failed operation does not reject the ones queued behind it',
      () async {
    final failing = serialiseStoreWrite('dir', () async {
      throw StateError('boom');
    });
    final after = serialiseStoreWrite('dir', () async => 7);

    await expectLater(failing, throwsStateError);
    expect(await after, 7);
  });

  test('a re-entrant call on the same key runs inline instead of deadlocking',
      () async {
    final done = serialiseStoreWrite('dir', () async {
      // A public entry point whose shared persist helper is serialised too.
      await serialiseStoreWrite('dir', () async {});
      return 'inner ran';
    });

    expect(await done.timeout(const Duration(seconds: 2)), 'inner ran');
  });

  test('re-entrancy tolerance is scoped to the key it was granted for',
      () async {
    final log = <String>[];
    final outer = serialiseStoreWrite('a', () async {
      log.add('outer start');
      await serialiseStoreWrite('b', () async => log.add('inner b'));
      log.add('outer end');
    });
    await outer;
    expect(log, ['outer start', 'inner b', 'outer end']);
  });

  test('storeWritesSettled waits for an operation started but not awaited',
      () async {
    var landed = false;
    unawaited(serialiseStoreWrite('dir', () async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      landed = true;
    }));

    await storeWritesSettled('dir');
    expect(landed, isTrue);
  });

  test('a drained chain is discarded, so a reused key starts clean', () async {
    await serialiseStoreWrite('reused', () async {});
    var ran = false;
    // Nothing is queued, so this must not wait on a retained tail.
    await serialiseStoreWrite('reused', () async => ran = true)
        .timeout(const Duration(seconds: 2));
    expect(ran, isTrue);
  });
  test('a synchronous throw is caught, and the chain behind it still runs',
      () async {
    // The existing failure case throws inside an `async` closure, which
    // returns a rejected future rather than throwing at the call. A plain
    // closure that throws propagates out of `runZoned` synchronously — a
    // different path through the same try, and the one that would leave the
    // chain's link never completing if it escaped.
    final failing = serialiseStoreWrite<int>('dir', () => throw StateError('sync'));
    final after = serialiseStoreWrite('dir', () async => 7);

    await expectLater(failing, throwsStateError);
    expect(await after.timeout(const Duration(seconds: 2)), 7);
  });

  test('order survives a failure: the operation behind it still runs after it',
      () async {
    // A failed write must not be able to reorder the writes queued behind it.
    // Only asserting that the next one RESOLVES would pass even if it had run
    // first, which on a store directory is the delete-overtakes-write race
    // this chain exists to close.
    final log = <String>[];
    final failing = serialiseStoreWrite('dir', () async {
      log.add('failing');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      throw StateError('boom');
    });
    final after = serialiseStoreWrite('dir', () async => log.add('after'));

    await expectLater(failing, throwsStateError);
    await after;
    expect(log, ['failing', 'after']);
  });

  test('storeWritesSettled from inside a serialised body returns, not hangs',
      () async {
    // It is implemented as a queued no-op, so on the same key it inherits the
    // re-entrancy grant and runs inline. That is the only non-deadlocking
    // answer available — queueing behind the body that is asking would wait
    // on itself forever — and a store shutting a directory down calls it from
    // paths that may already be inside the chain.
    final done = serialiseStoreWrite('dir', () async {
      await storeWritesSettled('dir');
      return 'returned';
    });
    expect(await done.timeout(const Duration(seconds: 2)), 'returned');
  });

  test('every key keeps its own order when many interleave', () async {
    // One shared chain instead of one per key would still produce a total
    // order, so each key's sequence would still be internally ordered — but
    // the keys would serialise against each other, which the timing below
    // makes visible: a directory whose writes are fast must not be held up
    // behind a slow one, and its own writes must still land in call order.
    final log = <String>[];
    final futures = <Future<void>>[];
    for (var i = 0; i < 5; i++) {
      futures.add(serialiseStoreWrite('slow', () async {
        await Future<void>.delayed(const Duration(milliseconds: 8));
        log.add('slow$i');
      }));
      futures.add(serialiseStoreWrite('fast', () async => log.add('fast$i')));
    }
    await Future.wait(futures);

    expect(log.where((e) => e.startsWith('fast')).toList(),
        ['fast0', 'fast1', 'fast2', 'fast3', 'fast4']);
    expect(log.where((e) => e.startsWith('slow')).toList(),
        ['slow0', 'slow1', 'slow2', 'slow3', 'slow4']);
    // The fast key drained entirely before the slow key's second operation,
    // which a single shared chain could not do.
    expect(log.indexOf('fast4'), lessThan(log.indexOf('slow1')));
  });
}

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
}

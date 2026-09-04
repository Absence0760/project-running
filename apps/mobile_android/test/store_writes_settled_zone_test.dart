// `storeWritesSettled`'s zone precondition, pinned in the shape that actually
// bites: a store write started by a fake-zone `tester.tap`, then awaited from
// `tester.runAsync`. `serialiseStoreWrite` links its chain with `.then`, so
// that link's continuation is a fake-zone microtask the real-zone await never
// drains — measured over five configurations in decisions § 1093, where it is
// also measured that comparing zone identity cannot tell the two apart.
//
// Before § 1093 this hung to the runner's own timeout with no message, which
// on CI reads as an infrastructure flake rather than as a misuse.

import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('settled_zone_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('a write queued inside runAsync settles from runAsync',
      (tester) async {
    await tester.runAsync(() async {
      unawaited(serialiseStoreWrite(dir.path, () async {
        await File('${dir.path}/a.json').writeAsString('{}');
      }));
      await storeWritesSettled(dir.path, bound: const Duration(seconds: 5));
    });
    expect(File('${dir.path}/a.json').existsSync(), isTrue);
  });

  testWidgets('a write queued from the fake zone reports rather than hanging',
      (tester) async {
    unawaited(serialiseStoreWrite(dir.path, () async {
      await File('${dir.path}/b.json').writeAsString('{}');
    }));
    await tester.runAsync(() async {
      await expectLater(
        storeWritesSettled(dir.path, bound: const Duration(seconds: 2)),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('did not settle'), contains('pumpUntil')),
        )),
      );
    });
  });
}

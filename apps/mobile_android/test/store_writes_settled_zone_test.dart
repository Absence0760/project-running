// `storeWritesSettled`'s zone precondition, pinned in the shape that actually
// bites: a store write started by a fake-zone `tester.tap`, then awaited from
// `tester.runAsync`. `serialiseStoreWrite` links its chain with `.then`, so
// that link's continuation is a fake-zone microtask the real-zone await never
// drains — measured over five configurations in decisions § 1093, where it is
// also measured that comparing zone identity cannot tell the two apart.
//
// Before § 1093 this hung to the runner's own timeout with no message, which
// on CI reads as an infrastructure flake rather than as a misuse. Row 5 of that
// table — awaited from the fake zone too — still did, because the bound's
// error is itself delivered through the awaiting zone; § 1130 sends the same
// diagnosis to the runner from `Zone.root` instead.

import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_write_watch.dart';

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
    allowStoreWritesToOutliveTest(
        'the unsettleable write is what this test is about');
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

  testWidgets('an awaiter that cannot be resumed is reported to the runner',
      (tester) async {
    allowStoreWritesToOutliveTest(
        'the unsettleable write is what this test is about');
    Object? reported;
    StackTrace? site;
    final prior = debugStoreWritesSettledSink;
    debugStoreWritesSettledSink = (Object e, StackTrace s) {
      reported = e;
      site = s;
    };
    addTearDown(() => debugStoreWritesSettledSink = prior);

    unawaited(serialiseStoreWrite(dir.path, () async {
      await File('${dir.path}/c.json').writeAsString('{}');
    }));
    // Awaited from the fake zone, with no pump behind it: row 5 of § 1093's
    // table, where completing the future reaches nobody.
    // `.ignore()` rather than a catch handler: a catch registered here is a
    // fake-zone continuation too, so it would be exactly as unreachable as the
    // await this test is about.
    storeWritesSettled(dir.path, bound: const Duration(seconds: 1)).ignore();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));

    expect(reported, isA<StateError>());
    expect((reported! as StateError).message, contains(dir.path));
    expect(site, isNotNull);
  });

  testWidgets('a resumable awaiter is not also reported to the runner',
      (tester) async {
    allowStoreWritesToOutliveTest(
        'the unsettleable write is what this test is about');
    var reports = 0;
    final prior = debugStoreWritesSettledSink;
    debugStoreWritesSettledSink = (Object e, StackTrace s) => reports++;
    addTearDown(() => debugStoreWritesSettledSink = prior);

    unawaited(serialiseStoreWrite(dir.path, () async {
      await File('${dir.path}/d.json').writeAsString('{}');
    }));
    await tester.runAsync(() async {
      await expectLater(
        storeWritesSettled(dir.path, bound: const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    expect(reports, 0);
  });
}

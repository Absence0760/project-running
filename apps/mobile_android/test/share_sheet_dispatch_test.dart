// What the share helper actually hands the plugin (decisions § 714).
//
// `share_sheet_test.dart` covers the anchor DERIVATION and
// `architecture_guards_test.dart` covers who may import share_plus. Neither
// exercises `shareFilesFrom` / `shareTextFrom`, so the property the whole
// module exists for — that a share reaching the plugin always carries a
// non-empty `sharePositionOrigin`, because an iPad presents the sheet as a
// popover and refuses one without a source rect — was asserted nowhere. A
// helper that dropped the parameter would have passed every existing test
// and shipped a share that silently never opens on every iPad.
//
// The platform is swapped for a recorder rather than mocked at the method
// channel: `SharePlus.instance` is built from `SharePlatform.instance` on
// first access, so installing the fake in setUpAll is what the production
// call path then reaches.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import '../lib/share_sheet.dart';

class _RecordingSharePlatform extends SharePlatform {
  final List<ShareParams> calls = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    calls.add(params);
    return const ShareResult('recorded', ShareResultStatus.success);
  }
}

late _RecordingSharePlatform _platform;

Rect _viewRect(WidgetTester tester) =>
    Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);

/// Mount a widget of a known size and return its context.
Future<BuildContext> _anchorAt(
  WidgetTester tester, {
  double left = 24,
  double top = 36,
  double width = 100,
  double height = 44,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(left: left, top: top),
          child: SizedBox(
            width: width,
            height: height,
            child: Builder(builder: (ctx) {
              captured = ctx;
              return const SizedBox.expand();
            }),
          ),
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  setUpAll(() {
    _platform = _RecordingSharePlatform();
    SharePlatform.instance = _platform;
  });

  setUp(() => _platform.calls.clear());

  group('shareTextFrom', () {
    testWidgets('reaches the plugin at all', (tester) async {
      final ctx = await _anchorAt(tester);
      await shareTextFrom(ctx, text: 'https://threkir.com/r/abc');

      expect(_platform.calls, hasLength(1),
          reason: 'the recorder never saw the share — the fake platform is '
              'not the one the helper reaches, so every assertion below is '
              'vacuous');
      expect(_platform.calls.single.text, 'https://threkir.com/r/abc');
    });

    testWidgets('carries the anchor derived from the invoking widget',
        (tester) async {
      final ctx = await _anchorAt(tester, left: 24, top: 36, width: 100, height: 44);
      await shareTextFrom(ctx, text: 'link', subject: 'My run');

      final params = _platform.calls.single;
      expect(params.sharePositionOrigin, const Rect.fromLTWH(24, 36, 100, 44),
          reason: 'the popover has to point at the control that was tapped');
      expect(params.subject, 'My run');
    });

    testWidgets('an unresolvable anchor still yields a non-empty rect',
        (tester) async {
      // The iPad plugin rejects CGRectZero exactly as it rejects a missing
      // origin, so degrading has to degrade to a REAL rect. A zero-size box
      // is the shape a mid-animation or collapsed control presents.
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 0,
              height: 0,
              child: Builder(builder: (ctx) {
                captured = ctx;
                return const SizedBox.expand();
              }),
            ),
          ),
        ),
      );
      await shareTextFrom(captured, text: 'link');

      final origin = _platform.calls.single.sharePositionOrigin!;
      expect(origin.isEmpty, isFalse,
          reason: 'an empty rect IS the failure this module prevents');
      expect(_viewRect(tester).contains(origin.center), isTrue,
          reason: 'the plugin also requires the anchor to sit inside the view');
    });

    testWidgets('a context whose element is gone still shares', (tester) async {
      // A share fired after a confirm dialog popped, or from a sheet already
      // dismissed: an L4 auxiliary effect must not take the screen down with
      // it, and it must not silently do nothing either.
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: (ctx) {
            captured = ctx;
            return const SizedBox(width: 20, height: 20);
          }),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(captured.mounted, isFalse);

      await shareTextFrom(captured, text: 'link');

      expect(_platform.calls, hasLength(1));
      expect(_platform.calls.single.sharePositionOrigin!.isEmpty, isFalse);
    });
  });

  group('shareFilesFrom', () {
    testWidgets('carries the files, the caption and the anchor',
        (tester) async {
      final ctx = await _anchorAt(tester, left: 10, top: 12, width: 60, height: 30);
      await shareFilesFrom(
        ctx,
        files: [XFile('/tmp/threkir-test/run.gpx')],
        text: 'My route',
        subject: 'route.gpx',
      );

      final params = _platform.calls.single;
      expect(params.files, hasLength(1));
      expect(params.files!.single.name, 'run.gpx');
      expect(params.text, 'My route');
      expect(params.subject, 'route.gpx');
      expect(params.sharePositionOrigin, const Rect.fromLTWH(10, 12, 60, 30));
    });

    testWidgets('a multi-file share carries one anchor for the whole sheet',
        (tester) async {
      final ctx = await _anchorAt(tester);
      await shareFilesFrom(ctx, files: [
        XFile('/tmp/threkir-test/a.csv'),
        XFile('/tmp/threkir-test/b.csv'),
      ]);

      expect(_platform.calls.single.files, hasLength(2));
      expect(_platform.calls.single.sharePositionOrigin!.isEmpty, isFalse);
    });
  });

  testWidgets('every entry point passes an anchor — none is optional',
      (tester) async {
    // The signature is what makes this true (both take a required positional
    // BuildContext), and the guard in architecture_guards_test.dart holds the
    // signature. This is the behavioural half: whatever a caller does, what
    // arrives at the plugin is anchored.
    final ctx = await _anchorAt(tester);
    await shareTextFrom(ctx, text: 'a');
    await shareFilesFrom(ctx, files: [XFile('/tmp/threkir-test/x.csv')]);

    expect(_platform.calls, hasLength(2));
    for (final params in _platform.calls) {
      final origin = params.sharePositionOrigin;
      expect(origin, isNotNull,
          reason: 'share_plus 12 turns a missing origin into a '
              'PlatformException on iPad and no sheet ever appears');
      expect(origin!.isEmpty, isFalse);
      expect(origin.width, greaterThan(0));
      expect(origin.height, greaterThan(0));
    }
  });
}

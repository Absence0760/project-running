// The share-card rasteriser, and the branch that used to lose a failure.
//
// Four sheets rasterise a card and hand the PNG to the share sheet. Each of
// them sat inside a `try` whose `catch` shows a share-failed banner — and each
// of them opened with `if (byteData == null) return;`, which walks past that
// banner, past the `finally` that clears the spinner, and leaves the runner
// looking at a re-enabled Share button with no share and no message. A failure
// that presents exactly like a cancel is the worst of the three outcomes, and
// nothing measured it because a real `RenderRepaintBoundary` cannot be asked
// to produce a null encoding on demand.
//
// Splitting the null check out is what makes it reachable from a test.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/capture_png.dart';
import 'source_scan.dart';

/// The eight-byte PNG signature every encoder emits first.
const _pngMagic = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

void main() {
  group('pngBytesOrThrow', () {
    test('an encoding that produced nothing is a failure, not a no-op', () {
      // The whole point: this used to be `return`, so the caller's banner
      // never fired and the share silently did not happen.
      expect(() => pngBytesOrThrow(null), throwsStateError);
    });

    test('a real encoding comes back as its bytes', () {
      final source = Uint8List.fromList([1, 2, 3, 4]);
      expect(pngBytesOrThrow(ByteData.view(source.buffer)), source);
    });
  });

  group('capturePngBytes', () {
    testWidgets('rasterises the boundary it is given to a real PNG',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: Container(width: 40, height: 40, color: Colors.indigo),
          ),
        ),
      );

      // `toImage` resolves on the real event loop, so it makes no progress
      // under `pump` alone (decisions § 715).
      late Uint8List bytes;
      await tester.runAsync(() async {
        bytes = await capturePngBytes(key, pixelRatio: 1.0);
      });

      expect(bytes.length, greaterThan(_pngMagic.length));
      expect(bytes.sublist(0, _pngMagic.length), _pngMagic,
          reason: 'the bytes handed to the share sheet must be a PNG');
    });

    testWidgets('a boundary that is not mounted fails loudly', (tester) async {
      // The share happens from a sheet that can be dismissed under it. The
      // caller's catch is what turns this into the banner, so it has to be a
      // throw rather than an empty result.
      await tester.pumpWidget(const SizedBox.shrink());
      await expectLater(
        () => capturePngBytes(GlobalKey()),
        throwsA(isA<Object>()),
      );
    });
  });

  test('no rasteriser keeps a PNG encode of its own', () {
    // The guard the four copies needed. Each one owned the null check, and one
    // of them silently losing it again is invisible from every screen test —
    // the symptom is a share that did not happen and said nothing.
    final offenders = dartFiles('lib')
        .where((f) => f.path != 'lib/widgets/capture_png.dart')
        .where((f) =>
            blankNonCode(f.readAsStringSync()).contains('ImageByteFormat.png'))
        .map((f) => f.path)
        .toList()
      ..sort();

    expect(offenders, isEmpty,
        reason: 'these encode a PNG outside capture_png.dart, so they own the '
            'null-encoding branch themselves: ${offenders.join(', ')}. Call '
            'capturePngBytes instead — a null encoding has to reach the '
            "caller's error banner, not return past it.");
  });
}

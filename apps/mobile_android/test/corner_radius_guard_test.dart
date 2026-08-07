// Source-scan guard for issue #666 V15: eleven corner radii, no scale.
//
// The shipped distribution was 12×45, 8×33, 6×22, 16×21, 4×17, 20×14, 14×12,
// 10×7, 999×7, 2×5, 3×2. V15 prescribed three tokens — 8, 12, 999 — on counts
// that included "999 ×33" when the real pill count is **7**, and both 6 and 16
// outrank it three-to-one. A three-token scale chosen on that arithmetic would
// have moved a fifth of the app's corners onto the wrong rung.
//
// `AppRadius` halves the value set instead, moving no corner more than 2 dp:
// 2 and 3 snap to 4, 6 to 8, 10 and 14 to 12, ties going to the more common
// rung. Like `AppIconSize` this pins the SET rather than the call sites — a
// `BorderRadius` has no theme step to name, so a constant at 185 sites buys
// naming rather than consistency.
//
// The exemption is the fixed-canvas rasterisers, on the same reasoning as every
// prior sweep: they paint a `RepaintBoundary` to a PNG at a size no device
// sees. Count-pinned, so a NEW literal in an exempt file still fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import 'source_scan.dart';

const _roots = ['lib', '../../packages/ui_kit/lib'];

const _rasterisers = <String, int>{};

final _radius = RegExp(r'(?:Border)?Radius\.circular\((\d+(?:\.\d+)?)\)');

void main() {
  test('every corner radius is a rung on the scale', () {
    final offenders = <String>[];
    final exemptCounts = <String, int>{};
    var measured = 0;

    for (final root in _roots.where(rootExists)) {
      for (final file in dartFiles(root)) {
        final rel = file.path.replaceFirst(RegExp(r'^\./'), '');
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _radius.allMatches(src)) {
          measured++;
          if (AppRadius.scale.contains(double.parse(m.group(1)!))) continue;
          if (_rasterisers.containsKey(rel)) {
            exemptCounts[rel] = (exemptCounts[rel] ?? 0) + 1;
            continue;
          }
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('$rel:$line circular(${m.group(1)})');
        }
      }
    }

    // Population: §534 — a regex that stopped matching must not pass by
    // asserting over nothing.
    expect(
      measured,
      greaterThan(150),
      reason: 'the scan found only $measured radius literals — it is probably '
          'broken rather than the app having shrunk',
    );

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'these corner radii are off the scale. Snap each to the nearest '
          'rung on AppRadius, or add the rung if a surface genuinely needs one '
          'the scale does not carry.',
    );

    expect(exemptCounts, equals(_rasterisers),
        reason: 'the rasteriser allowlist may only shrink.');
  });
}

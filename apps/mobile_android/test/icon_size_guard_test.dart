// Source-scan guard for issue #666 V14: `Icon(size:)` had no scale.
//
// The shipped sizes were 18 (×113), 16 (×54), 14 (×21), 20 (×20), 13 (×13),
// 48 (×15), 64 (×7) and one-offs at 6, 11, 12, 22, 24, 26, 28, 32, 36, 40, 60,
// 96. V14 prescribed a three-rung scale — inline 16 / leading 20 /
// illustration 48 — which would have moved the app's single most common size
// (18, more than twice the next) onto a rung it does not use, restyling 113
// call sites to close a consistency finding. So `AppIconSize` is the clusters
// the app converged on by itself, and the work was migrating the 22 one-off
// sites onto the nearest rung.
//
// What this pins is the SET, not the call sites: a size outside the scale
// fails, a literal that equals a rung passes. That is deliberately weaker than
// the `fontSize:` ban, and the reason is that the two are not analogous — type
// has a `textTheme` to name a step with, so a literal there is a step spelled
// by hand; an `Icon` has no equivalent, so requiring every site to import a
// constant buys naming rather than consistency, at 250+ call sites of churn.
//
// The exemption is the fixed-canvas share rasterisers, on the same reasoning
// every prior round exempted them from the theme (§480) and type-scale (§482)
// sweeps: they paint a `RepaintBoundary` to a PNG at a size the device never
// sees, so a device-facing scale does not govern them. Count-pinned on §480's
// model, so a NEW literal in an exempt file still fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import 'source_scan.dart';

const _roots = ['lib', '../../packages/ui_kit/lib'];

/// Files that rasterise a fixed canvas, with their exact count of off-scale
/// sizes. The allowlist can only shrink.
const _rasterisers = <String, int>{
  'lib/widgets/run_share_card.dart': 1,
  'lib/widgets/route_share_card.dart': 1,
  // Not a rasteriser: a 6 px BULLET marking the today row on plan detail. A
  // dot is a shape sized as a dot, not a glyph sized on the icon scale — the
  // same distinction `font_size_literal_guard_test` draws for text inside a
  // load-bearing graphic. Snapping it to the nearest rung took it to 14 and
  // `plan_detail_screen_test` caught it, which is the pin that says it is
  // deliberate.
  'lib/screens/plan_detail_screen.dart': 1,
};

/// Every `size: <int>` argument, attributed to its enclosing constructor by
/// the shared bracket walker rather than by a regex. A regex anchored on
/// `Icon(` cannot cross a nested call — `Icon(Icons.x, color: f(y), size: 20)`
/// — and silently under-scanned by 26 of 293 sites when this guard was first
/// written.
final _sizeArg = RegExp(r'\bsize:\s*(\d+)(?=[,)\s])');

/// Constructors whose `size:` is an icon's, not some other widget's dimension.
const _iconHosts = {'Icon', 'ImageIcon'};

bool _isIconSize(String src, int at) {
  for (final parts in enclosingHosts(src, at)) {
    if (parts.any(_iconHosts.contains)) return true;
    // The innermost named host decides; anything else owns its own `size:`.
    if (parts.last.isNotEmpty) return false;
  }
  return false;
}

void main() {
  test('every Icon size is a rung on the scale', () {
    final offenders = <String>[];
    final exemptCounts = <String, int>{};
    var measured = 0;

    for (final root in _roots.where(rootExists)) {
      for (final file in dartFiles(root)) {
        final rel = file.path.replaceFirst(RegExp(r'^\./'), '');
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _sizeArg.allMatches(src)) {
          if (!_isIconSize(src, m.start)) continue;
          measured++;
          final size = double.parse(m.group(1)!);
          if (AppIconSize.scale.contains(size)) continue;
          if (_rasterisers.containsKey(rel)) {
            exemptCounts[rel] = (exemptCounts[rel] ?? 0) + 1;
            continue;
          }
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('$rel:$line size: ${m.group(1)}');
        }
      }
    }

    // Population: a regex that stopped matching would satisfy the check below
    // over an empty set (decisions §534).
    expect(
      measured,
      greaterThan(200),
      reason: 'the scan found only $measured Icon(size:) sites — it is probably '
          'broken rather than the app having shrunk',
    );

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'these icon sizes are off the scale. Snap each to the nearest '
          'rung on AppIconSize, or — if a surface genuinely needs a size the '
          'scale does not carry — add the rung there rather than a one-off.',
    );

    // An exempt file that stops needing its exemption must give it up.
    expect(
      exemptCounts,
      equals(_rasterisers),
      reason: 'the rasteriser allowlist no longer matches what those files '
          'paint. It may only shrink.',
    );
  });
}

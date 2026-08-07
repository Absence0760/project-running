// Source-scan guard for issue #666 C17: a screen disagreeing with itself about
// where its own left edge is.
//
// C17 read "page gutter is 12, 16 or 20". Measured across the app that is
// 66 sites at 12 and 56 at 20 against **201 at 16** — a global convergence
// would be a 122-site restyle of live screens, which is a design call rather
// than a defect. What IS unambiguous is a single screen whose own scroll views
// disagree: `coach_screen` put its header at 20, its transcript at 12 and a
// third surface at 16, so one page had three left edges. Round 18 fixed the two
// library screens' search field; this closes the four remaining real ones and
// pins the rule.
//
// So the invariant is INTERNAL consistency, not a global value. A screen that
// is uniformly at 12 or 20 passes — its edge is coherent to the reader, which
// is what the finding is about.
//
// The four exemptions are each a different KIND of surface, not a page:
//
//  * `club_detail_screen` — the 20 is a modal bottom sheet's own inset
//    (`showDragHandle` + `SafeArea`). A sheet is not the page under it.
//  * `guided_runs_screen` — the 0 is a full-bleed list; edge-to-edge is the
//    layout, not a gutter that drifted.
//  * `onboarding_screen` — 24/32 is the pre-sign-in hero, deliberately roomier
//    than the app behind it.
//  * `run_screen` — 16/24 on the recording surface. § 551 already declined to
//    spend a visual change there for tidiness, and that reasoning holds here.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _root = 'lib/screens';

/// Screens allowed to carry more than one page-level inset, with the count of
/// DISTINCT values each is allowed. The allowlist may only shrink.
const _exempt = <String, int>{
  'lib/screens/club_detail_screen.dart': 2,
  'lib/screens/guided_runs_screen.dart': 2,
  'lib/screens/onboarding_screen.dart': 2,
  'lib/screens/run_screen.dart': 2,
};

final _scrollPadding = RegExp(
  r'(ListView|SingleChildScrollView|CustomScrollView|GridView)'
  r'[^;]{0,400}?padding:\s*(?:const\s+)?EdgeInsets\.'
  r'(all|symmetric|fromLTRB)\(([^)]*)\)',
  dotAll: true,
);

int? _horizontal(String kind, String args) {
  final m = kind == 'symmetric'
      ? RegExp(r'horizontal:\s*(\d+)').firstMatch(args)
      : RegExp(r'^\s*(\d+)').firstMatch(args);
  return m == null ? null : int.parse(m.group(1)!);
}

void main() {
  test('no screen disagrees with itself about its own left edge', () {
    final offenders = <String>[];
    final exemptSeen = <String, int>{};
    var measured = 0;

    if (!rootExists(_root)) fail('$_root does not exist');
    for (final file in dartFiles(_root)) {
      final rel = file.path.replaceFirst(RegExp(r'^\./'), '');
      final src = blankNonCode(file.readAsStringSync());
      final values = <int>{};
      for (final m in _scrollPadding.allMatches(src)) {
        final v = _horizontal(m.group(2)!, m.group(3)!);
        if (v == null) continue;
        measured++;
        values.add(v);
      }
      if (values.length < 2) continue;
      if (_exempt.containsKey(rel)) {
        exemptSeen[rel] = values.length;
        continue;
      }
      offenders.add('$rel -> ${(values.toList()..sort()).join(', ')}');
    }

    // Population: §534 — a regex that stopped matching would satisfy the
    // assertion below over nothing at all.
    expect(
      measured,
      greaterThan(60),
      reason: 'found only $measured page-level scroll paddings — the scan is '
          'probably broken rather than the app having shrunk',
    );

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'these screens use more than one page-level inset, so their own '
          'left edge moves as the reader scrolls or switches tab. Converge '
          'them — 16 is what 201 of the app\'s sites already use. A sheet, a '
          'full-bleed list or a hero is a different KIND of surface and '
          'belongs in the exemption list with its reason.',
    );

    // An exempt screen that gained a third value, or lost its need for the
    // exemption, must come back here.
    expect(exemptSeen, equals(_exempt),
        reason: 'the page-gutter exemption list no longer matches what those '
            'screens do. It may only shrink.');
  });
}

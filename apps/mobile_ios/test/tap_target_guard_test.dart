import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tap-target guard — pins WCAG 2.5.8 (>= 48dp) on the IconButtons that carry
/// `VisualDensity.compact` (baseSizeAdjustment -8dp/axis → ~40dp) so a later
/// edit can't quietly drop the explicit 48dp constraints and shrink them back
/// under the floor. Source-level (like architecture_guards_test.dart) because
/// the buttons are either private widgets or live inside map screens whose
/// `pumpAndSettle` hangs on tile animations.

const _min48 = 'BoxConstraints(minWidth:48,minHeight:48';

/// Read a screen source with all whitespace stripped, so the assertions don't
/// care whether a constraint was written inline or across several lines.
String _read(String rel) =>
    File('lib/screens/$rel').readAsStringSync().replaceAll(RegExp(r'\s+'), '');

/// Assert a 48x48 constraint appears in the window of source following [anchor].
void _expectMin48After(String content, String anchor, {int window = 300}) {
  final i = content.indexOf(anchor);
  expect(i, greaterThanOrEqualTo(0), reason: 'anchor "$anchor" not found');
  final slice = content.substring(i, (i + window).clamp(0, content.length));
  expect(slice.contains(_min48), isTrue,
      reason: 'no >=48dp tap-target constraint near "$anchor"');
}

void main() {
  group('compact IconButtons keep a >=48dp tap target', () {
    test('routes_screen cloud-sync button', () {
      // Reason: the header cloud-sync IconButton carries VisualDensity.compact;
      // without an explicit 48dp constraint it renders ~40dp (WCAG 2.5.8 #255).
      _expectMin48After(_read('routes_screen.dart'), 'l10n.routesSyncFromCloud');
    });

    test('route_detail report-review flag button', () {
      // Reason: the report-review flag button shipped with an empty
      // BoxConstraints(); it must keep the explicit 48x48 (WCAG 2.5.8 #255).
      _expectMin48After(
          _read('route_detail_screen.dart'), 'l10n.routeDetailReportReview');
    });

    test('routes_heatmap pin button', () {
      // Reason: the compact pin IconButton must not regress below 48dp (#255).
      _expectMin48After(_read('routes_heatmap_screen.dart'), 'trailing:IconButton(');
    });

    test('runs_screen nav chevrons (both)', () {
      // Reason: both period-nav chevrons used a sub-48dp tightFor(32, 32); they
      // must stay >=48dp and never revert to the tight constraint (#255).
      final c = _read('runs_screen.dart');
      _expectMin48After(c, 'Icons.chevron_left');
      _expectMin48After(c, 'Icons.chevron_right');
      // The old tight 32x32 constraint must be gone from the nav group.
      final navStart = c.indexOf('Icons.chevron_left');
      final navEnd = (c.indexOf('Icons.chevron_right') + 300).clamp(0, c.length);
      expect(c.substring(navStart, navEnd),
          isNot(contains('tightFor(width:32,height:32)')),
          reason: 'nav chevrons reverted to the sub-48dp tightFor(32, 32)');
    });
  });
}

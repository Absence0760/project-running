// Source-scan guard for issue #666 C6: every sub-surface tab strip in the app
// is one strip. Four screens built their own `TabBar` and disagreed on both of
// the flags that shape it — the fitness hub left `isScrollable` unset (46 dp,
// flush at x=0) while social, profile and club detail set it true (Material 3
// then defaults `TabAlignment.startOffset`, a 52 dp left indent), and social
// alone gave its tabs icons, which is the only reason a strip is 72 dp instead
// of 46. Switching between the two hubs moved the strip 26 dp vertically and
// the first tab 52 dp horizontally at the same time.
//
// `AppTabBar` (ui_kit) derives `isScrollable` from whether the labels fit at
// the current text scale, so the flag is no longer a per-screen choice, and it
// takes labels rather than `Tab`s so an icon cannot be smuggled back in.
//
// When this test fails: take `AppTabBar` rather than raising a count. A strip
// that genuinely needs something the shared one lacks is an argument to grow
// `AppTabBar`, since whatever it needs the other four will need next.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The screens that host a tab strip. Listed so a strip that is deleted or
/// moved has to be accounted for rather than quietly leaving the guard empty.
const _hosts = <String>[
  'lib/screens/fitness_hub_screen.dart',
  'lib/screens/social_screen.dart',
  'lib/screens/profile_screen.dart',
  'lib/screens/club_detail_screen.dart',
];

/// `profile` and `club_detail` reach the strip through the shared
/// hero-scrolls-away host rather than building it inline (decisions § 545), so
/// they satisfy the guard indirectly — and the host itself is guarded, so the
/// indirection cannot become an escape hatch.
const _stripHost = 'lib/widgets/collapsing_tab_host.dart';

/// A `TabBar(` construction. `TabBarView(` and `TabBarTheme(` must not match.
final _tabBar = RegExp(r'\bTabBar\(');

/// A `Tab(` construction — the widget that carries the optional icon.
final _tab = RegExp(r'(?<![A-Za-z_])Tab\(');

Iterable<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('every listed tab host still exists', () {
    for (final path in _hosts) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path is guarded but missing — if the strip moved, move the '
              'entry rather than dropping the guard');
    }
  });

  test('every tab host takes the shared strip', () {
    expect(File(_stripHost).readAsStringSync(), contains('AppTabBar('),
        reason: '$_stripHost stopped building the shared strip, so the screens '
            'that delegate to it have no strip at all');
    for (final path in _hosts) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains('AppTabBar(') || src.contains('CollapsingTabHost('),
        isTrue,
        reason: '$path builds its own tab strip',
      );
    }
  });

  test('no screen constructs a bare TabBar', () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_tabBar.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a hand-built TabBar picks isScrollable, and the two screens '
            'that picked it differently are what this closed — take AppTabBar '
            'instead:\n${offenders.join('\n')}');
  });

  test('no screen builds a Tab, so none can carry an icon', () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_tab.hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'an icon is what makes a strip 72 dp instead of 46, and the '
            'six-tab club-detail strip shows tab count does not earn it — '
            'pass labels to AppTabBar:\n${offenders.join('\n')}');
  });
}

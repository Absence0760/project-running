// Source-scan guard for issue #666 V8: a stat tile is `StatTile` (ui_kit) and
// the row it sits in is `StatGrid`. Twelve private classes drew the same
// value-over-label pair before this, and the drift between them was the
// defect: six value type sizes, two label sizes, two muted colours, and three
// different answers to "what happens when the value is too wide" — one of
// which (an intrinsically-sized cell in a `Row(spaceAround)`) had no answer at
// all and simply overflowed.
//
// Three rules:
//
//  * The set of remaining stat-named `StatelessWidget`s is CLOSED. Each entry
//    below is a documented non-tile, and the reason is part of the entry: a
//    thirteenth hand-rolled tile fails this test rather than passing review.
//  * The migrated surfaces must still REFERENCE `StatTile`, so the adoption
//    cannot be quietly undone one screen at a time.
//  * `StatTile` / `StatGrid` / `SectionHeader` are ui_kit names and may not be
//    redeclared locally — a local shadow would satisfy every rule above while
//    reopening the drift.
//
// When this test fails: use `StatTile.small` / `.medium` / `.large` inside a
// `StatGrid`, or add an entry here WITH the reason it is not a tile.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `path::ClassName` -> why it is not a `StatTile`.
///
/// Every one of these draws something a value-over-label tile cannot, and
/// forcing them in would mean the flag-per-caller widget that is the other
/// half of this defect.
const _notTiles = <String, String>{
  // A Card whose label sits ABOVE the value and which carries two further
  // sub-detail lines and a tap target — a card body, not a cell in a row.
  'lib/screens/dashboard_screen.dart::_PeriodStatCard':
      'label-above card with sub-detail lines and a tap target',
  // Start-aligned inside a feed card, with an uppercased label: the feed
  // card's own grammar, not the centred cell of a stat row.
  'lib/screens/feed_screen.dart::_Stat': 'start-aligned feed-card stat',
  // Label above the value inside a Card. One caller, so a `labelAbove` flag
  // on StatTile would serve exactly this screen.
  'lib/screens/recap_screen.dart::_StatCard': 'label-above card body',
  // A dismissible Card of inline label:value chips in a Wrap — a panel, and
  // its chips are not stacked pairs.
  'lib/screens/run_detail_screen.dart::_SegmentStatsCard':
      'dismissible chip panel, not a tile',
  // The frosted map overlay that COMPOSES StatTile.medium, plus a clock,
  // dividers and every recording control.
  'lib/screens/run_screen.dart::_StatsOverlay': 'overlay that composes tiles',
  // A clock and a hold-to-stop button — a bar, with no stat in it.
  'lib/screens/run_screen.dart::_CollapsedStatsBar': 'collapsed control bar',
  // Composes StatTile.large and adds the tap-for-explanation affordance; the
  // tile is the content, this is the gesture (#25, #267).
  'lib/widgets/fitness_card.dart::FitnessStat':
      'tile plus an explanation affordance',
  // A rasterised share card on a fixed dark canvas with hardcoded type and
  // colour — deliberately theme-free per § 482.
  'lib/widgets/route_share_card.dart::_Stat': 'rasterised share-card stat',
};

/// Surfaces that must go on referencing the shared tile.
const _mustUseStatTile = <String>[
  'lib/screens/run_detail_screen.dart',
  'lib/screens/run_screen.dart',
  'lib/screens/public_run_screen.dart',
  'lib/screens/public_route_screen.dart',
  'lib/screens/route_detail_screen.dart',
  'lib/screens/period_summary_screen.dart',
  'lib/widgets/fitness_card.dart',
];

/// `path::ClassName` -> why it is not a `SectionHeader`.
const _notSectionHeaders = <String, String>{
  // `titleMedium` heading of a block inside a scrolling body. A section TITLE
  // is a heading; SectionHeader is the uppercased eyebrow that names a list
  // group, and collapsing the two would need a kind flag.
  'lib/screens/dashboard_screen.dart::_SectionHeader':
      'titleMedium section title, not a list-group eyebrow',
};

Iterable<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// Stateless widget class declarations whose name matches [pattern], keyed
/// `path::ClassName`. `State` / `Status` / `Static` names are not stat tiles
/// and are filtered by the caller's pattern, not here.
Map<String, String> _declarations(RegExp pattern) {
  final found = <String, String>{};
  for (final file in _sources()) {
    for (final m in pattern.allMatches(file.readAsStringSync())) {
      found['${file.path}::${m.group(1)}'] = file.path;
    }
  }
  return found;
}

void main() {
  test('the set of hand-rolled stat widgets is closed', () {
    final pattern = RegExp(
        r'^class (_?[A-Za-z0-9]*Stat[A-Za-z0-9]*) extends StatelessWidget',
        multiLine: true);
    final found = _declarations(pattern).keys.where((k) {
      final name = k.split('::').last;
      return !name.contains('State') &&
          !name.contains('Status') &&
          !name.contains('Static');
    }).toSet();

    final undocumented = found.difference(_notTiles.keys.toSet());
    expect(undocumented, isEmpty,
        reason: 'new hand-rolled stat widget(s). Use StatTile.small/.medium/'
            '.large inside a StatGrid, or add an entry to _notTiles with the '
            'reason it is not a tile.');

    final stale = _notTiles.keys.toSet().difference(found);
    expect(stale, isEmpty,
        reason: 'these entries no longer exist — drop them from _notTiles so '
            'the list keeps naming real code.');
  });

  test('the migrated surfaces still reference the shared tile', () {
    for (final path in _mustUseStatTile) {
      final source = File(path).readAsStringSync();
      expect(source, contains('StatTile'),
          reason: '$path stopped using StatTile — a screen may not re-grow its '
              'own stat cell.');
    }
  });

  test('the set of hand-rolled section headers is closed', () {
    final found = _declarations(RegExp(
            r'^class (_?[A-Za-z0-9]*SectionHeader[A-Za-z0-9]*) extends StatelessWidget',
            multiLine: true))
        .keys
        .toSet();
    expect(found.difference(_notSectionHeaders.keys.toSet()), isEmpty,
        reason: 'new hand-rolled section header. Use SectionHeader (ui_kit) '
            'for a list-group eyebrow.');
    expect(_notSectionHeaders.keys.toSet().difference(found), isEmpty,
        reason: 'stale _notSectionHeaders entry');
  });

  test('the ui_kit names are never redeclared locally', () {
    for (final file in _sources()) {
      final source = file.readAsStringSync();
      for (final name in ['StatTile', 'StatGrid', 'SectionHeader']) {
        expect(source, isNot(contains('class $name ')),
            reason: '${file.path} shadows ui_kit\'s $name');
      }
    }
  });
}

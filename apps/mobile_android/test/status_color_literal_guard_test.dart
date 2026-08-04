// Source-scan guard for issue #666 V3: status-role colours come from the
// AppSemanticColors theme extension (packages/ui_kit), never from raw
// Tailwind/Material hex literals or the Colors.green / amber / red swatches.
// The extension's pairs are AA-guarded per brightness
// (app_semantic_colors_test.dart); a literal bypasses that guarantee and
// silently drifts from the palette in one theme or the other.
//
// Two kinds of exemption, both deliberately narrow:
//  * Whole-file: the share-card widgets rasterise to fixed-size PNGs for the
//    OS share sheet and do not follow the device theme by design
//    (docs/architecture/conventions.md § Mobile status colours).
//  * Scoped data palettes: chart/map DATA colours (pace ramp, heat scale,
//    HR-zone bands, map start/finish/drag markers, chart series) are not
//    status roles, so they keep their fixed hues — but each is pinned to an
//    exact occurrence count per file, so a new status-role literal added to
//    one of these files still fails.
//
// When this test fails: route the colour through
// AppSemanticColors.of(context) (or .ofTheme(theme)) instead of adding an
// allowlist entry. Only a genuine new DATA palette earns an entry here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _bannedHexes = [
  // greens
  '22C55E', '16A34A', '10B981', '34D399', '047857', '4CAF50',
  // ambers
  'F59E0B', 'FBBF24', 'EAB308', 'FACC15', 'D97706', 'FFC107',
  // reds
  'EF4444', 'DC2626', 'B91C1C', 'F87171', 'F44336',
  // crown gold
  'F5B30A',
];

// Rasterised share-card PNGs — theme-independent by design.
const _exemptFiles = {
  'lib/widgets/run_share_card.dart',
  'lib/widgets/route_share_card.dart',
  'lib/widgets/finisher_certificate_card.dart',
};

// file -> pattern -> exact expected occurrence count. Patterns are either a
// six-digit hex suffix from [_bannedHexes] or a Colors.<swatch> name.
const _dataPalettes = <String, Map<String, int>>{
  // 6-bucket pace ramp drawn over map tiles (slow -> fast).
  'lib/widgets/pace_segments.dart': {'EF4444': 1, 'FBBF24': 1, '10B981': 1},
  // Heat-density scale + its legend gradient.
  'lib/screens/run_heatmap_screen.dart': {
    '10B981': 2,
    'F59E0B': 2,
    'EF4444': 2,
  },
  // Heat-density dots + the featured map-pin ring.
  'lib/screens/routes_heatmap_screen.dart': {'Colors.red': 1, 'FACC15': 1},
  // Map-overlay markers: selected-segment highlight, coarse-position ring,
  // hover pointer (mirrors web RunMap.svelte).
  'lib/widgets/live_run_map.dart': {'F59E0B': 6},
  // Painted start/finish caps on the mini track preview.
  'lib/widgets/track_preview.dart': {'22C55E': 1, 'EF4444': 1},
  // Course start/finish checkpoint hues beside the kindSpec marker catalogue.
  'lib/screens/roadbook_screen.dart': {'22C55E': 1, 'EF4444': 1},
  // Waypoint pins on the builder map: start/end/drag states.
  'lib/screens/route_builder_screen.dart': {
    'Colors.amber': 3,
    'Colors.green': 2,
    'Colors.red': 1,
  },
  // HR-zone band palette (Z2/Z3/Z5).
  'lib/screens/run_detail_screen.dart': {
    '4CAF50': 1,
    'FFC107': 1,
    'F44336': 1,
  },
  // Intensity-zone band palette (z3).
  'lib/widgets/intensity_card.dart': {'F59E0B': 1},
  // CTL/ATL/TSB chart series hues (legend + painter).
  'lib/widgets/training_load_chart.dart': {'F59E0B': 2, 'EF4444': 1},
};

final _hexPattern = RegExp(
  '0x[0-9A-Fa-f]{2}(${_bannedHexes.join('|')})',
  caseSensitive: false,
);
final _swatchPattern = RegExp(r'Colors\.(green|amber|red)\b');

void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('exempt share-card files still exist at their allowlisted paths', () {
    for (final path in _exemptFiles) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path is allowlisted but missing — if it moved, move the '
              'allowlist entry with it so the exemption stays scoped.');
    }
  });

  test('no status hex literal or status Material swatch outside the '
      'allowlists', () {
    final violations = <String>[];
    for (final file in dartFiles) {
      final relPath = file.path;
      if (_exemptFiles.contains(relPath)) continue;
      final source = file.readAsStringSync();
      final allowed = _dataPalettes[relPath] ?? const <String, int>{};
      final seen = <String, int>{};
      final lines = source.split('\n');
      final hits = <String, List<int>>{};
      for (var i = 0; i < lines.length; i++) {
        for (final m in _hexPattern.allMatches(lines[i])) {
          final key = m.group(1)!.toUpperCase();
          seen[key] = (seen[key] ?? 0) + 1;
          (hits[key] ??= []).add(i + 1);
        }
        for (final m in _swatchPattern.allMatches(lines[i])) {
          final key = 'Colors.${m.group(1)!}';
          seen[key] = (seen[key] ?? 0) + 1;
          (hits[key] ??= []).add(i + 1);
        }
      }
      for (final entry in seen.entries) {
        final expected = allowed[entry.key] ?? 0;
        if (entry.value != expected) {
          violations.add('$relPath: ${entry.key} x${entry.value} '
              '(allowed $expected) at lines ${hits[entry.key]!.join(', ')}');
        }
      }
      for (final entry in allowed.entries) {
        if (!seen.containsKey(entry.key)) {
          violations.add('$relPath: allowlist expects ${entry.key} '
              'x${entry.value} but found none — palette migrated? Remove '
              'the entry.');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'Status-role colour literals must go through '
            'AppSemanticColors (success/warning/danger/crown + on*). '
            'Violations:\n${violations.join('\n')}');
  });
}

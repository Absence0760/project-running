import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep arch guards for the route-detail screen polish round.
/// Pins the visible UX changes so a refactor that reverts to the
/// buried-at-bottom layout fails loud:
///
///   1. "Start run" is a FloatingActionButton (always reachable)
///      — not a `FilledButton` at the end of a 700-line ListView.
///   2. The diagnostic `MissingMapTilesHint` is mounted under the
///      map so the "still not seeing the map" failure mode is
///      diagnosable from the device.
///   3. Description has a "Description" heading + matched typography
///      with the rest of the screen.
///   4. Surface / run-count / featured metadata uses the new
///      `_MetaChip` pill shape, not the old centered `_inlineMeta`
///      mini-text row.
void main() {
  group('route_detail_screen — polish round (source-grep)', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/route_detail_screen.dart').readAsStringSync();
    });

    test(
        'Start run is a FloatingActionButton, gated on '
        '`_displayWaypoints.length >= 2`',
        () {
      // Pre-polish, Start Run lived at the END of the ListView —
      // after every detail panel. The FAB is the right Material
      // shape for the primary action; pin it so a refactor that
      // re-buries it fails this test.
      expect(
        src.contains('floatingActionButton: canStartRun'),
        isTrue,
        reason: 'Start Run must be the Scaffold FAB, not an inline '
            'FilledButton.',
      );
      expect(
        src.contains('FloatingActionButton.extended('),
        isTrue,
        reason: 'Must use the labelled (.extended) variant so the '
            'green "play" CTA reads as the primary action.',
      );
      expect(
        src.contains("heroTag: 'route_detail_start_run'"),
        isTrue,
        reason: 'heroTag pinned so a second Scaffold with another '
            'FAB on the navigation stack can\'t collide.',
      );
      expect(
        src.contains('canStartRun = _displayWaypoints.length >= 2'),
        isTrue,
        reason: 'FAB must hide when there\'s no polyline to run — '
            'clipped-to-empty privacy outcome shouldn\'t offer the '
            'CTA.',
      );
    });

    test(
        'the OLD bottom-of-scroll Start Run FilledButton is REMOVED '
        '(no duplicate CTA)',
        () {
      // Negative assertion: the old "Start run with this route"
      // bottom-button must NOT exist anywhere — it would render
      // a second CTA stacked under the FAB.
      expect(
        src.contains("'Start run with this route'"),
        isFalse,
        reason: 'The old bottom-of-list "Start run with this route" '
            'FilledButton must be removed — leaving it duplicates '
            'the FAB and visually competes with it.',
      );
    });

    test(
        'MissingMapTilesHint is mounted under the LiveRunMap — '
        'diagnoses the "still not seeing the map" failure mode',
        () {
      expect(
        src.contains("import '../widgets/missing_map_tiles_hint.dart'"),
        isTrue,
        reason: 'route_detail must import the diagnostic widget.',
      );
      expect(
        src.contains('const MissingMapTilesHint(),'),
        isTrue,
        reason: 'The widget must be mounted in the build tree '
            '(no envKeyPresentOverride passed → it probes dotenv).',
      );
    });

    test(
        'description section uses a "Description" heading + structured '
        'Column (not just a bare paragraph)',
        () {
      expect(
        src.contains('routeDetailDescriptionHeading'),
        isTrue,
        reason: 'Description block must have a label heading so it '
            'reads as a deliberate section.',
      );
    });

    test(
        'surface / run-count / featured row uses the new _MetaChip '
        'pill shape — not the old _inlineMeta centered mini-row',
        () {
      expect(
        src.contains('class _MetaChip'),
        isTrue,
        reason: 'New _MetaChip widget must exist — visual parity '
            'with the routes-list pills.',
      );
      // Old helper must be gone — dead code removal.
      expect(
        src.contains('_inlineMeta('),
        isFalse,
        reason: 'Old `_inlineMeta` helper must be removed; its '
            'only callers were replaced by _MetaChip.',
      );
    });

    test(
        'bottom-of-list trailing padding (88 px) leaves room for the '
        'FAB to float above the last review card',
        () {
      // Without trailing padding, the FAB sits on top of the last
      // review card. 88 px clears a standard FAB.extended height +
      // 16 px breathing room.
      expect(
        src.contains('const SizedBox(height: 88)'),
        isTrue,
        reason: 'Bottom-of-scroll padding must clear the FAB.',
      );
    });
  });
}

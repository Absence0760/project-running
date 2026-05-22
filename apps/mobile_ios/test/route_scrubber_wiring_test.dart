import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-grep arch guards for the route-direction scrubber wiring
/// on `route_detail_screen.dart`. The scrubber widget is private
/// to that screen so a unit-level pump would require either
/// `@visibleForTesting` exposure or a full screen-pump with a
/// seeded route — disproportionate to the wiring contract. Source-
/// grep matches the same pattern used for the verified-badge +
/// route-builder wiring guards.
///
/// These pin:
///   1. `_RoutePreviewScrubber` exists in the file.
///   2. It's rendered conditionally (≥ 2 waypoints) — degenerate /
///      privacy-clipped routes don't show a useless slider.
///   3. The state generation counter + `_scrubFraction` /
///      `_scrubbing` fields are present.
///   4. The interpolated position is fed to `LiveRunMap` via the
///      `previewPosition` prop ONLY while `_scrubbing` is true.
///   5. `interpolateAlongRoute` (the pure helper) is imported from
///      `route_geometry.dart`.
void main() {
  group('route_detail_screen — scrubber wiring (source-grep)', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/route_detail_screen.dart').readAsStringSync();
    });

    test('imports interpolateAlongRoute from the pure helper module', () {
      expect(
        src.contains(
            "import '../route_geometry.dart' show interpolateAlongRoute"),
        isTrue,
        reason: 'Scrubber must use the parity-paired pure helper '
            '(twin of web `route_geometry.ts`) — not an ad-hoc '
            'inline interpolation.',
      );
    });

    test('state fields _scrubFraction (double) + _scrubbing (bool) exist',
        () {
      expect(
        src.contains('double _scrubFraction = 0.0'),
        isTrue,
        reason: '_scrubFraction must be a double, default 0.0 — pins '
            'the start-of-route initial position.',
      );
      expect(
        src.contains('bool _scrubbing = false'),
        isTrue,
        reason: '_scrubbing must be a bool, default false — the '
            'preview marker mounts ONLY while this is true so '
            'releasing the thumb fades back to the static view.',
      );
    });

    test(
        '_RoutePreviewScrubber widget class exists in the same file '
        '(private to the screen)',
        () {
      expect(
        src.contains('class _RoutePreviewScrubber'),
        isTrue,
        reason: 'Scrubber widget must live in the screen file as a '
            'private class — keeps the scrubber-state surface '
            'narrow.',
      );
    });

    test(
        'scrubber is mounted ONLY when waypoints.length >= 2 — '
        'clipped / degenerate routes hide it',
        () {
      expect(
        src.contains('_displayWaypoints.length >= 2'),
        isTrue,
        reason: 'Without this guard, a single-point / empty '
            '_displayWaypoints route would render a useless slider.',
      );
      expect(
        src.contains('_RoutePreviewScrubber('),
        isTrue,
        reason: 'Scrubber widget must be instantiated below the map.',
      );
    });

    test(
        'preview marker fed to LiveRunMap is gated on _scrubbing — '
        'released thumb returns to static view',
        () {
      expect(
        src.contains('previewPosition: _scrubbing'),
        isTrue,
        reason: 'LiveRunMap.previewPosition must be conditionally '
            'set on _scrubbing so the marker fades out on release. '
            'Pre-fix, a single drag would leave a sticky pulse on '
            'the polyline indefinitely.',
      );
      expect(
        src.contains('interpolateAlongRoute('),
        isTrue,
        reason: 'The interpolated position must come from '
            'interpolateAlongRoute(_displayWaypoints, _scrubFraction).',
      );
    });

    test(
        '_RoutePreviewScrubber surfaces onChangeStart / onChanged / '
        'onChangeEnd callbacks — mirrors Material Slider semantics',
        () {
      expect(src.contains('onChangeStart'), isTrue);
      expect(src.contains('onChanged'), isTrue);
      expect(src.contains('onChangeEnd'), isTrue);
    });

    test(
        'scrubber readout uses UnitFormat.distance (km/mi-aware) — '
        'not a hardcoded km suffix',
        () {
      // Without this, a mi-preferring user would see "5.0 km" while
      // the route stats above show "3.1 mi". The same UnitFormat
      // helper drives both surfaces.
      expect(
        src.contains('UnitFormat.distance(reachedM, unit)'),
        isTrue,
        reason: 'Live distance readout must honour the user\'s '
            'unit preference.',
      );
    });
  });

  group('LiveRunMap — previewPosition prop wiring', () {
    late String src;
    setUpAll(() {
      src = File('lib/widgets/live_run_map.dart').readAsStringSync();
    });

    test('exposes the previewPosition prop', () {
      expect(
        src.contains('final Waypoint? previewPosition'),
        isTrue,
        reason: 'previewPosition must be a nullable Waypoint — '
            'null clears the marker, non-null mounts it.',
      );
      expect(src.contains('this.previewPosition'), isTrue);
    });

    test(
        'preview-marker MarkerLayer is gated on '
        '`widget.previewPosition != null`',
        () {
      expect(
        src.contains('widget.previewPosition != null'),
        isTrue,
        reason: 'Without the null guard the MarkerLayer would crash '
            'when previewPosition is unset (LatLng(null.lat, ...)).',
      );
      // Pin the marker has its own ValueKey so flutter_map doesn't
      // merge it with the hover marker.
      expect(
        src.contains("ValueKey('route-preview-runner')"),
        isTrue,
        reason: 'Distinct ValueKey so the scrubber + chart-hover '
            'markers can coexist without one stealing the other.',
      );
    });
  });
}

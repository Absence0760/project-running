import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/route_geometry.dart' show markerPointAtDistance;
import '../lib/widgets/route_markers_panel.dart';

RouteMarkerRow _marker({
  required String id,
  required String kind,
  required String label,
  double? positionM,
  String userId = 'owner-1',
  Map<String, dynamic> meta = const {},
}) {
  return RouteMarkerRow(
    id: id,
    routeId: 'route-1',
    userId: userId,
    kind: kind,
    label: label,
    lat: 51.5,
    lng: -0.12,
    positionM: positionM,
    meta: meta,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}

/// The 1 km west→east segment then a north leg from `route_snap_test.dart`.
/// A point at (lng -0.11, lat 51.502) snaps down onto (lng -0.11, lat 51.5).
const _routeLine = <Waypoint>[
  Waypoint(lat: 51.5, lng: -0.12),
  Waypoint(lat: 51.5, lng: -0.1),
  Waypoint(lat: 51.51, lng: -0.1),
];

class _MarkersApi extends ApiClient {
  double? addedLat;
  double? addedLng;
  int addCalls = 0;
  double? updatedLat;
  double? updatedLng;
  int updateCalls = 0;

  @override
  String? get userId => 'owner-1';

  @override
  Future<List<RouteMarkerRow>> fetchRouteMarkers(String routeId) async =>
      const [];

  @override
  Future<RouteMarkerRow> addRouteMarker({
    required String routeId,
    required String kind,
    required String label,
    required double lat,
    required double lng,
    Map<String, dynamic> meta = const {},
  }) async {
    addCalls++;
    addedLat = lat;
    addedLng = lng;
    return _marker(id: 'new', kind: kind, label: label);
  }

  @override
  Future<void> updateRouteMarker(
    String id, {
    String? kind,
    String? label,
    double? lat,
    double? lng,
    Map<String, dynamic>? meta,
  }) async {
    updateCalls++;
    updatedLat = lat;
    updatedLng = lng;
  }
}

/// Marker add blocks on a gate the test controls, to observe the save spinner.
class _BlockingMarkersApi extends ApiClient {
  final Completer<void> gate = Completer<void>();

  @override
  String? get userId => 'owner-1';

  @override
  Future<List<RouteMarkerRow>> fetchRouteMarkers(String routeId) async =>
      const [];

  @override
  Future<RouteMarkerRow> addRouteMarker({
    required String routeId,
    required String kind,
    required String label,
    required double lat,
    required double lng,
    Map<String, dynamic> meta = const {},
  }) async {
    await gate.future;
    return _marker(id: 'new', kind: kind, label: label);
  }
}

Widget _host({
  required bool isOwner,
  required List<RouteMarkerRow> markers,
  ApiClient? api,
  GlobalKey<RouteMarkersPanelState>? panelKey,
  List<Waypoint> routeLine = const [],
  String? viewerId = 'owner-1',
  String? routeOwnerId = 'owner-1',
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RouteMarkersPanel(
          key: panelKey,
          api: api,
          routeId: 'route-1',
          isOwner: isOwner,
          viewerId: viewerId,
          routeOwnerId: routeOwnerId,
          routeLine: routeLine,
          initialMarkers: markers,
          onPinsChanged: (_) {},
          onPlacingChanged: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the schedule with kind labels + detail lines', (tester) async {
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: [
        _marker(
          id: 'm1',
          kind: 'cutoff',
          label: 'Gate',
          positionM: 300,
          meta: {'cutoff_clock': '14:30'},
        ),
        _marker(
          id: 'm2',
          kind: 'aid_station',
          label: 'Aid 2',
          positionM: 1500,
          meta: {
            'services': ['water', 'food']
          },
        ),
      ],
    ));
    await tester.pump();

    expect(find.text('Course markers'), findsOneWidget);
    expect(find.text('Gate'), findsOneWidget);
    expect(find.text('Aid 2'), findsOneWidget);
    // Kind + detail are joined into one line per row.
    expect(find.textContaining('Cut-off 14:30'), findsOneWidget);
    expect(find.textContaining('Water · Food'), findsOneWidget);

    // Owner gets add + per-row edit/delete affordances.
    expect(find.text('Add marker'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNWidgets(2));
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  testWidgets(
      'long label and note-detail line are truncated so the row cannot grow '
      'into a wall of text', (tester) async {
    const longLabel =
        'Aid Station 7 — Emigrant Pass Ridge Crest Water and Electrolyte '
        'Refill with Medical Tent and Drop Bags';
    const longNote =
        'A very long free-text note that a viewer typed which, without a '
        'maxLines cap, would wrap into a wall of text and shove the edit and '
        'delete buttons off the visible row on a phone.';
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: [
        _marker(
          id: 'm1',
          kind: 'note',
          label: longLabel,
          positionM: 500,
          meta: {'note': longNote},
        ),
      ],
    ));
    await tester.pump();

    final label = tester.widget<Text>(find.text(longLabel));
    expect(label.maxLines, 1,
        reason: 'A long marker label must clip to one line, not wrap.');
    expect(label.overflow, TextOverflow.ellipsis);

    final detail = tester.widget<Text>(find.textContaining(longNote));
    expect(detail.maxLines, 2,
        reason: 'A long note detail line must cap at two lines.');
    expect(detail.overflow, TextOverflow.ellipsis);
  });

  testWidgets(
      'non-owner viewer: owner markers are read-only + badged, own markers '
      'editable, and they can add their own', (tester) async {
    await tester.pumpWidget(_host(
      isOwner: false,
      viewerId: 'viewer-2',
      routeOwnerId: 'owner-1',
      markers: [
        // The route owner's OFFICIAL marker — read-only + badged.
        _marker(
            id: 'm1',
            kind: 'aid_station',
            label: 'Official aid',
            positionM: 500,
            userId: 'owner-1'),
        // The viewer's OWN personal overlay — editable.
        _marker(
            id: 'm2',
            kind: 'note',
            label: 'My note',
            positionM: 800,
            userId: 'viewer-2'),
      ],
    ));
    await tester.pump();

    expect(find.text('Official aid'), findsOneWidget);
    expect(find.text('My note'), findsOneWidget);

    // A signed-in non-owner can add their own markers.
    expect(find.text('Add marker'), findsOneWidget);

    // Only the viewer's own marker carries edit/delete; the owner's is
    // read-only and badged as the route owner's.
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('Route owner'), findsOneWidget);
  });

  testWidgets('signed-out viewer sees the schedule but cannot add or edit',
      (tester) async {
    await tester.pumpWidget(_host(
      isOwner: false,
      viewerId: null,
      routeOwnerId: 'owner-1',
      markers: [
        _marker(id: 'm1', kind: 'aid_station', label: 'Aid 1', positionM: 500),
      ],
    ));
    await tester.pump();

    expect(find.text('Aid 1'), findsOneWidget);
    expect(find.text('Add marker'), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('empty state renders when there are no markers', (tester) async {
    await tester.pumpWidget(_host(isOwner: true, markers: const []));
    await tester.pump();
    expect(
      find.textContaining('No course markers yet'),
      findsOneWidget,
    );
  });

  testWidgets('snap ON places a tapped-off-route marker on the route line',
      (tester) async {
    final api = _MarkersApi();
    final key = GlobalKey<RouteMarkersPanelState>();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: const [],
      api: api,
      panelKey: key,
      routeLine: _routeLine,
    ));
    await tester.pump();

    // Enter placing mode — the snap toggle appears (default on).
    await tester.tap(find.text('Add marker'));
    await tester.pump();
    expect(find.text('Snap to route line'), findsOneWidget);

    // Tap ~222 m north of the horizontal first leg.
    key.currentState!.placeAt(const Waypoint(lat: 51.502, lng: -0.11));
    await tester.pumpAndSettle();

    // Fill the name field and save.
    await tester.enterText(find.byType(TextField).first, 'Aid 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.addCalls, 1);
    // Snapped onto the line: lat pulled to 51.5, lng unchanged.
    expect((api.addedLat! - 51.5).abs() < 1e-6, isTrue,
        reason: 'lat ${api.addedLat}');
    expect((api.addedLng! - -0.11).abs() < 1e-6, isTrue,
        reason: 'lng ${api.addedLng}');

    // Drain the "tap to place" banner timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('marker save shows a progress bar while the add is in flight',
      (tester) async {
    final api = _BlockingMarkersApi();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: const [],
      api: api,
      routeLine: _routeLine,
    ));
    await tester.pump();

    await tester.tap(find.text('Add marker'));
    await tester.pump();
    await tester.tap(find.text('Enter location instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Aid');
    await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'), '51.502');
    await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'), '-0.11');

    await tester.tap(find.text('Save'));
    // Let the sheet close; the add then starts and blocks on the gate.
    // (No pumpAndSettle — the indeterminate progress bar never settles.)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LinearProgressIndicator), findsOneWidget,
        reason: 'a save in flight must show progress');

    // Completing the add clears the spinner.
    api.gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // Drain the "Tap to place" banner auto-dismiss timer from _startAdd.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
  });

  testWidgets('typed coordinates create a marker without any map tap',
      (tester) async {
    final api = _MarkersApi();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: const [],
      api: api,
      routeLine: _routeLine,
    ));
    await tester.pump();

    await tester.tap(find.text('Add marker'));
    await tester.pump();
    await tester.tap(find.text('Enter location instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Typed aid');
    await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'), '51.502');
    await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'), '-0.11');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.addCalls, 1);
    expect((api.addedLat! - 51.502).abs() < 1e-6, isTrue,
        reason: 'lat ${api.addedLat}');
    expect((api.addedLng! - -0.11).abs() < 1e-6, isTrue,
        reason: 'lng ${api.addedLng}');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('out-of-range typed coordinates block the save', (tester) async {
    final api = _MarkersApi();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: const [],
      api: api,
      routeLine: _routeLine,
    ));
    await tester.pump();

    await tester.tap(find.text('Add marker'));
    await tester.pump();
    await tester.tap(find.text('Enter location instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Bad');
    await tester.enterText(find.widgetWithText(TextField, 'Latitude'), '999');
    await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'), '-0.11');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(api.addCalls, 0);
    expect(
      find.text(
          'Enter a valid latitude (-90 to 90) and longitude (-180 to 180).'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'editing prefills coordinates and a typed change moves the marker',
      (tester) async {
    final api = _MarkersApi();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: [
        _marker(id: 'm1', kind: 'aid_station', label: 'Aid 1', positionM: 500),
      ],
      api: api,
      routeLine: _routeLine,
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    final latField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Latitude'));
    final lngField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Longitude'));
    expect(latField.controller!.text, '51.5');
    expect(lngField.controller!.text, '-0.12');

    await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'), '51.507');
    await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'), '-0.125');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.updateCalls, 1);
    expect((api.updatedLat! - 51.507).abs() < 1e-6, isTrue,
        reason: 'lat ${api.updatedLat}');
    expect((api.updatedLng! - -0.125).abs() < 1e-6, isTrue,
        reason: 'lng ${api.updatedLng}');
  });

  testWidgets('snap OFF places the marker at the raw tapped point',
      (tester) async {
    final api = _MarkersApi();
    final key = GlobalKey<RouteMarkersPanelState>();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: const [],
      api: api,
      panelKey: key,
      routeLine: _routeLine,
    ));
    await tester.pump();

    await tester.tap(find.text('Add marker'));
    await tester.pump();
    // Disable snapping.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    key.currentState!.placeAt(const Waypoint(lat: 51.502, lng: -0.11));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Aid 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(api.addCalls, 1);
    // Raw tapped coordinate — no projection onto the line.
    expect((api.addedLat! - 51.502).abs() < 1e-6, isTrue,
        reason: 'lat ${api.addedLat}');
    expect((api.addedLng! - -0.11).abs() < 1e-6, isTrue,
        reason: 'lng ${api.addedLng}');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('placing by distance along the route creates a marker',
      (tester) async {
    final api = _MarkersApi();
    await tester.pumpWidget(_host(
      isOwner: true,
      markers: const [],
      api: api,
      routeLine: _routeLine,
    ));
    await tester.pump();

    await tester.tap(find.text('Add marker'));
    await tester.pump();
    await tester.tap(find.text('Enter location instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'By distance');
    // No Preferences registered in the host-test runner → km. 0.5 km = 500 m.
    await tester.enterText(
        find.widgetWithText(TextField, 'Distance along route'), '0.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final expected = markerPointAtDistance(_routeLine, 500)!;
    expect(api.addCalls, 1);
    expect((api.addedLat! - expected.lat).abs() < 1e-6, isTrue,
        reason: 'lat ${api.addedLat} vs ${expected.lat}');
    expect((api.addedLng! - expected.lng).abs() < 1e-6, isTrue,
        reason: 'lng ${api.addedLng} vs ${expected.lng}');
    // 500 m sits on the first (horizontal) leg, so latitude stays put.
    expect((api.addedLat! - 51.5).abs() < 1e-6, isTrue);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  group('parseDistanceAlong', () {
    test('parses a km value into metres', () {
      expect(parseDistanceAlong('0.5', unit: DistanceUnit.km), 500);
      expect(parseDistanceAlong('5', unit: DistanceUnit.km), 5000);
      expect(parseDistanceAlong('0', unit: DistanceUnit.km), 0);
    });

    test('parses a mile value into metres', () {
      expect(parseDistanceAlong('1', unit: DistanceUnit.mi), kMetresPerMile);
      final five = parseDistanceAlong('5', unit: DistanceUnit.mi)!;
      expect((five - 5 * kMetresPerMile).abs() < 1e-6, isTrue);
    });

    test('rejects junk, negatives, and non-finite', () {
      expect(parseDistanceAlong('', unit: DistanceUnit.km), isNull);
      expect(parseDistanceAlong('abc', unit: DistanceUnit.km), isNull);
      expect(parseDistanceAlong('-3', unit: DistanceUnit.km), isNull);
    });
  });

  group('markerPointAtDistance', () {
    const line = <Waypoint>[
      Waypoint(lat: 51.5, lng: -0.12),
      Waypoint(lat: 51.5, lng: -0.10),
      Waypoint(lat: 51.51, lng: -0.10),
    ];

    test('needs a real line', () {
      expect(markerPointAtDistance(const [], 100), isNull);
      expect(markerPointAtDistance(
          const [Waypoint(lat: 51.5, lng: -0.12)], 100), isNull);
    });

    test('distance 0 snaps to the start', () {
      final wp = markerPointAtDistance(line, 0)!;
      expect((wp.lat - 51.5).abs() < 1e-9, isTrue);
      expect((wp.lng - -0.12).abs() < 1e-9, isTrue);
    });

    test('an over-long distance clamps to the end', () {
      final wp = markerPointAtDistance(line, 1e9)!;
      expect((wp.lat - 51.51).abs() < 1e-6, isTrue);
      expect((wp.lng - -0.10).abs() < 1e-6, isTrue);
    });

    test('a mid distance lands on the line', () {
      final wp = markerPointAtDistance(line, 500)!;
      // 500 m is within the first horizontal leg — latitude unchanged, and
      // longitude advances east of the start.
      expect((wp.lat - 51.5).abs() < 1e-6, isTrue);
      expect(wp.lng > -0.12 && wp.lng < -0.10, isTrue);
    });
  });

  group('parseMarkerElapsed / formatMarkerElapsed', () {
    test('accepts h:mm:ss, mm:ss, and bare minutes', () {
      expect(parseMarkerElapsed('1:45:00'), 6300);
      expect(parseMarkerElapsed('25:00'), 1500);
      expect(parseMarkerElapsed('90'), 5400);
    });

    test('two-part input prefers h:mm when the marker position makes it '
        'the plausible pace', () {
      // 4:30 at an 80 km aid station: 4 h 30 is ~202 s/km — plausible.
      expect(parseMarkerElapsed('4:30', positionM: 80000), 16200);
      // 25:00 at 4.6 km: 25 hours is absurd, 25 minutes is ~326 s/km.
      expect(parseMarkerElapsed('25:00', positionM: 4600), 1500);
      // No position (a marker not yet placed on the line): mm:ss.
      expect(parseMarkerElapsed('4:30'), 270);
    });

    test('rejects junk, negatives, and zero', () {
      expect(parseMarkerElapsed(''), isNull);
      expect(parseMarkerElapsed('abc'), isNull);
      expect(parseMarkerElapsed('1:2:3:4'), isNull);
      expect(parseMarkerElapsed('0'), isNull);
      expect(parseMarkerElapsed('-5'), isNull);
    });

    test('format round-trips through parse', () {
      expect(formatMarkerElapsed(6300), '1:45:00');
      expect(formatMarkerElapsed(1500), '25:00');
      expect(parseMarkerElapsed(formatMarkerElapsed(6300)), 6300);
      expect(parseMarkerElapsed(formatMarkerElapsed(1500)), 1500);
    });
  });

  group('formatElapsedDigits (target-time input mask)', () {
    test('fills from the right into m:ss / h:mm:ss', () {
      expect(formatElapsedDigits(''), '');
      expect(formatElapsedDigits('4'), '0:04');
      expect(formatElapsedDigits('43'), '0:43');
      expect(formatElapsedDigits('430'), '4:30');
      expect(formatElapsedDigits('2500'), '25:00');
      expect(formatElapsedDigits('14500'), '1:45:00');
      expect(formatElapsedDigits('430000'), '43:00:00');
    });

    test('strips non-digits so an already-formatted value re-masks cleanly', () {
      expect(formatElapsedDigits('abc'), '');
      // The prefill (formatMarkerElapsed output) round-trips unchanged.
      expect(formatElapsedDigits('1:45:00'), '1:45:00');
      expect(formatElapsedDigits('25:00'), '25:00');
      expect(formatElapsedDigits('0:43'), '0:43');
    });

    test('caps at six digits (drops the oldest) so hours stay two-digit', () {
      expect(formatElapsedDigits('12345678'), '34:56:78');
    });

    test('the masked value parses back to the intended seconds', () {
      expect(parseMarkerElapsed(formatElapsedDigits('2500')), 1500);
      expect(parseMarkerElapsed(formatElapsedDigits('14500')), 6300);
    });
  });

  group('formatClockDigits (cut-off HH:MM input mask)', () {
    test('fills from the left, inserting the colon after two digits', () {
      expect(formatClockDigits(''), '');
      expect(formatClockDigits('1'), '1');
      expect(formatClockDigits('14'), '14');
      expect(formatClockDigits('143'), '14:3');
      expect(formatClockDigits('1430'), '14:30');
    });

    test('strips non-digits and caps at four digits', () {
      expect(formatClockDigits('14:30'), '14:30');
      expect(formatClockDigits('091530'), '15:30');
    });
  });

  test(
      '_openEditor opens the marker sheet with useSafeArea so its Save button '
      'clears the system nav bar', () {
    final source =
        File('lib/widgets/route_markers_panel.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _openEditor(');
    expect(start, isNonNegative,
        reason: '_openEditor not found in route_markers_panel.dart');
    // Scope to the editor-open call, ahead of the save dispatch.
    final end = source.indexOf('if (result == null) return;', start);
    expect(end, greaterThan(start));
    final openEditor = source.substring(start, end);
    expect(openEditor.contains('showModalBottomSheet<_MarkerDraft>'), isTrue);
    // Without useSafeArea the scroll-controlled sheet extends under the
    // Samsung system nav bar and the Save button is occluded, so the tap
    // misses and "Save does nothing". isScrollControlled must stay for the
    // keyboard room.
    expect(openEditor.contains('useSafeArea: true'), isTrue,
        reason: 'the marker-editor bottom sheet must pass useSafeArea: true');
    expect(openEditor.contains('isScrollControlled: true'), isTrue);
  });
}

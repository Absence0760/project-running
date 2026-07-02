import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/route_markers_panel.dart';

RouteMarkerRow _marker({
  required String id,
  required String kind,
  required String label,
  double? positionM,
  Map<String, dynamic> meta = const {},
}) {
  return RouteMarkerRow(
    id: id,
    routeId: 'route-1',
    userId: 'owner-1',
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
}

Widget _host({
  required bool isOwner,
  required List<RouteMarkerRow> markers,
  ApiClient? api,
  GlobalKey<RouteMarkersPanelState>? panelKey,
  List<Waypoint> routeLine = const [],
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

  testWidgets('non-owner sees the schedule but no edit affordances', (tester) async {
    await tester.pumpWidget(_host(
      isOwner: false,
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
}

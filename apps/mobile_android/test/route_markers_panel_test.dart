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

Widget _host({required bool isOwner, required List<RouteMarkerRow> markers}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RouteMarkersPanel(
          api: null,
          routeId: 'route-1',
          isOwner: isOwner,
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
}

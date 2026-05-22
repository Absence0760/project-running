import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/preferences.dart';
import '../lib/screens/route_picker_screen.dart';

cm.Route _route(
  String id,
  String name, {
  bool starred = false,
  double distanceM = 5000,
}) =>
    cm.Route(
      id: id,
      userId: 'test-user',
      name: name,
      waypoints: const [
        cm.Waypoint(lat: 51.5, lng: -0.12),
        cm.Waypoint(lat: 51.51, lng: -0.13),
      ],
      distanceMetres: distanceM,
      elevationGainMetres: 50,
      isStarred: starred,
    );

Future<void> _pump(WidgetTester tester, List<cm.Route> routes) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RoutePickerScreen(
        routes: routes,
        unit: DistanceUnit.km,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RoutePickerScreen', () {
    testWidgets(
      'opens as a full-screen page with an AppBar — NOT a modal '
      'bottom sheet (user-requested layout change)',
      (tester) async {
        await _pump(tester, [_route('a', 'Alpha')]);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Choose route'), findsOneWidget);
        // "No route" lives as a trailing AppBar action.
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('No route'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'starred routes sort BEFORE non-starred — and a STARRED + ALL '
      'ROUTES section header pair frames them',
      (tester) async {
        // Mixed list: order in input is alpha-by-name but should
        // re-sort so starred routes lead.
        await _pump(tester, [
          _route('a', 'Alpha'),
          _route('b', 'Bravo', starred: true),
          _route('c', 'Charlie'),
          _route('d', 'Delta', starred: true),
        ]);
        // Section headers are visible (user-requested starred-first
        // visual grouping).
        expect(find.text('STARRED'), findsOneWidget);
        expect(find.text('ALL ROUTES'), findsOneWidget);

        // Order of the rendered ListTile titles. Bravo + Delta
        // (starred) come first, then Alpha + Charlie (alpha).
        final titles = tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((t) => (t.title as Text).data)
            .toList();
        // The starred section renders Bravo, Delta in alpha order;
        // the all-routes section renders Alpha, Charlie.
        expect(titles, ['Bravo', 'Delta', 'Alpha', 'Charlie']);
      },
    );

    testWidgets(
      'no section headers when there are zero starred routes',
      (tester) async {
        await _pump(tester, [
          _route('a', 'Alpha'),
          _route('b', 'Bravo'),
        ]);
        // No starred → no STARRED / ALL ROUTES headers (just a
        // flat list).
        expect(find.text('STARRED'), findsNothing);
        expect(find.text('ALL ROUTES'), findsNothing);
      },
    );

    testWidgets(
      'search filters by case-insensitive name substring',
      (tester) async {
        await _pump(tester, [
          _route('a', 'River Loop'),
          _route('b', 'Park Trail'),
          _route('c', 'Bridge to Bridge'),
        ]);
        await tester.enterText(find.byType(TextField), 'bridge');
        await tester.pumpAndSettle();
        expect(find.text('Bridge to Bridge'), findsOneWidget);
        expect(find.text('River Loop'), findsNothing);
        expect(find.text('Park Trail'), findsNothing);
      },
    );

    testWidgets(
      'empty-search hint when search matches no routes',
      (tester) async {
        await _pump(tester, [_route('a', 'Alpha')]);
        await tester.enterText(find.byType(TextField), 'zzzz');
        await tester.pumpAndSettle();
        expect(find.textContaining('No routes match'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping "No route" pops with null',
      (tester) async {
        cm.Route? result = _route('placeholder', 'placeholder');
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      final picked = await pickRoute(
                        ctx,
                        routes: [_route('a', 'Alpha')],
                        unit: DistanceUnit.km,
                      );
                      result = picked;
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('No route'),
          ),
        );
        await tester.pumpAndSettle();
        expect(result, isNull);
      },
    );

    testWidgets(
      'tapping a route tile pops with that route',
      (tester) async {
        cm.Route? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await pickRoute(
                        ctx,
                        routes: [
                          _route('a', 'Alpha'),
                          _route('b', 'Bravo'),
                        ],
                        unit: DistanceUnit.km,
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bravo'));
        await tester.pumpAndSettle();
        expect(result?.id, 'b');
        expect(result?.name, 'Bravo');
      },
    );

    testWidgets(
      'clear-search button resets the filter + restores the full list',
      (tester) async {
        await _pump(tester, [
          _route('a', 'Alpha'),
          _route('b', 'Bravo'),
        ]);
        await tester.enterText(find.byType(TextField), 'alpha');
        await tester.pumpAndSettle();
        expect(find.text('Bravo'), findsNothing);
        // Tap the clear (close) icon in the suffix.
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('Bravo'), findsOneWidget);
        expect(find.text('Alpha'), findsOneWidget);
      },
    );
  });
}

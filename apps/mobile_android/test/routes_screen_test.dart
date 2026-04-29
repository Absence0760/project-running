import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_screen.dart';

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, {required Preferences prefs}) {
  return tester.pumpWidget(
    MaterialApp(
      home: RoutesScreen(
        apiClient: null,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  group('RoutesScreen — initial render', () {
    testWidgets('renders the Routes app-bar title', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.text('Routes'), findsOneWidget);
    });

    testWidgets('renders the Explore action in the app bar',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.explore), findsOneWidget);
    });

    testWidgets('hides the cloud-sync icon when apiClient is null',
        (tester) async {
      // Reason: without a signed-in user the cloud_download icon must
      // not appear — there is nothing to sync.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.cloud_download), findsNothing);
    });

    testWidgets('renders the Import FAB with the upload icon',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(find.byIcon(Icons.upload_file), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no routes',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.text('No routes yet'), findsOneWidget);
      expect(find.text('Tap Import to add a GPX or KML file'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/explore_routes_screen.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<({Preferences prefs, LocalRouteStore routeStore})> _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return (prefs: prefs, routeStore: LocalRouteStore());
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required LocalRouteStore routeStore,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: ExploreRoutesScreen(
        apiClient: null,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('ExploreRoutesScreen — initial render', () {
    testWidgets('renders the Explore Routes app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.text('Explore Routes'), findsOneWidget);
    });

    testWidgets('renders the Featured filter chip', (tester) async {
      // Reason: Featured is the entry point into curated routes —
      // its absence would mean users can't surface non-personal
      // content from the Explore tab.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, routeStore: s.routeStore);
      await tester.pump();
      expect(find.text('Featured'), findsOneWidget);
    });
  });
}

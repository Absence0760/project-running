import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/public_route_screen.dart';

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

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PublicRouteScreen(api: ApiClient(), routeId: 'fake-route-id'),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('PublicRouteScreen — initial render', () {
    testWidgets('renders the Route fallback title before the route loads',
        (tester) async {
      // Reason: until _route fills in, the title falls back to the
      // literal string "Route".
      await _pump(tester);
      expect(find.text('Route'), findsOneWidget);
    });

    testWidgets('first frame shows the loading spinner', (tester) async {
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

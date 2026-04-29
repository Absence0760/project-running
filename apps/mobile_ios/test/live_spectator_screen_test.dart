import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/screens/live_spectator_screen.dart';

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
      home: LiveSpectatorScreen(
        api: ApiClient(),
        runId: 'fake-run-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('LiveSpectatorScreen — initial render', () {
    testWidgets('renders the Live tracking app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Live tracking'), findsOneWidget);
    });
  });
}

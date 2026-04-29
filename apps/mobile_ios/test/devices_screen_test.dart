import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/screens/devices_screen.dart';

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
      home: DevicesScreen(
        api: ApiClient(),
        currentDeviceId: 'this-device-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('DevicesScreen — initial render', () {
    testWidgets('renders the Devices app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Devices'), findsOneWidget);
    });

    testWidgets('first frame shows the loading spinner', (tester) async {
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/widgets/run_segment_efforts.dart';

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
      home: Scaffold(
        body: RunSegmentEfforts(
          api: ApiClient(),
          runId: 'fake-run-id',
          routeId: null,
          track: const [],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('RunSegmentEfforts — initial render', () {
    testWidgets('shows the "Checking segments…" loading hint',
        (tester) async {
      // Reason: while _loading is true the widget renders just a
      // small text label — that's the only deterministic surface in
      // tests without a working Supabase backend.
      await _pump(tester);
      expect(find.text('Checking segments…'), findsOneWidget);
    });
  });
}

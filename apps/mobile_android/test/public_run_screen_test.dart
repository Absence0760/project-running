import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/public_run_screen.dart';

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
      home: PublicRunScreen(api: ApiClient(), runId: 'fake-run-id'),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('PublicRunScreen — initial render', () {
    testWidgets('renders the Run app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Run'), findsOneWidget);
    });

    testWidgets('first frame shows the loading spinner', (tester) async {
      await _pump(tester);
      // Single pump only — the post-fetch frame swaps in either
      // ErrorState or the run body once Supabase resolves.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

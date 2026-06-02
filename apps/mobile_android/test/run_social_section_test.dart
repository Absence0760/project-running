import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_social_section.dart';

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
      home: Scaffold(
        body: RunSocialSection(
          api: ApiClient(),
          runId: 'fake-run-id',
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('RunSocialSection — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the widget renders only a
      // CircularProgressIndicator inside a centered Padding.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

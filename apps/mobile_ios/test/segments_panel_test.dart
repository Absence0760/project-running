import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/segments_panel.dart';

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

Future<void> _pump(WidgetTester tester, {bool canCreate = false}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SegmentsPanel(
          api: ApiClient(),
          routeId: 'fake-route-id',
          routeDistanceM: 5000,
          canCreate: canCreate,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('SegmentsPanel — initial render', () {
    testWidgets('renders the Segments heading', (tester) async {
      await _pump(tester);
      expect(find.text('Segments'), findsOneWidget);
    });

    testWidgets('shows the "Loading segments…" hint while fetching',
        (tester) async {
      // Reason: while _loading is true the body renders only a small
      // text label — no SegmentTile or "No segments" empty state.
      await _pump(tester);
      expect(find.text('Loading segments…'), findsOneWidget);
    });

    testWidgets('hides the New segment button when canCreate is false',
        (tester) async {
      // Reason: only route owners can create segments — the button
      // must not appear for viewers.
      await _pump(tester, canCreate: false);
      expect(find.text('New segment'), findsNothing);
    });

    testWidgets('shows the New segment button when canCreate is true',
        (tester) async {
      await _pump(tester, canCreate: true);
      expect(find.text('New segment'), findsOneWidget);
    });
  });
}

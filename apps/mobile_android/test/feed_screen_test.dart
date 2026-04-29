import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/screens/feed_screen.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // Local fake — never reached by network; the catch path inside
  // FeedScreen handles the connection failure that follows.
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(home: FeedScreen(api: ApiClient())),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('FeedScreen — initial render', () {
    testWidgets('renders the Feed app-bar title', (tester) async {
      await _pump(tester);
      await tester.pump();
      expect(find.text('Feed'), findsOneWidget);
    });

    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: _loading is true initially. Single pump only — the
      // post-fetch frame swaps in either ErrorState or the entries
      // list once the (failing) Supabase call resolves.
      await _pump(tester);
      // Don't pump again — let the spinner be visible before the
      // catch path fires and replaces it.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

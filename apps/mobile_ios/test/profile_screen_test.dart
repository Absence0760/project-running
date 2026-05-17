import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/screens/profile_screen.dart';

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

Future<void> _pump(WidgetTester tester, {required String userId}) {
  return tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(api: ApiClient(), userId: userId),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('ProfileScreen — initial render', () {
    testWidgets('renders the Profile fallback title before the summary loads',
        (tester) async {
      // Reason: until _summary fills in, the title shows the literal
      // string "Profile" — make sure the fallback renders.
      await _pump(tester, userId: 'someone-else');
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('first frame shows the loading spinner', (tester) async {
      await _pump(tester, userId: 'someone-else');
      // Single pump only — the post-fetch frame swaps in ErrorState.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders three tabs (Runs/Followers/Following) for non-self',
        (tester) async {
      // Reason: Notifications is gated to isSelf — it must NOT appear
      // when viewing another user's profile.
      await _pump(tester, userId: 'someone-else');
      expect(find.text('Runs'), findsOneWidget);
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('Following'), findsOneWidget);
      expect(find.text('Notifications'), findsNothing);
    });
  });

  group('_verbFor — event_rsvp wiring', () {
    // Source-level grep for the verb strings the web NotificationsList
    // emits. Profile_screen owns the equivalent Dart switch; if the
    // verb / kind label diverges from web (or the migration name in
    // the project), the parity contract from decisions §31 / §38 is
    // broken. Cheaper than booting a tester with a fake API.
    final source =
        File('lib/screens/profile_screen.dart').readAsStringSync();

    test('handles the event_rsvp notification kind', () {
      expect(source.contains("case 'event_rsvp':"), isTrue,
          reason:
              'event_rsvp was added in migration 20260903_001 — the inbox '
              'verb switch must list it explicitly.');
    });

    test('verb string mirrors the web "RSVP\'d Going" phrasing', () {
      // Source on disk encodes the apostrophe as `\'` inside a single-
      // quoted string literal; match that literal byte sequence.
      expect(source.contains(r"RSVP\'d Going to your event"), isTrue,
          reason:
              'Verb text must match NotificationsList.svelte so push / '
              'inbox / web stay in lockstep.');
    });

    test('event_rsvp tap navigates into the club event detail', () {
      expect(source.contains('EventDetailScreen('), isTrue,
          reason:
              'Tapping an event_rsvp notification must open the same '
              'EventDetailScreen the club-event tab uses.');
    });
  });
}

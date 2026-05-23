// Widget tests for ClubInviteScreen — mobile parity with the web
// /clubs/join/[token] surface. The screen reads a token (typed or
// deep-link-injected), calls SocialService.joinClubByToken, and
// navigates to the club detail on success. Failures surface the
// RPC's own error string (those are written for end-user reading).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/screens/club_invite_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

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

class _FakeSocialService extends SocialService {
  String? capturedToken;
  Object? errorToThrow;
  String returnSlug = 'richmond-run-club';

  @override
  Future<String> joinClubByToken(String token) async {
    capturedToken = token;
    if (errorToThrow != null) throw errorToThrow!;
    return returnSlug;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  _FakeSocialService? social,
  String? initialToken,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: ClubInviteScreen(
        social: social ?? _FakeSocialService(),
        training: TrainingService(),
        initialToken: initialToken,
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('ClubInviteScreen', () {
    testWidgets('renders the Join club title + invite-code field',
        (tester) async {
      await _pump(tester);
      expect(find.text('Join club'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Invite code'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
    });

    testWidgets('empty token shows hint instead of calling the RPC',
        (tester) async {
      // Defensive: tapping Join without a code must NOT silently
      // call the RPC with an empty string.
      final social = _FakeSocialService();
      await _pump(tester, social: social);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      expect(social.capturedToken, isNull);
      expect(find.textContaining('Enter the invite code'), findsOneWidget);
    });

    testWidgets('valid token calls joinClubByToken with trimmed value',
        (tester) async {
      final social = _FakeSocialService();
      await _pump(tester, social: social);
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        '  ABC-123-XYZ  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      // Plain pump — the success path navigates away (push to
      // ClubDetailScreen which fetches data); pumpAndSettle would
      // block on its in-flight network call.
      await tester.pump();
      expect(social.capturedToken, 'ABC-123-XYZ');
      // Drain the success top-banner's auto-dismiss timer + give
      // ClubDetailScreen's mount-time fetches a moment to settle
      // so the test ends cleanly.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('RPC error surfaces the message in the error slot',
        (tester) async {
      // RPC error strings ("token expired", "already a member") are
      // written for end-user reading — the screen surfaces them
      // raw rather than re-wrapping in generic copy.
      final social = _FakeSocialService()
        ..errorToThrow = Exception('Invite token expired');
      await _pump(tester, social: social);
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        'expired-token',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Invite token expired'), findsOneWidget);
    });

    testWidgets('initialToken fires auto-redemption on mount', (tester) async {
      // Headline contract for the deep-link path: landing on the
      // screen with a token pre-filled (universal link / app
      // intent) must trigger redemption without the user tapping
      // Join. The fake's capturedToken proves the call fired.
      final social = _FakeSocialService();
      await _pump(tester, social: social, initialToken: 'deeplink-token');
      // Two pump frames: one for the post-frame callback fire, one
      // for the Future to settle.
      await tester.pump();
      await tester.pump();
      expect(social.capturedToken, 'deeplink-token');
      // Drain pending timers (banner + ClubDetailScreen mount
      // fetches) so the test ends cleanly.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('initialToken whitespace-only does NOT auto-redeem',
        (tester) async {
      // Defensive: a "/clubs/join/   " malformed deep link must not
      // hit the API with an empty token. Pin the trim guard.
      final social = _FakeSocialService();
      await _pump(tester, social: social, initialToken: '   ');
      await tester.pump();
      await tester.pump();
      expect(social.capturedToken, isNull);
    });
  });
}

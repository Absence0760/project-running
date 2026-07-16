// Widget tests for ClubInviteScreen — mobile parity with the web
// /clubs/join/[token] surface. The screen reads a token (typed or
// deep-link-injected), calls SocialService.joinClubByToken, and
// navigates to the club detail on success. Failures route through
// friendlyError so the banner shows actionable copy (offline /
// rate-limited / generic) rather than a raw exception toString.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
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
  /// The redeem action gates on the viewer id, so a fake must declare
  /// who is looking rather than falling through to a real Supabase read.
  final String? viewerId = 'u-viewer';

  @override
  String? get currentUserId => viewerId;

  String? capturedToken;
  Object? errorToThrow;
  String returnSlug = 'richmond-run-club';
  int joinCalls = 0;
  // Gates the redeem future so the busy-spinner state can be observed.
  Completer<void>? gate;

  @override
  Future<String> joinClubByToken(String token) async {
    joinCalls++;
    capturedToken = token;
    if (gate != null) await gate!.future;
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

    testWidgets('a failure shows friendly generic copy, not the raw exception',
        (tester) async {
      // The raw exception (a PostgrestException / SocketException
      // toString is jargon) must never reach the banner — an opaque
      // failure collapses to the generic friendly fallback.
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
      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.textContaining('Invite token expired'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('an offline failure shows the offline copy, not raw jargon',
        (tester) async {
      // A network drop must be distinguishable from a generic error —
      // classifyAuthError routes a SocketException to the offline copy.
      final social = _FakeSocialService()
        ..errorToThrow =
            const SocketException('Failed host lookup: "example.com"');
      await _pump(tester, social: social);
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        'any-token',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
            'You appear to be offline. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.textContaining('Failed host lookup'), findsNothing);
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

    testWidgets('shows a spinner + disables Join while redemption is in flight',
        (tester) async {
      final social = _FakeSocialService()..gate = Completer<void>();
      await _pump(tester, social: social);
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        'slow-token',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      // Spinner shown inside the Join button while the gated call runs.
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      // The disabled button has no onPressed.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      // Release; redemption fails (no real ClubDetailScreen nav needed).
      social.errorToThrow = Exception('expired');
      social.gate!.complete();
      await tester.pumpAndSettle();
      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
    });

    testWidgets('error then a fixed retry succeeds — second call fires',
        (tester) async {
      // After a failed redemption the user can correct the code and tap
      // Join again; the button is re-enabled and the second attempt
      // reaches the RPC.
      final social = _FakeSocialService()
        ..errorToThrow = Exception('invalid token');
      await _pump(tester, social: social);
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        'bad',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      await tester.pump();
      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(social.joinCalls, 1);

      // Fix the code; clear the error injection; retry.
      social.errorToThrow = null;
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        'good-token',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      expect(social.joinCalls, 2);
      expect(social.capturedToken, 'good-token');
      // Drain banner + ClubDetailScreen mount fetches so teardown is clean.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a token with internal spaces is trimmed at the edges only',
        (tester) async {
      // trim() strips leading/trailing whitespace; internal characters
      // pass through verbatim (the RPC owns final validation).
      final social = _FakeSocialService();
      await _pump(tester, social: social);
      await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'),
        '  abc def  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pump();
      expect(social.capturedToken, 'abc def');
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

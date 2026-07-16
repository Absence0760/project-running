import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/sign_up_screen.dart';

class _FakeApiClient extends ApiClient {
  String? capturedEmail;
  String? capturedPassword;
  DateTime? capturedAgeConfirmedAt;
  DateTime? capturedTermsAcceptedAt;
  Object? errorToThrow;
  bool needsEmailConfirmation = false;

  @override
  Future<({String userId, bool needsEmailConfirmation})> signUp({
    required String email,
    required String password,
    DateTime? ageConfirmedAt,
    DateTime? termsAcceptedAt,
  }) async {
    capturedEmail = email;
    capturedPassword = password;
    capturedAgeConfirmedAt = ageConfirmedAt;
    capturedTermsAcceptedAt = termsAcceptedAt;
    if (errorToThrow != null) throw errorToThrow!;
    return (userId: 'uid-new', needsEmailConfirmation: needsEmailConfirmation);
  }
}

/// Duck-typed stand-in for a Supabase `AuthApiException` (carries `code`
/// + `statusCode`) so the server-error branches can be exercised without
/// importing the supabase auth types.
class _FakeAuthException {
  const _FakeAuthException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;
  final String? statusCode;
  @override
  String toString() =>
      'AuthApiException(message: $message, statusCode: $statusCode, code: $code)';
}

Future<void> _pump(WidgetTester tester, _FakeApiClient client) async {
  // The sign-up form has email + password + two GDPR checkboxes +
  // a Create Account button + OAuth divider + 2 OAuth rows. At the
  // default test viewport (800x600) the Create Account button
  // sits below the fold; widen the surface so tap-by-finder works
  // without scrolling each test.
  await tester.binding.setSurfaceSize(const Size(400, 1200));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SignUpScreen(apiClient: client),
    ),
  );
}

void main() {
  group('SignUpScreen', () {
    testWidgets('renders email and password fields', (tester) async {
      await _pump(tester, _FakeApiClient());
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('Create Account button is present', (tester) async {
      await _pump(tester, _FakeApiClient());
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.text('Create Account'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('calls signUp with entered credentials when button tapped',
        (tester) async {
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'new@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      // Both GDPR gates must be ticked before the API call fires.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, 'new@b.com');
      expect(client.capturedPassword, 'password1');
    });

    testWidgets('renders error text when signUp throws', (tester) async {
      final client = _FakeApiClient()..errorToThrow = Exception('Email taken');
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'taken@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      // A synthetic Exception classifies as generic — the raw text is
      // replaced by a friendly, user-facing message (auth_error.dart).
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });

    // ─────────── GDPR Art 8 gates ───────────

    testWidgets('renders both gate checkboxes with the canonical copy',
        (tester) async {
      await _pump(tester, _FakeApiClient());
      expect(find.text('I am 16 years of age or older'), findsOneWidget);
      expect(
        find.text('I accept the Terms of Service and Privacy Policy'),
        findsOneWidget,
      );
      expect(find.byType(Checkbox), findsNWidgets(2));
    });

    testWidgets('Terms + Privacy in the accept label are tappable link spans',
        (tester) async {
      // GDPR Art 7(2): the consent label must let the user open the Terms
      // + Privacy Policy before accepting.
      await _pump(tester, _FakeApiClient());
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final linkSpans = <TextSpan>[];
      for (final rt in richTexts) {
        rt.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) linkSpans.add(span);
          return true;
        });
      }
      expect(
        linkSpans.any((s) => s.text == 'Terms of Service'),
        isTrue,
        reason: 'Terms of Service must be a tappable span',
      );
      expect(
        linkSpans.any((s) => s.text == 'Privacy Policy'),
        isTrue,
        reason: 'Privacy Policy must be a tappable span',
      );
    });

    testWidgets('signUp blocked when age gate is unchecked', (tester) async {
      // GDPR Art 8 — users under 16 require parental consent in the
      // EU. A regression that let the API call fire without the
      // self-affirmation would be a real compliance gap.
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'longpass1');
      // Tick ToS but NOT the age gate.
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      // No API call.
      expect(client.capturedEmail, isNull);
      // Error copy explains the missing gate.
      expect(
        find.textContaining('16 or older'),
        findsOneWidget,
      );
    });

    testWidgets('signUp blocked when terms gate is unchecked', (tester) async {
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'longpass1');
      // Tick age but NOT terms.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, isNull);
      // The label also contains "Terms of Service"; assert the
      // distinctive "Please accept" prefix that only appears on the
      // error path.
      expect(
        find.textContaining('Please accept the Terms'),
        findsOneWidget,
      );
    });

    testWidgets('signUp blocked when BOTH gates are unchecked', (tester) async {
      // Negative-shape pin — neither gate ticked must surface the
      // age-gate hint first (consistent error ordering), not skip
      // to the API call.
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'longpass1');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, isNull);
      expect(find.textContaining('16 or older'), findsOneWidget);
    });

    testWidgets(
        'Google button shows coming-soon before the gate when unconfigured',
        (tester) async {
      // With the provider unconfigured (empty env) the coming-soon notice
      // must win even with the GDPR gates unchecked — the button isn't
      // functional yet, so it shouldn't nag about age/terms first.
      dotenv.loadFromString(envString: '', isOptional: true);
      final client = _FakeApiClient();
      await _pump(tester, client);
      final googleBtn =
          find.widgetWithText(OutlinedButton, 'Continue with Google');
      await tester.ensureVisible(googleBtn);
      await tester.tap(googleBtn);
      await tester.pump();
      expect(find.textContaining('coming soon'), findsOneWidget);
      // The config check precedes the gate, so no age-gate error and no API call.
      expect(find.textContaining('16 or older'), findsNothing);
      expect(client.capturedEmail, isNull);
    });


    // ─────────── Pre-submit validation (#243) ───────────

    testWidgets('malformed email shows an inline field error and no API call',
        (tester) async {
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'not-an-email');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, isNull);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('short password shows an inline field error and no API call',
        (tester) async {
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'short7!');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, isNull);
      expect(find.text('Password must be at least 8 characters.'),
          findsOneWidget);
    });

    testWidgets('inline field errors clear on the next valid submit',
        (tester) async {
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'not-an-email');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'short7!');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      // The too-short password error is still visible on the field —
      // find the password TextField by its label instead.
      await tester.enterText(
          find.ancestor(
              of: find.text('Password'), matching: find.byType(TextField)),
          'password1');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsNothing);
      expect(find.text('Password must be at least 8 characters.'),
          findsNothing);
      expect(client.capturedEmail, 'a@b.com');
    });

    // ─────────── Server-side auth errors (#242) ───────────

    testWidgets('duplicate email (confirmations disabled) shows the specific message',
        (tester) async {
      final client = _FakeApiClient()
        ..errorToThrow = const _FakeAuthException('User already registered',
            code: 'user_already_exists', statusCode: '422');
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'taken@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('already has an account'), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsNothing);
    });

    testWidgets('weak password rejected by the server shows the specific message',
        (tester) async {
      final client = _FakeApiClient()
        ..errorToThrow = const _FakeAuthException(
            'Password should be at least 8 characters',
            code: 'weak_password',
            statusCode: '422');
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('too weak'), findsOneWidget);
    });

    // ─────────── Obfuscated success with no session (#242) ───────────

    testWidgets(
        'signUp success without a session shows check-your-email and does not pop',
        (tester) async {
      // Confirmations-enabled posture: BOTH a genuine new signup and a
      // duplicate email return success-with-no-session. Navigating as
      // signed-in here was the "silent non-event" bug — the screen must
      // stay up and show the check-your-email state instead.
      final client = _FakeApiClient()..needsEmailConfirmation = true;
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'new@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(client.capturedEmail, 'new@b.com');
      expect(find.byType(SignUpScreen), findsOneWidget);
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('new@b.com'), findsOneWidget);
      expect(find.text('Back to sign in'), findsOneWidget);
    });

    // ─────────── Apple fail-closed gate (#241) ───────────

    testWidgets(
        'Apple button shows coming-soon before the gate when unconfigured',
        (tester) async {
      // No APPLE_SERVICE_CLIENT_ID / APPLE_REDIRECT_URI in the env →
      // the Android web-auth flow can never succeed
      // (sign_in_with_apple throws before any UI opens), so the button
      // must fail closed with the friendly notice — before the GDPR
      // gate nag, mirroring the Google precedence pinned above.
      dotenv.loadFromString(envString: '', isOptional: true);
      final client = _FakeApiClient();
      await _pump(tester, client);
      final appleBtn =
          find.widgetWithText(OutlinedButton, 'Continue with Apple');
      await tester.ensureVisible(appleBtn);
      await tester.tap(appleBtn);
      await tester.pump();
      expect(find.textContaining('Apple sign-in is coming soon'),
          findsOneWidget);
      expect(find.textContaining('16 or older'), findsNothing);
      expect(client.capturedEmail, isNull);
    });

    testWidgets('"Sign in" back link pops the screen', (tester) async {
      // Wrap in a Navigator so there is a previous route to pop back to.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('previous')),
          routes: {
            '/signup': (_) => SignUpScreen(apiClient: _FakeApiClient()),
          },
        ),
      );
      // Navigate to sign-up.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SignUpScreen(apiClient: _FakeApiClient()),
          builder: (context, child) => Scaffold(body: child),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) =>
                        SignUpScreen(apiClient: _FakeApiClient()),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);
      await tester.ensureVisible(find.textContaining('Sign in'));
      await tester.tap(find.textContaining('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsNothing);
    });
  });
}

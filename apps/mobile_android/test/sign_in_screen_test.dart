import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/sign_in_screen.dart';
import '../lib/screens/sign_up_screen.dart';

class _FakeApiClient extends ApiClient {
  String? capturedEmail;
  String? capturedPassword;
  String? capturedResetEmail;
  String? capturedResetRedirectTo;
  String? capturedResendEmail;
  Object? errorToThrow;
  Object? resetErrorToThrow;

  @override
  Future<void> resendSignUpConfirmation({required String email}) async {
    capturedResendEmail = email;
  }

  @override
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    capturedEmail = email;
    capturedPassword = password;
    if (errorToThrow != null) throw errorToThrow!;
    return 'uid-123';
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
  }) async {
    capturedResetEmail = email;
    capturedResetRedirectTo = redirectTo;
    if (resetErrorToThrow != null) throw resetErrorToThrow!;
  }
}

Future<void> _pump(WidgetTester tester, _FakeApiClient client) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SignInScreen(apiClient: client),
    ),
  );
}

/// Duck-typed stand-in for a Supabase `AuthApiException` (carries `code`
/// + `statusCode`) so the classified error branches can be exercised
/// without importing the supabase auth types.
class _FakeAuthException {
  const _FakeAuthException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;
  final String? statusCode;
  @override
  String toString() =>
      'AuthApiException(message: $message, statusCode: $statusCode, code: $code)';
}

void main() {
  group('SignInScreen', () {
    testWidgets('renders email and password text fields', (tester) async {
      await _pump(tester, _FakeApiClient());
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('renders the sign-in FilledButton', (tester) async {
      await _pump(tester, _FakeApiClient());
      // The FilledButton has text "Sign In"; the AppBar title is also
      // "Sign In". Scope to FilledButton to disambiguate.
      expect(
        find.descendant(
            of: find.byType(FilledButton), matching: find.text('Sign In')),
        findsOneWidget,
      );
    });

    testWidgets('calls signIn with entered credentials when button tapped',
        (tester) async {
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'a@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'secret');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, 'a@b.com');
      expect(client.capturedPassword, 'secret');
    });

    testWidgets('renders error text when signIn throws', (tester) async {
      final client = _FakeApiClient()
        ..errorToThrow = Exception('Invalid credentials');
      await _pump(tester, client);
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'x@y.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'wrong');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      // The raw exception text is classified into a friendly message
      // (auth_error.dart) instead of being shown verbatim.
      expect(find.textContaining('Incorrect email or password'), findsOneWidget);
    });

    testWidgets(
        'Google button shows a coming-soon notice when the provider is unconfigured',
        (tester) async {
      // GOOGLE_WEB_CLIENT_ID unset (empty env) → the button must show the
      // friendly coming-soon copy, not attempt a native sign-in or surface
      // a raw config error. Mirrors web's PUBLIC_GOOGLE_AUTH_ENABLED gate.
      dotenv.loadFromString(envString: '', isOptional: true);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await _pump(tester, _FakeApiClient());
      final googleBtn =
          find.widgetWithText(OutlinedButton, 'Sign in with Google');
      await tester.ensureVisible(googleBtn);
      await tester.tap(googleBtn);
      await tester.pump();
      expect(find.textContaining('coming soon'), findsOneWidget);
    });

    testWidgets('"Create one" link navigates to SignUpScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await _pump(tester, _FakeApiClient());
      await tester.ensureVisible(find.textContaining("Create one"));
      await tester.tap(find.textContaining("Create one"));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);
    });


    // ─────────── Apple fail-closed gate (#241) ───────────

    testWidgets(
        'Apple button shows a coming-soon notice when the web-auth flow is unconfigured',
        (tester) async {
      // No APPLE_SERVICE_CLIENT_ID / APPLE_REDIRECT_URI in the env →
      // sign_in_with_apple's Android path throws before any UI opens,
      // so the button must fail closed with the friendly notice —
      // the same treatment as the Google gate above.
      dotenv.loadFromString(envString: '', isOptional: true);
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await _pump(tester, _FakeApiClient());
      final appleBtn =
          find.widgetWithText(OutlinedButton, 'Sign in with Apple');
      await tester.ensureVisible(appleBtn);
      await tester.tap(appleBtn);
      await tester.pump();
      expect(find.textContaining('Apple sign-in is coming soon'),
          findsOneWidget);
    });

    // ─────────── Unconfirmed email (#242) ───────────

    testWidgets(
        'email_not_confirmed sign-in failure shows the specific message + resend button',
        (tester) async {
      final client = _FakeApiClient()
        ..errorToThrow = const _FakeAuthException('Email not confirmed',
            code: 'email_not_confirmed', statusCode: '400');
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'me@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'password1');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Confirm your email first'), findsOneWidget);
      expect(find.text('Resend confirmation email'), findsOneWidget);

      await tester.tap(find.text('Resend confirmation email'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(client.capturedResendEmail, 'me@example.com');
      // Privacy-preserving copy — must not confirm account existence.
      expect(
        find.textContaining('If that email is registered'),
        findsOneWidget,
      );
      // Drain the top-banner auto-dismiss timer.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('other sign-in failures do not show the resend button',
        (tester) async {
      final client = _FakeApiClient()
        ..errorToThrow = const _FakeAuthException('Invalid login credentials',
            code: 'invalid_credentials', statusCode: '400');
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'me@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'wrongpass');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Incorrect email or password'),
          findsOneWidget);
      expect(find.text('Resend confirmation email'), findsNothing);
    });

    // ─────────── Forgot password? ───────────

    testWidgets('"Forgot password?" link is visible alongside Sign In',
        (tester) async {
      await _pump(tester, _FakeApiClient());
      expect(find.text('Forgot password?'), findsOneWidget);
    });

    testWidgets('Forgot password without an email surfaces a hint',
        (tester) async {
      // Defensive: tapping Forgot password with an empty email must
      // NOT silently call the API with a blank string. Pin the
      // "Enter your email above first" hint as the surfaced error.
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      expect(client.capturedResetEmail, isNull);
      expect(find.textContaining('Enter your email above'), findsOneWidget);
    });

    testWidgets('Forgot password with an email calls sendPasswordResetEmail',
        (tester) async {
      // Headline regression net: a user typing "me@example.com" +
      // tapping the link must trigger the reset-email API with the
      // trimmed value. Email field's value is the source of truth.
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), '  me@example.com  ');
      await tester.tap(find.text('Forgot password?'));
      // Plain pump — pumpAndSettle would block on the top-banner's
      // ~5s auto-dismiss timer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(client.capturedResetEmail, 'me@example.com');
      // The reset link must point at the web /auth/reset page (mobile
      // doesn't host the form). With dotenv uninitialised in the test,
      // WEB_BASE_URL falls back to the prod host. Without an explicit
      // redirectTo GoTrue falls back to the project Site URL (localhost
      // by default) and the link dies in prod.
      expect(client.capturedResetRedirectTo, 'https://threkir.com/auth/reset');
      // Tear down the banner timer before the test ends so the
      // fake-async loop doesn't flag a pending timer.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Forgot password shows the privacy-preserving confirmation',
        (tester) async {
      // The success copy must NOT leak "we sent the email" / "your
      // account exists" — the standard practice is "If that email
      // is registered…". A regression that confirmed account
      // existence would be a real privacy leak.
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'me@example.com');
      await tester.tap(find.text('Forgot password?'));
      // Single pump — pumpAndSettle would block on the top-banner's
      // ~3s timer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.textContaining('If that email is registered'),
        findsOneWidget,
      );
      // Drain the banner's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('Forgot password rejects a non-email shape', (tester) async {
      // No "@" → the "looks like an email" guard catches it. Pin
      // so a typo doesn't get silently round-tripped to Supabase
      // and stuck in their analytics.
      final client = _FakeApiClient();
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'not-an-email');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      expect(client.capturedResetEmail, isNull);
      expect(find.textContaining('Enter your email above'), findsOneWidget);
    });

    testWidgets('Forgot password surfaces network errors as an error message',
        (tester) async {
      // Supabase may rate-limit reset requests; the error path must
      // surface a readable message rather than silently no-op.
      final client = _FakeApiClient()
        ..resetErrorToThrow = Exception('Network unreachable');
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'me@example.com');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      // A synthetic Exception (not a real SocketException) classifies as
      // generic — the point is that some readable message surfaces.
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });
  });
}

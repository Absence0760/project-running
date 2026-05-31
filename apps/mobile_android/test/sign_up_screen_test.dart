import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/sign_up_screen.dart';

class _FakeApiClient extends ApiClient {
  String? capturedEmail;
  String? capturedPassword;
  DateTime? capturedAgeConfirmedAt;
  DateTime? capturedTermsAcceptedAt;
  Object? errorToThrow;

  @override
  Future<String> signUp({
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
    return 'uid-new';
  }
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
          find.widgetWithText(TextField, 'Password'), 'pass123');
      // Both GDPR gates must be ticked before the API call fires.
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, 'new@b.com');
      expect(client.capturedPassword, 'pass123');
    });

    testWidgets('renders error text when signUp throws', (tester) async {
      final client = _FakeApiClient()..errorToThrow = Exception('Email taken');
      await _pump(tester, client);
      await tester.enterText(
          find.widgetWithText(TextField, 'Email'), 'taken@b.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Password'), 'abc');
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Email taken'), findsOneWidget);
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
          find.widgetWithText(TextField, 'Password'), 'secret');
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
          find.widgetWithText(TextField, 'Password'), 'secret');
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
          find.widgetWithText(TextField, 'Password'), 'secret');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      expect(client.capturedEmail, isNull);
      expect(find.textContaining('16 or older'), findsOneWidget);
    });

    testWidgets('"Sign in" back link pops the screen', (tester) async {
      // Wrap in a Navigator so there is a previous route to pop back to.
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(body: Text('previous')),
          routes: {
            '/signup': (_) => SignUpScreen(apiClient: _FakeApiClient()),
          },
        ),
      );
      // Navigate to sign-up.
      await tester.pumpWidget(
        MaterialApp(
          home: SignUpScreen(apiClient: _FakeApiClient()),
          builder: (context, child) => Scaffold(body: child),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await tester.pumpWidget(
        MaterialApp(
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

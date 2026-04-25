import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/screens/sign_up_screen.dart';

class _FakeApiClient extends ApiClient {
  String? capturedEmail;
  String? capturedPassword;
  Object? errorToThrow;

  @override
  Future<String> signUp({
    required String email,
    required String password,
  }) async {
    capturedEmail = email;
    capturedPassword = password;
    if (errorToThrow != null) throw errorToThrow!;
    return 'uid-new';
  }
}

Future<void> _pump(WidgetTester tester, _FakeApiClient client) {
  return tester.pumpWidget(
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
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('Email taken'), findsOneWidget);
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

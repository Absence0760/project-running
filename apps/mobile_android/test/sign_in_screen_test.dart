import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/screens/sign_in_screen.dart';
import 'package:mobile_android/screens/sign_up_screen.dart';

class _FakeApiClient extends ApiClient {
  String? capturedEmail;
  String? capturedPassword;
  Object? errorToThrow;

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
}

Future<void> _pump(WidgetTester tester, _FakeApiClient client) {
  return tester.pumpWidget(
    MaterialApp(
      home: SignInScreen(apiClient: client),
    ),
  );
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
      expect(find.textContaining('Invalid credentials'), findsOneWidget);
    });

    testWidgets('"Create one" link navigates to SignUpScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      await _pump(tester, _FakeApiClient());
      await tester.ensureVisible(find.textContaining("Create one"));
      await tester.tap(find.textContaining("Create one"));
      await tester.pumpAndSettle();
      expect(find.byType(SignUpScreen), findsOneWidget);
    });
  });
}

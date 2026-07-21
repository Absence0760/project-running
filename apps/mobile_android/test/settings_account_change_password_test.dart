import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';

class _PasswordApi extends ApiClient {
  String? capturedPassword;
  final List<String> verifyCalls = [];
  bool verifyResult;

  _PasswordApi({this.verifyResult = true});

  @override
  String? get userId => 'u1';
  @override
  String? get userEmail => 'runner@test.com';
  @override
  Future<DateTime?> fetchCoachConsentAt() async => null;
  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        shadowHidden: false,
        id: 'u1',
        displayName: 'Runner',
        avatarUrl: null,
      );
  @override
  Future<bool> verifyCurrentPassword(String currentPassword) async {
    verifyCalls.add(currentPassword);
    return verifyResult;
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    capturedPassword = newPassword;
  }
}

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

Future<void> _openDialog(WidgetTester tester, _PasswordApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsAccountScreen(
        apiClient: api,
        preferences: Preferences(),
        settingsSync: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Change password'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Change password'));
  await tester.pumpAndSettle();
}

// Current(0) / New(1) / Confirm(2) — the three step-up password fields.
Finder _dialogField(int index) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .at(index);

Finder get _saveButton => find.widgetWithText(FilledButton, 'Save');

// Fill all three fields and rebuild so the Save button re-evaluates.
Future<void> _fill(
  WidgetTester tester, {
  required String current,
  required String next,
  required String confirm,
}) async {
  await tester.enterText(_dialogField(0), current);
  await tester.enterText(_dialogField(1), next);
  await tester.enterText(_dialogField(2), confirm);
  await tester.pump();
}

// Drive the async changePassword flow without pumpAndSettle (the Save
// button's in-flight CircularProgressIndicator would spin forever).
Future<void> _settleAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dialog declares step-up autofill hints in an AutofillGroup',
      (tester) async {
    await _openDialog(tester, _PasswordApi());

    expect(
      find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(AutofillGroup)),
      findsOneWidget,
    );
    final current = tester.widget<TextField>(_dialogField(0));
    expect(current.autofillHints, contains(AutofillHints.password));
    expect(current.textInputAction, TextInputAction.next);
    final next = tester.widget<TextField>(_dialogField(1));
    expect(next.autofillHints, contains(AutofillHints.newPassword));
    expect(next.textInputAction, TextInputAction.next);
    final confirm = tester.widget<TextField>(_dialogField(2));
    expect(confirm.autofillHints, contains(AutofillHints.newPassword));
    expect(confirm.textInputAction, TextInputAction.done);
  });

  testWidgets('Save stays disabled until the current password is entered',
      (tester) async {
    await _openDialog(tester, _PasswordApi());

    // A valid new pair is not enough — without the current password the
    // step-up cannot run, so Save must stay disabled.
    await tester.enterText(_dialogField(1), 'newpass99');
    await tester.enterText(_dialogField(2), 'newpass99');
    await tester.pump();
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNull);

    await tester.enterText(_dialogField(0), 'currentpw');
    await tester.pump();
    expect(tester.widget<FilledButton>(_saveButton).onPressed, isNotNull);
  });

  testWidgets('correct current password verifies then updates and commits '
      'autofill', (tester) async {
    final api = _PasswordApi(verifyResult: true);
    await _openDialog(tester, api);

    await _fill(tester,
        current: 'currentpw123', next: 'newpass99', confirm: 'newpass99');
    tester.testTextInput.log.clear();
    await tester.tap(_saveButton);
    await _settleAsync(tester);

    expect(api.verifyCalls, ['currentpw123']);
    expect(api.capturedPassword, 'newpass99');
    expect(
      tester.testTextInput.log.map((c) => c.method),
      contains('TextInput.finishAutofillContext'),
    );

    await tester.pump(const Duration(seconds: 4)); // drain the banner timer
  });

  testWidgets('wrong current password is rejected and never reaches '
      'updatePassword', (tester) async {
    final api = _PasswordApi(verifyResult: false);
    await _openDialog(tester, api);

    await _fill(tester,
        current: 'wrongpw', next: 'newpass99', confirm: 'newpass99');
    await tester.tap(_saveButton);
    await _settleAsync(tester);

    expect(api.verifyCalls, ['wrongpw']);
    expect(api.capturedPassword, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('incorrect'), findsOneWidget);
  });

  testWidgets('a mismatch is rejected before the current password is sent',
      (tester) async {
    final api = _PasswordApi();
    await _openDialog(tester, api);

    await _fill(tester,
        current: 'currentpw123', next: 'newpass99', confirm: 'newpass98');
    await tester.tap(_saveButton);
    await _settleAsync(tester);

    // The free local pair check runs first, so no sign-in attempt was spent.
    expect(api.verifyCalls, isEmpty);
    expect(api.capturedPassword, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Passwords do not match'), findsOneWidget);
  });

  testWidgets('a too-short new password reports length, not mismatch',
      (tester) async {
    final api = _PasswordApi();
    await _openDialog(tester, api);

    await _fill(tester, current: 'currentpw123', next: 'abc', confirm: 'xyz');
    await tester.tap(_saveButton);
    await _settleAsync(tester);

    expect(api.verifyCalls, isEmpty);
    expect(api.capturedPassword, isNull);
    expect(find.textContaining('at least'), findsOneWidget);
    expect(find.textContaining('do not match'), findsNothing);
  });
}

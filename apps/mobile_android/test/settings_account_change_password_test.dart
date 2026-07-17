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

Finder _dialogField(int index) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .at(index);

void main() {
  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'dialog fields declare newPassword autofill hints in an AutofillGroup',
      (tester) async {
    await _openDialog(tester, _PasswordApi());

    expect(
      find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(AutofillGroup)),
      findsOneWidget,
    );
    final first = tester.widget<TextField>(_dialogField(0));
    expect(first.autofillHints, contains(AutofillHints.newPassword));
    expect(first.textInputAction, TextInputAction.next);
    final second = tester.widget<TextField>(_dialogField(1));
    expect(second.autofillHints, contains(AutofillHints.newPassword));
    expect(second.textInputAction, TextInputAction.done);
  });

  testWidgets('next on the new-password field moves focus to confirm',
      (tester) async {
    await _openDialog(tester, _PasswordApi());

    await tester.enterText(_dialogField(0), 'newpass99');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    final second = tester.widget<TextField>(_dialogField(1));
    expect(second.focusNode?.hasFocus, isTrue);
  });

  testWidgets('done on the confirm field submits and commits autofill',
      (tester) async {
    final api = _PasswordApi();
    await _openDialog(tester, api);

    await tester.enterText(_dialogField(0), 'newpass99');
    await tester.enterText(_dialogField(1), 'newpass99');
    tester.testTextInput.log.clear();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.capturedPassword, 'newpass99');
    expect(
      tester.testTextInput.log.map((c) => c.method),
      contains('TextInput.finishAutofillContext'),
    );

    await tester.pump(const Duration(seconds: 4)); // drain the banner timer
  });

  testWidgets('done on a mismatched pair keeps the dialog open, no API call',
      (tester) async {
    final api = _PasswordApi();
    await _openDialog(tester, api);

    await tester.enterText(_dialogField(0), 'newpass99');
    await tester.enterText(_dialogField(1), 'newpass98');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(api.capturedPassword, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Passwords do not match'), findsOneWidget);
  });
}

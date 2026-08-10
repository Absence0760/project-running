import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';

class _EmailApi extends ApiClient {
  _EmailApi({this.fail = false});
  final bool fail;
  final List<String> writes = <String>[];

  @override
  String? get userId => 'u1';
  @override
  String? get userEmail => 'old@test.com';
  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => null;
  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        shadowHidden: false,
        id: 'u1',
        displayName: 'Alex',
        avatarUrl: null,
      );
  @override
  Future<void> updateEmail(String newEmail) async {
    writes.add(newEmail);
    if (fail) throw StateError('boom');
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

Future<void> _pump(WidgetTester tester, _EmailApi api) async {
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
}

Future<void> _openDialog(WidgetTester tester) async {
  final tile = find.text('Change email');
  // The tile lives near the bottom of a lazy ListView — scroll it into
  // the build before tapping.
  await tester.scrollUntilVisible(tile, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Finder _dialogSave() =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Save'));

void main() {
  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the Change email tile is present when signed in', (tester) async {
    await _pump(tester, _EmailApi());
    await tester.scrollUntilVisible(find.text('Change email'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Change email'), findsOneWidget);
  });

  testWidgets('an unchanged address is rejected and writes nothing',
      (tester) async {
    final api = _EmailApi();
    await _pump(tester, api);
    await _openDialog(tester);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'old@test.com',
    );
    await tester.tap(_dialogSave());
    await tester.pumpAndSettle();

    expect(
      find.textContaining("valid email address that's different"),
      findsOneWidget,
    );
    expect(api.writes, isEmpty);
  });

  testWidgets('a malformed address is rejected and writes nothing',
      (tester) async {
    final api = _EmailApi();
    await _pump(tester, api);
    await _openDialog(tester);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'not-an-email',
    );
    await tester.tap(_dialogSave());
    await tester.pumpAndSettle();

    expect(
      find.textContaining("valid email address that's different"),
      findsOneWidget,
    );
    expect(api.writes, isEmpty);
  });

  testWidgets('a valid new address requests the change and shows pending',
      (tester) async {
    final api = _EmailApi();
    await _pump(tester, api);
    await _openDialog(tester);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'new@test.com',
    );
    await tester.tap(_dialogSave());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.writes, <String>['new@test.com']);
    // The pending note names both inboxes; it renders on the tile subtitle
    // (and transiently in the top banner).
    expect(find.textContaining('new@test.com'), findsWidgets);
    expect(find.textContaining('old@test.com'), findsWidgets);

    await tester.pump(const Duration(seconds: 4)); // drain the banner timer
  });

  testWidgets('a failed request surfaces an error banner', (tester) async {
    final api = _EmailApi(fail: true);
    await _pump(tester, api);
    await _openDialog(tester);

    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'new@test.com',
    );
    await tester.tap(_dialogSave());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining("Couldn't start the email change"),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });
}

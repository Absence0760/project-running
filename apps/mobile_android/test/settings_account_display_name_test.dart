import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';

class _NameApi extends ApiClient {
  _NameApi({this.name, this.fail = false});
  String? name;
  final bool fail;
  final List<String?> writes = <String?>[];

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
        displayName: name,
        avatarUrl: null,
      );
  @override
  Future<void> updateDisplayName(String? displayName) async {
    writes.add(displayName);
    if (fail) throw StateError('write failed');
    name = displayName;
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

Future<void> _pump(WidgetTester tester, _NameApi api) async {
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

Finder _nameTile() => find.ancestor(
      of: find.text('Display name'),
      matching: find.byType(ListTile),
    );

void main() {
  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tile shows the saved display name', (tester) async {
    await _pump(tester, _NameApi(name: 'Alex Rivera'));

    expect(_nameTile(), findsOneWidget);
    expect(find.text('Alex Rivera'), findsOneWidget);
  });

  testWidgets('tile explains the Runner fallback when unset', (tester) async {
    await _pump(tester, _NameApi(name: null));

    expect(find.text('Not set — you appear as "Runner"'), findsOneWidget);
  });

  testWidgets('editing the name writes it through and updates the tile',
      (tester) async {
    final api = _NameApi(name: null);
    await _pump(tester, api);

    await tester.tap(_nameTile());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '  Alex Rivera  ');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Trimmed before the write, per the wizard's own shaping.
    expect(api.writes, <String>['Alex Rivera']);
    expect(find.text('Alex Rivera'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4)); // drain the banner timer
  });

  testWidgets('cancelling writes nothing', (tester) async {
    final api = _NameApi(name: 'Alex');
    await _pump(tester, api);

    await tester.tap(_nameTile());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();

    expect(api.writes, isEmpty);
  });

  testWidgets('a failed save surfaces an error and keeps the old name',
      (tester) async {
    final api = _NameApi(name: 'Alex', fail: true);
    await _pump(tester, api);

    await tester.tap(_nameTile());
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Sam');
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't update your display name. Please try again."),
        findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });
}

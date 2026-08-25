import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/settings_sync.dart';

/// Date of birth is written to two stores under two rules (decisions § 718):
/// `user_profiles.date_of_birth` is the age record behind the under-18
/// discoverability floor and carries no consent term, while the
/// `user_settings.prefs` mirror is the Art 9 health-use copy the coach and
/// HR-max reads consume and follows consent. Before this split the phone
/// wrote ONLY the Art 9 mirror, ungated — so a runner recorded
/// special-category data with no consent on record, and the age record the
/// floor keys off never landed at all.

class _FakeApi extends ApiClient {
  _FakeApi({this.consentAt, this.profileDob});

  final DateTime? consentAt;
  final DateTime? profileDob;
  DateTime? ageRecordWritten;
  int ageRecordCalls = 0;

  @override
  String? get userId => 'u1';

  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        shadowHidden: false,
        id: 'u1',
        healthDataConsentAt: consentAt,
        dateOfBirth: profileDob,
      );

  @override
  Future<void> setMyDateOfBirth(DateTime? dateOfBirth) async {
    ageRecordCalls++;
    ageRecordWritten = dateOfBirth;
  }
}

class _RecordingSync extends SettingsSyncService {
  _RecordingSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> writes = [];
  final Map<String, dynamic> bag = {};

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    writes.add(changes);
    bag.addAll(changes);
    notifyListeners();
  }
}

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api,
  Preferences prefs,
  _RecordingSync sync,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsPreferencesScreen(
        apiClient: api,
        preferences: prefs,
        settingsSync: sync,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDobRow(WidgetTester tester, AppLocalizations l10n) async {
  await tester.scrollUntilVisible(
    find.text(l10n.prefsDateOfBirth),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text(l10n.prefsDateOfBirth));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.prefsDateOfBirth));
  await tester.pumpAndSettle();
}

/// Drive the calendar from its year grid to a confirmed date. The picker
/// opens on the year list (#222), so pick a year, then a day, then confirm.
Future<void> _pickDate(WidgetTester tester, {required int year}) async {
  await tester.tap(find.text('$year'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('15').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await initializeDateFormatting();
  });

  testWidgets('a runner with no consent still records the age record, and the '
      'Art 9 mirror is not written', (tester) async {
    final api = _FakeApi();
    final sync = _RecordingSync(await _prefs());
    await _pump(tester, api, await _prefs(), sync);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await _openDobRow(tester, l10n);
    await _pickDate(tester, year: 1990);

    expect(api.ageRecordCalls, 1,
        reason: 'the age record must be written without an Art 9 consent');
    expect(api.ageRecordWritten?.year, 1990);
    expect(sync.bag.containsKey(SettingsKeys.dateOfBirth), isTrue);
    expect(sync.bag[SettingsKeys.dateOfBirth], isNull,
        reason: 'the Art 9 mirror fails closed with no consent on record');
  });

  testWidgets('with consent on record both stores are written',
      (tester) async {
    final api = _FakeApi(consentAt: DateTime.utc(2026, 1, 1));
    final sync = _RecordingSync(await _prefs());
    await _pump(tester, api, await _prefs(), sync);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await _openDobRow(tester, l10n);
    await _pickDate(tester, year: 1990);

    expect(api.ageRecordWritten?.year, 1990);
    expect(sync.bag[SettingsKeys.dateOfBirth], startsWith('1990-'));
  });

  testWidgets('the row reads the age record, not only the Art 9 mirror',
      (tester) async {
    // A withdrawal clears the mirror while the record stays on file —
    // reading the mirror alone rendered "Not set" over a stored birth date.
    final api = _FakeApi(profileDob: DateTime.utc(1988, 3, 4));
    final sync = _RecordingSync(await _prefs());
    await _pump(tester, api, await _prefs(), sync);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.scrollUntilVisible(
      find.text(l10n.prefsDateOfBirth),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1988-03-04'), findsOneWidget);
  });
}

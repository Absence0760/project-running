import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_safety_screen.dart';
import '../lib/settings_sync.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // api null: no Supabase round-trips — exercises the offline/empty UI
      // (the screen short-circuits the load when api/userId is null).
      home: const SettingsSafetyScreen(api: null),
    ),
  );
  await tester.pumpAndSettle();
}

/// Surfaces one incoming request and gates the confirm RPC so the in-flight
/// window stays open across a second tap.
class _SafetyApi extends ApiClient {
  _SafetyApi({this.hasPhone = false});

  final bool hasPhone;
  int confirmCalls = 0;
  final List<bool> confirmOptIns = [];
  final Completer<void> confirmGate = Completer<void>();

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => const [];

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async => [
        PendingSafetyRequest(
          id: 'req-1',
          ownerName: 'Jordan',
          hasPhone: hasPhone,
          createdAt: DateTime.utc(2026, 5, 1),
        ),
      ];

  @override
  Future<bool> confirmSafetyRequest(String id, {bool smsOptIn = false}) async {
    confirmCalls++;
    confirmOptIns.add(smsOptIn);
    await confirmGate.future;
    return true;
  }
}

/// Lists the four SMS states an owner's contact row can be in.
class _ContactListApi extends ApiClient {
  _ContactListApi(this._contacts);

  final List<SafetyContact> _contacts;

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => _contacts;

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async =>
      const [];
}

/// Records what the add call was handed, so the normalisation the screen
/// applies before the insert is observable.
class _AddCaptureApi extends ApiClient {
  final List<({String email, String? phone})> adds = [];

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => const [];

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async =>
      const [];

  @override
  Future<SafetyContact> addSafetyContact(String email, {String? phone}) async {
    adds.add((email: email, phone: phone));
    return SafetyContact(
      id: 'sc-new',
      contactEmail: email,
      contactPhone: phone,
      createdAt: DateTime.utc(2026, 5, 1),
    );
  }
}


/// The contact add always fails — drives the add-failure banner + its
/// Retry action (which must re-submit the kept email text).
class _AddFailApi extends ApiClient {
  int addCalls = 0;

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => const [];

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async =>
      const [];

  @override
  Future<SafetyContact> addSafetyContact(String email, {String? phone}) async {
    addCalls++;
    throw Exception('network down');
  }
}

/// One confirmed relationship the signed-in user is the CONTACT of. The
/// opt-in state lives on the fake, not on the widget, so the switch is only
/// ever driven by what a reload reports.
class _ContactOfApi extends ApiClient {
  _ContactOfApi({this.hasPhone = true, this.optInResult = true});

  final bool hasPhone;
  final bool optInResult;
  bool optedIn = false;
  bool withdrawn = false;
  final List<({String id, bool optIn})> optInCalls = [];
  final List<String> declines = [];
  final List<String> removes = [];

  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() async => const [];

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async =>
      const [];

  @override
  Future<List<SafetyContactOf>> fetchSafetyContactOf() async => withdrawn
      ? const []
      : [
          SafetyContactOf(
            id: 'rel-1',
            ownerId: 'owner-1',
            ownerName: 'Jordan',
            hasPhone: hasPhone,
            smsOptInAt: optedIn ? DateTime.utc(2026, 5, 2) : null,
            createdAt: DateTime.utc(2026, 5, 1),
          ),
        ];

  @override
  Future<bool> setSafetySmsOptIn(String id, bool optIn) async {
    optInCalls.add((id: id, optIn: optIn));
    if (optInResult) optedIn = optIn;
    return optInResult;
  }

  @override
  Future<bool> declineSafetyRequest(String id) async {
    declines.add(id);
    withdrawn = true;
    return true;
  }

  @override
  Future<void> removeSafetyContact(String id) async {
    removes.add(id);
  }
}

/// Never resolves either load, so the loading frame is observable.
class _HangingApi extends ApiClient {
  @override
  String? get userId => 'me';

  @override
  Future<List<SafetyContact>> fetchMySafetyContacts() =>
      Completer<List<SafetyContact>>().future;

  @override
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() =>
      Completer<List<PendingSafetyRequest>>().future;
}

/// Records bag writes and reports `synced` so the pref controls enable —
/// same shape as settings_email_notifications_test's fake. `service`
/// returns null, so the screen renders the defaults (Off / switch off).
class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs) : super(preferences: prefs);

  final List<Map<String, dynamic>> universalWrites = [];
  final List<Map<String, dynamic>> deviceWrites = [];

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    universalWrites.add(changes);
    notifyListeners();
  }

  @override
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    deviceWrites.add(changes);
    notifyListeners();
  }
}

/// Every settings write fails. A safety control that stays flipped after a
/// rejected write tells the runner they are covered when the server says
/// otherwise.
class _ThrowingSettingsSync extends SettingsSyncService {
  _ThrowingSettingsSync(Preferences prefs) : super(preferences: prefs);

  int deviceAttempts = 0;

  @override
  bool get synced => true;

  @override
  SettingsService? get service => null;

  @override
  Future<void> updateUniversal(Map<String, dynamic> changes) async {
    throw Exception('network down');
  }

  @override
  Future<void> updateDevice(Map<String, dynamic> changes) async {
    deviceAttempts++;
    throw Exception('network down');
  }
}

Future<_ThrowingSettingsSync> _throwingSync() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return _ThrowingSettingsSync(prefs);
}

Future<_FakeSettingsSync> _fakeSync() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  return _FakeSettingsSync(prefs);
}

/// The prefs section sits below the add form and the contact list, outside a
/// lazily-built ListView's first viewport. Scroll it in before reading it.
Future<Finder> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  return target;
}

void main() {
  group('SettingsSafetyScreen', () {
    testWidgets('the loading frame stands form rows, not a bare spinner',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: _HangingApi()),
        ),
      );
      await tester.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('renders the add form, intro and empty state', (tester) async {
      await _pump(tester);
      expect(find.text('Safety contacts'), findsWidgets);
      expect(find.text('Contact email'), findsOneWidget);
      expect(find.text('Add contact'), findsOneWidget);
      expect(find.text('No safety contacts yet.'), findsOneWidget);
      // No incoming-requests section without pending requests.
      expect(find.text('Requests for you'), findsNothing);
    });

    testWidgets('invalid email shows the inline validation banner',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField).first, 'not-an-email');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('a valid-looking email passes the inline check',
        (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField).first, 'partner@example.com');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      // With api == null the add is a no-op, but it must NOT trip the
      // invalid-email guard — that is the only client-side branch.
      expect(find.text('Enter a valid email address.'), findsNothing);
    });

    testWidgets('double-tapping Confirm on an incoming request fires once',
        (tester) async {
      final api = _SafetyApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      // The incoming-requests section sits below the overdue/auto-share
      // prefs; scroll it into the lazily-built ListView viewport first.
      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      await tester.scrollUntilVisible(
        confirm,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(confirm, findsOneWidget);

      await tester.tap(confirm);
      await tester.pump();
      // Second tap while the first confirm is gated in flight — disabled now.
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();

      expect(api.confirmCalls, 1);

      api.confirmGate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'a failed contact add shows a Retry banner that re-submits the '
        'kept email (issue #666 U8)', (tester) async {
      final api = _AddFailApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField).first, 'partner@example.com');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.addCalls, 1);
      expect(find.textContaining('Could not add contact'), findsOneWidget);
      final retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.addCalls, 2);
    });
  });

  group('SettingsSafetyScreen — SMS escalation leg', () {
    testWidgets('a punctuated number is normalised before the insert',
        (tester) async {
      final api = _AddCaptureApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Contact email'),
          'partner@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Phone for SMS (optional)'),
          '+44 (0) 7700 900123');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.adds, hasLength(1));
      expect(api.adds.single.phone, '+447700900123',
          reason: 'the trunk zero must be dropped, not kept as a digit');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('an unusable number is refused before the round trip',
        (tester) async {
      final api = _AddCaptureApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Contact email'),
          'partner@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, 'Phone for SMS (optional)'),
          '07700900123');
      await tester.tap(find.text('Add contact'));
      await tester.pump();

      expect(api.adds, isEmpty);
      expect(find.textContaining('international format'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('an empty phone field still adds an email-only contact',
        (tester) async {
      final api = _AddCaptureApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Contact email'),
          'partner@example.com');
      await tester.tap(find.text('Add contact'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.adds, hasLength(1));
      expect(api.adds.single.phone, isNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'a stored number without the contact opt-in is not shown as SMS on',
        (tester) async {
      final api = _ContactListApi([
        SafetyContact(
          id: 'sc-armed',
          contactEmail: 'armed@example.com',
          contactPhone: '+447700900123',
          contactUserId: 'u2',
          confirmedAt: DateTime.utc(2026, 5, 2),
          smsOptInAt: DateTime.utc(2026, 5, 2),
          createdAt: DateTime.utc(2026, 5, 1),
        ),
        SafetyContact(
          id: 'sc-waiting',
          contactEmail: 'waiting@example.com',
          contactPhone: '+447700900124',
          contactUserId: 'u3',
          confirmedAt: DateTime.utc(2026, 5, 2),
          createdAt: DateTime.utc(2026, 5, 1),
        ),
        SafetyContact(
          id: 'sc-email-only',
          contactEmail: 'emailonly@example.com',
          contactUserId: 'u4',
          confirmedAt: DateTime.utc(2026, 5, 2),
          createdAt: DateTime.utc(2026, 5, 1),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly one row may claim SMS, and it is the one that opted in.
      expect(find.text('SMS on'), findsOneWidget);
      expect(find.text("SMS off — they haven't opted in yet"), findsOneWidget);
    });

    testWidgets('the opt-in is offered only when the requester stored a number',
        (tester) async {
      final without = _SafetyApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: without),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Confirm'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Also alert me by SMS'), findsNothing);
    });

    testWidgets('ticking the opt-in carries it into the confirm RPC',
        (tester) async {
      final api = _SafetyApi(hasPhone: true);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      final optIn = find.text('Also alert me by SMS');
      await tester.scrollUntilVisible(
        optIn,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(optIn);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pump();

      expect(api.confirmOptIns, [true]);
      api.confirmGate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('confirming without ticking consents to email only',
        (tester) async {
      final api = _SafetyApi(hasPhone: true);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();

      final confirm = find.widgetWithText(FilledButton, 'Confirm');
      await tester.scrollUntilVisible(
        confirm,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(confirm);
      await tester.pump();

      expect(api.confirmOptIns, [false],
          reason: 'silence is not consent to be texted');
      api.confirmGate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('SettingsSafetyScreen — overdue + auto-live-share prefs', () {
    testWidgets('renders the overdue section with Off default + the switch off',
        (tester) async {
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.byType(SwitchListTile));
      expect(find.text('Overdue alert'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, isFalse);
      // The public-by-link disclosure is load-bearing copy.
      expect(
        find.textContaining('viewable by anyone with the link'),
        findsOneWidget,
      );
    });

    testWidgets('picking a window writes the universal pref', (tester) async {
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();

      expect(sync.universalWrites, [
        {'safety_overdue_minutes': 30},
      ]);
    });

    testWidgets('the auto-live-share toggle writes the device pref',
        (tester) async {
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(sync.deviceWrites, [
        {'auto_live_share': true},
      ]);
      expect(sync.universalWrites, isEmpty,
          reason: 'the device pref must not leak into the universal bag');
    });

    testWidgets('a rejected auto-live-share write reverts the switch',
        (tester) async {
      final sync = await _throwingSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.byType(SwitchListTile));
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(sync.deviceAttempts, 1);
      // The write was refused, so the control must not keep reading "on".
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse,
          reason: 'a safety switch may not claim a setting the server rejected');
      expect(find.textContaining('Could not save setting'), findsOneWidget);

    });

    testWidgets('a rejected overdue-window write reverts the dropdown',
        (tester) async {
      final sync = await _throwingSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();
      expect(
          tester.widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>))
              .value,
          isNull);

      await tester.tap(find.byType(DropdownButton<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 min').last);
      await tester.pumpAndSettle();

      expect(
          tester.widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>))
              .value,
          isNull,
          reason: 'a rejected escalation window must not read as configured');
      expect(find.textContaining('Could not save setting'), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('controls are disabled without a settings service',
        (tester) async {
      await _pump(tester); // api: null, settingsSync: null
      await _scrollTo(tester, find.byType(DropdownButton<int?>));
      final dropdown = tester.widget<DropdownButton<int?>>(
        find.byType(DropdownButton<int?>),
      );
      expect(dropdown.onChanged, isNull);
      await _scrollTo(tester, find.byType(SwitchListTile));
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
    });

    testWidgets(
        'the off-route toggle is hidden until the deploy flag is on, then '
        'writes the universal pref', (tester) async {
      // Flag off (dotenv not initialized) → hidden.
      dotenv.clean();
      final sync = await _fakeSync();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SwitchListTile, 'Off-route alert'),
          findsNothing);

      // Flag on → the toggle appears and writes the universal pref.
      dotenv.loadFromString(
        mergeWith: {'OFF_ROUTE_ESCALATION_ENABLED': 'true'},
        isOptional: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: null, settingsSync: sync),
        ),
      );
      await tester.pumpAndSettle();

      // The tile sits below the lazy list's build extent (the
      // auto-live-share subtitle grew a line for issue #664), so scroll
      // it into existence before asserting.
      await tester.scrollUntilVisible(
        find.text('Off-route alert'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final offRoute = find.widgetWithText(SwitchListTile, 'Off-route alert');
      expect(offRoute, findsOneWidget);
      await tester.tap(offRoute);
      await tester.pumpAndSettle();

      expect(sync.universalWrites, [
        {'safety_off_route_alerts': true},
      ]);

      // Reset the global flag so no later test in the file sees the toggle.
      dotenv.clean();
    });
  });

  // The relationships the user is the CONTACT of — the only surface
  // `set_safety_sms_opt_in` can be reached from once the confirm step is
  // behind them (decisions 726).
  group('SettingsSafetyScreen — you are a safety contact for', () {
    Future<_ContactOfApi> pumpContactOf(
      WidgetTester tester, {
      bool hasPhone = true,
      bool optInResult = true,
    }) async {
      final api = _ContactOfApi(hasPhone: hasPhone, optInResult: optInResult);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsSafetyScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('You are a safety contact'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('names the runner and offers the SMS consent, off',
        (tester) async {
      await pumpContactOf(tester);
      expect(find.text('Emergency contact for Jordan'), findsOneWidget);
      final sms = find.widgetWithText(
          SwitchListTile, 'Alert me by SMS as well as email');
      expect(sms, findsOneWidget);
      expect(tester.widget<SwitchListTile>(sms).value, isFalse);
    });

    testWidgets('turning SMS on calls the RPC and follows the server',
        (tester) async {
      final api = await pumpContactOf(tester);
      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Alert me by SMS as well as email'));
      await tester.pumpAndSettle();

      expect(api.optInCalls.length, 1);
      expect(api.optInCalls.first.id, 'rel-1');
      expect(api.optInCalls.first.optIn, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(
                SwitchListTile, 'Alert me by SMS as well as email'))
            .value,
        isTrue,
      );
    });

    testWidgets('a refused write leaves the switch where the server has it',
        (tester) async {
      final api = await pumpContactOf(tester, optInResult: false);
      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Alert me by SMS as well as email'));
      await tester.pumpAndSettle();

      expect(api.optInCalls.length, 1);
      expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(
                SwitchListTile, 'Alert me by SMS as well as email'))
            .value,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('withdrawing declines, never the owner-scoped remove',
        (tester) async {
      final api = await pumpContactOf(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Withdraw'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Withdraw'),
      ));
      await tester.pumpAndSettle();

      // `removeSafetyContact` is owner-scoped since 720 — wiring the button
      // to it would match nothing here and still report success.
      expect(api.declines, ['rel-1']);
      expect(api.removes, isEmpty);
      expect(find.text('Emergency contact for Jordan'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('no number on file offers the note, not the toggle',
        (tester) async {
      await pumpContactOf(tester, hasPhone: false);
      expect(
        find.widgetWithText(
            SwitchListTile, 'Alert me by SMS as well as email'),
        findsNothing,
      );
      expect(
        find.textContaining('SMS alerts need a mobile number for you'),
        findsOneWidget,
      );
    });
  });
}

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/training_service.dart';
import 'realtime_drain.dart';

/// The mobile half of issue #734: the AI route assistant now requires the
/// widened (v2) disclosure, so mobile needs a surface on which a runner can
/// accept it — and one that records what the SERVER stored, not a locally
/// synthesised stamp.

const _acceptedAt = '2026-01-01T00:00:00Z';

class _ConsentApi extends ApiClient {
  _ConsentApi({this.storedVersion, this.recordThrows = false});

  int? storedVersion;
  final bool recordThrows;
  final List<int> recorded = <int>[];
  int withdrawals = 0;

  @override
  String? get userId => 'u1';

  @override
  String? get userEmail => 'runner@test.com';

  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(
        shadowHidden: false,
        id: 'u1',
        displayName: 'Alex',
        avatarUrl: null,
      );

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async =>
      storedVersion == null
          ? null
          : {
              'ai_disclosure_version': storedVersion,
              'coach_consent_at': _acceptedAt,
            };

  @override
  Future<Map<String, dynamic>> recordAiDisclosureConsent(int version) async {
    recorded.add(version);
    if (recordThrows) throw StateError('consent not recorded');
    storedVersion = version;
    return {
      'ai_disclosure_version': version,
      'coach_consent_at': _acceptedAt,
    };
  }

  @override
  Future<void> withdrawAiDisclosureConsent() async {
    withdrawals++;
    storedVersion = null;
  }

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async =>
      const [];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];
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

Future<void> _pumpSettings(WidgetTester tester, _ConsentApi api) async {
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

Future<void> _pumpCoach(WidgetTester tester, _ConsentApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(api: api, training: TrainingService()),
    ),
  );
  // The chat surface carries a composer TextField, whose cursor animation
  // never settles — step the clock instead of pumpAndSettle.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Finder _dialogAccept() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('I consent — enable AI features'),
    );

const _reviewTile = 'Review the AI disclosure';
const _updateTile = 'Accept the updated AI disclosure';
const _withdrawTile = 'Withdraw AI features consent';

void main() {
  setUpAll(_ensureSupabase);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Settings → Account', () {
    testWidgets('a runner with nothing on record is offered the disclosure, '
        'and accepting records the current version', (tester) async {
      final api = _ConsentApi();
      await _pumpSettings(tester, api);

      await _scrollTo(tester, find.text(_reviewTile));
      expect(find.text(_withdrawTile), findsNothing);

      await tester.tap(find.text(_reviewTile));
      await tester.pumpAndSettle();

      // The dialog must show the WIDENED copy — the route bullet is the
      // whole reason a v1 acceptance is not enough.
      expect(
        find.textContaining('For the AI route assistant:'),
        findsOneWidget,
      );

      await tester.tap(_dialogAccept());
      await tester.pumpAndSettle();

      expect(api.recorded, [2]);
      expect(find.text('AI disclosure accepted.'), findsOneWidget);
      await _scrollTo(tester, find.text(_withdrawTile));
      expect(find.text(_reviewTile), findsNothing);
      expect(find.text(_updateTile), findsNothing);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a v1 Coach acceptance is offered the widened disclosure and '
        'keeps its withdrawal', (tester) async {
      final api = _ConsentApi(storedVersion: 1);
      await _pumpSettings(tester, api);

      await _scrollTo(tester, find.text(_updateTile));
      expect(find.text(_withdrawTile), findsOneWidget);
      expect(find.text(_reviewTile), findsNothing);
    });

    testWidgets('a current acceptance has no acceptance left to make',
        (tester) async {
      final api = _ConsentApi(storedVersion: 2);
      await _pumpSettings(tester, api);

      await _scrollTo(tester, find.text(_withdrawTile));
      expect(find.text(_updateTile), findsNothing);
      expect(find.text(_reviewTile), findsNothing);
    });

    testWidgets('a refused write leaves the dialog open and the record alone',
        (tester) async {
      // decisions § 560: a write that could not be performed must not
      // return as though it had.
      final api = _ConsentApi(recordThrows: true);
      await _pumpSettings(tester, api);

      await _scrollTo(tester, find.text(_reviewTile));
      await tester.tap(find.text(_reviewTile));
      await tester.pumpAndSettle();
      await tester.tap(_dialogAccept());
      await tester.pumpAndSettle();

      expect(api.recorded, [2]);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining("Couldn't record consent:"),
        findsOneWidget,
      );
      expect(find.text('AI disclosure accepted.'), findsNothing);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text(_reviewTile));
      expect(find.text(_withdrawTile), findsNothing);
    });

    testWidgets('withdrawing clears the record and re-offers the disclosure',
        (tester) async {
      final api = _ConsentApi(storedVersion: 2);
      await _pumpSettings(tester, api);

      await _scrollTo(tester, find.text(_withdrawTile));
      await tester.tap(find.text(_withdrawTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.withdrawals, 1);
      expect(find.text('AI features consent withdrawn.'), findsOneWidget);
      await _scrollTo(tester, find.text(_reviewTile));
      expect(find.text(_withdrawTile), findsNothing);

      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('CoachScreen', () {
    realtimeWidgetTest('a v1 Coach acceptance opens the chat — the widened '
        'disclosure is not re-prompted here', (tester) async {
      final api = _ConsentApi(storedVersion: 1);
      await _pumpCoach(tester, api);

      expect(find.text("Before you use Threkir's AI features"), findsNothing);
      expect(api.recorded, isEmpty);
    });

    realtimeWidgetTest('nothing on record blocks the chat, and accepting '
        'records the current version', (tester) async {
      final api = _ConsentApi();
      await _pumpCoach(tester, api);

      expect(find.text("Before you use Threkir's AI features"), findsOneWidget);
      expect(
        find.textContaining('For the AI route assistant:'),
        findsOneWidget,
      );

      // The disclosure is longer than the test viewport — the accept button
      // sits below the fold until the notice is scrolled through.
      final accept = find.text('I consent — enable AI features');
      await tester.ensureVisible(accept);
      await tester.pumpAndSettle();
      await tester.tap(accept);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(api.recorded, [2]);
      expect(find.text("Before you use Threkir's AI features"), findsNothing);
    });
  });
}

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coaching_screen.dart';

/// Signed-in fake whose coaching reads return canned data so the roster
/// screen renders without touching Supabase. Subclassing the real type keeps
/// it a drop-in for the screen's `api` field.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.athletes = const [],
    this.pending = const [],
    this.coaches = const [],
  });

  final List<CoachAthleteLink> athletes;
  final List<PendingCoachInvite> pending;
  final List<CoachAthleteLink> coaches;

  @override
  String? get userId => 'coach-1';

  @override
  Future<List<CoachAthleteLink>> fetchMyAthletes() async => athletes;

  @override
  Future<List<PendingCoachInvite>> fetchPendingCoachInvites() async => pending;

  @override
  Future<List<CoachAthleteLink>> fetchMyCoaches() async => coaches;
}

CoachAthleteLink _link(String id, String userId, String? name) =>
    CoachAthleteLink(
      id: id,
      status: 'active',
      note: null,
      createdAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
      userId: userId,
      displayName: name,
      avatarUrl: null,
    );

Future<Preferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, ApiClient api, Preferences prefs) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachingScreen(api: api, preferences: prefs),
    ),
  );
  await tester.pump(); // let initState's _load future resolve
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  group('coachInviteLink', () {
    test('builds the accept URL with the default host', () {
      expect(
        coachInviteLink('abc123', webBase: ''),
        'https://threkir.com/coaching/accept/abc123',
      );
    });

    test('uses the provided base and trims a trailing slash', () {
      expect(
        coachInviteLink('tok', webBase: 'https://preview.threkir.com/'),
        'https://preview.threkir.com/coaching/accept/tok',
      );
    });
  });

  testWidgets('renders empty state when there are no athletes or coaches',
      (tester) async {
    final prefs = await _prefs();
    await _pump(tester, _FakeApi(), prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingNoAthletes), findsOneWidget);
    expect(find.text(l10n.coachingNoCoaches), findsOneWidget);
    expect(find.text(l10n.coachingInviteAnAthlete), findsOneWidget);
  });

  testWidgets('lists athletes and coaches', (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(
      athletes: [_link('l1', 'a1', 'Alice Runner')],
      coaches: [_link('l2', 'c1', 'Coach Bob')],
    );
    await _pump(tester, api, prefs);
    expect(find.text('Alice Runner'), findsOneWidget);
    expect(find.text('Coach Bob'), findsOneWidget);
  });

  testWidgets('shows a pending invite with copy/share/revoke actions',
      (tester) async {
    final prefs = await _prefs();
    final api = _FakeApi(pending: [
      PendingCoachInvite(
        id: 'inv-1',
        inviteToken: 'tok-1',
        note: null,
        createdAt: DateTime.utc(2026, 1, 5),
      ),
    ]);
    await _pump(tester, api, prefs);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.coachingPendingInvite), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });
}

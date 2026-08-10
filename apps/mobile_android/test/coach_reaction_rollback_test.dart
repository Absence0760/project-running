// The thumbs up/down on a coach message writes optimistically. The rollback
// used to compare the message's reaction against the value it had *just* been
// set to, which is always equal — so a failed write left the thumb lit as if
// it had landed, and the catch reported nothing at all.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/training_service.dart';
import 'realtime_drain.dart';

class _ReactionApi extends ApiClient {
  _ReactionApi({required this.throwOnReact, this.seededReaction});

  final bool throwOnReact;
  final String? seededReaction;
  final List<String?> writes = [];

  @override
  String? get userId => 'u-viewer';

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => const {
        'ai_disclosure_version': 2,
        'coach_consent_at': '2026-01-01T00:00:00Z',
      };

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async => [
        CoachMessageRow(
          id: 'm-1',
          userId: 'u-viewer',
          role: 'assistant',
          content: 'Run easy today.',
          createdAt: DateTime.utc(2026, 3, 1, 10),
          reaction: seededReaction,
        ),
      ];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => [];

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;

  @override
  Future<void> setCoachReaction({
    required String messageId,
    String? reaction,
  }) async {
    writes.add(reaction);
    if (throwOnReact) throw Exception('boom');
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

Future<void> _pump(WidgetTester tester, _ReactionApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(api: api, training: TrainingService()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

Color _thumbColour(WidgetTester tester, String tooltip) {
  final icon = tester.widget<Icon>(
    find.descendant(
      of: find.byTooltip(tooltip),
      matching: find.byType(Icon),
    ),
  );
  return icon.color!;
}

Future<void> _tapThumb(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(_ensureSupabase);

  realtimeWidgetTest('a failed thumbs-up reverts to no reaction and says so',
      (tester) async {
    final api = _ReactionApi(throwOnReact: true);
    await _pump(tester, api);
    final resting = _thumbColour(tester, 'Helpful');

    await _tapThumb(tester, 'Helpful');

    expect(api.writes, ['up']);
    expect(_thumbColour(tester, 'Helpful'), resting,
        reason: 'the thumb must not stay lit after a rejected write');
    expect(find.text("Couldn't save your reaction. Try again."), findsOneWidget);
  });

  realtimeWidgetTest('a failed switch reverts to the reaction already stored',
      (tester) async {
    final api = _ReactionApi(throwOnReact: true, seededReaction: 'down');
    await _pump(tester, api);
    final litDown = _thumbColour(tester, 'Not helpful');

    await _tapThumb(tester, 'Helpful');

    expect(api.writes, ['up']);
    expect(_thumbColour(tester, 'Not helpful'), litDown,
        reason: 'the previous reaction must come back, not the rejected one');
  });

  realtimeWidgetTest('a successful thumbs-up sticks and reports nothing',
      (tester) async {
    final api = _ReactionApi(throwOnReact: false);
    await _pump(tester, api);
    final resting = _thumbColour(tester, 'Helpful');

    await _tapThumb(tester, 'Helpful');

    expect(api.writes, ['up']);
    expect(_thumbColour(tester, 'Helpful'), isNot(resting));
    expect(find.text("Couldn't save your reaction. Try again."), findsNothing);
  });
}

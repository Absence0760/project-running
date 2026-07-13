import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/training_service.dart';

/// Drives the empty-state suggestion branch: a consented viewer with a
/// configurable run count and no plan, so `_buildScroll` picks the
/// brand-new-runner chips when `runCount == 0` (mirrors web CoachChat's
/// `contextSummary?.runCount === 0` branch).
class _FakeApi extends ApiClient {
  final int runs;
  _FakeApi({required this.runs});

  @override
  String? get userId => 'u1';

  @override
  Future<DateTime?> fetchCoachConsentAt() async => DateTime(2026, 1, 1);

  @override
  Future<int> countRunsForUser(String userId, {int limit = 100}) async => runs;

  @override
  Future<Map<String, dynamic>?> fetchUserSettingsPrefs(String userId) async =>
      const <String, dynamic>{};

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;
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

Future<void> _pump(WidgetTester tester, {required int runs}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(api: _FakeApi(runs: runs), training: TrainingService()),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(_ensureSupabase);

  group('CoachScreen — empty-state suggestions', () {
    testWidgets('a brand-new runner (zero runs, no plan) sees the '
        'new-runner chips, not the tempo / last-run prompts', (tester) async {
      await _pump(tester, runs: 0);
      await _settle(tester);

      expect(find.text("I've never run before — where do I start?"),
          findsOneWidget);
      expect(find.text('Is it OK to walk during my runs?'), findsOneWidget);
      // The jargon / no-history prompts must NOT show for a zero-run user.
      expect(find.text('What is a tempo run?'), findsNothing);
      expect(find.text('How was my last run?'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a runner with history + no plan keeps the no-plan chips',
        (tester) async {
      await _pump(tester, runs: 12);
      await _settle(tester);

      expect(find.text('What is a tempo run?'), findsOneWidget);
      expect(find.text("I've never run before — where do I start?"),
          findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}

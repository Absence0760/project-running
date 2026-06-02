import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/training_service.dart';

/// Reports a non-null consent timestamp so the screen renders its main
/// (consented) Scaffold — the one whose left drawer used to swallow the
/// back button — instead of the GDPR consent gate.
class _ConsentedApi extends ApiClient {
  @override
  Future<DateTime?> fetchCoachConsentAt() async => DateTime(2026, 1, 1);
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

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(
        api: ApiClient(),
        training: TrainingService(),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('CoachScreen — initial render', () {
    testWidgets('renders the Coach app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Coach'), findsOneWidget);
      // The screen schedules a 50ms post-frame timer for streaming;
      // pump past it before the test ends so the framework's
      // pending-timer invariant doesn't trip.
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('the consented view renders an explicit back button (the left '
        'drawer used to swallow it)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CoachScreen(api: _ConsentedApi(), training: TrainingService()),
        ),
      );
      // Let the consent lookup resolve so the main Scaffold mounts.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The archive drawer is reachable from an explicit history action
      // instead, so the leading slot stays a real back affordance.
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('does not render the plan-switcher dropdown when there is at most one plan',
        (tester) async {
      // Reason: the title-row dropdown only mounts when _plans has
      // more than one entry — in tests there's no Supabase data so
      // the list stays empty and the dropdown stays hidden.
      await _pump(tester);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('without coach_consent_at the chat is gated behind the GDPR '
        'disclosure (audit/gdpr 2026-05-25)', (tester) async {
      // Reason: Coach forwards health-adjacent data to Anthropic
      // (US sub-processor) — GDPR Art 6(1)(a) requires an
      // affirmative consent act before the first dispatch. The
      // _bootstrap fetch fails against the unconnected local
      // Supabase, so _consentAt resolves to null, which must render
      // the disclosure copy instead of the chat composer.
      await _pump(tester);
      // Pump past the post-frame fetch attempt + the 100ms safety
      // margin to let _consentChecked flip true on failure.
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Before you chat with Coach'),
        findsOneWidget,
        reason: 'consent disclosure must be visible when '
            'coach_consent_at is null — see audit/gdpr (2026-05-25).',
      );
      expect(
        find.text('I consent — start Coach'),
        findsOneWidget,
        reason: 'the I-consent CTA must be reachable from the '
            'gate so the user can accept.',
      );
      // Settle pending timers before exit.
      await tester.pump(const Duration(milliseconds: 200));
    });
  });
}

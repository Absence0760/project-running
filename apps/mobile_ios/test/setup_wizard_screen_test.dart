import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/onboarding.dart';
import '../lib/preferences.dart';
import '../lib/screens/setup_wizard_screen.dart';

/// Records the two onboarding writes so the flow can be asserted without a
/// live Supabase. Every other ApiClient method is left to the base class.
class _FakeApi extends ApiClient {
  bool markOnboardedCalled = false;
  bool completeOnboardingCalled = false;
  String? completedDisplayName;
  String? completedUnit;
  bool? completedConsent;
  String? completedGender;
  DateTime? completedDob;

  /// Simulates zero connectivity — both stamp writes throw, like the
  /// real client does when the server is unreachable (issue #246).
  bool failWrites = false;

  @override
  String? get userId => 'u1';

  @override
  Future<void> markOnboarded() async {
    if (failWrites) throw Exception('network unreachable');
    markOnboardedCalled = true;
  }

  @override
  Future<void> completeOnboarding({
    String? displayName,
    required String preferredUnit,
    DateTime? dateOfBirth,
    String? gender,
    required bool healthDataConsent,
  }) async {
    if (failWrites) throw Exception('network unreachable');
    completeOnboardingCalled = true;
    completedDisplayName = displayName;
    completedUnit = preferredUnit;
    completedDob = dateOfBirth;
    completedGender = gender;
    completedConsent = healthDataConsent;
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
  Preferences prefs, {
  Locale? locale,
  String? initialPreferredUnit,
}) async {
  // Host under a Navigator with a base route so the wizard's pop-on-finish
  // has somewhere to land (it's pushed as a fullscreen route in the app).
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SetupWizardScreen(
                    apiClient: api,
                    preferences: prefs,
                    settingsSync: null,
                    initialPreferredUnit: initialPreferredUnit,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('SetupWizardScreen', () {
    testWidgets('renders the first step + a Skip header action', (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.setupNameTitle), findsOneWidget);
      expect(find.text(l10n.setupSkip), findsOneWidget);
    });

    testWidgets('Skip header stamps onboarded_at only (markOnboarded)',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.setupSkip));
      await tester.pumpAndSettle();
      expect(api.markOnboardedCalled, isTrue);
      expect(api.completeOnboardingCalled, isFalse);
    });

    testWidgets('Continue advances through every step to Open dashboard',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Walk all steps via Continue; the final step shows Open dashboard.
      for (var i = 0; i < onboardingTotalSteps - 1; i++) {
        await tester.tap(find.text(l10n.setupContinue));
        await tester.pumpAndSettle();
      }
      expect(find.text(l10n.setupOpenDashboard), findsOneWidget);
    });

    testWidgets(
        'final step with a goal offers one primary CTA, not two competing buttons',
        (tester) async {
      // Reason (#261): the goal-keyed "Create my training plan" CTA and the
      // nav "Open dashboard" were both FilledButtons, and the hint told the
      // runner to "tap Open dashboard" — two competing primaries + a mismatched
      // hint. The CTA must be the single primary; Open dashboard demotes to a
      // secondary outlined action and the hint names the primary.
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Advance to the goal step (index 2) and pick a goal.
      await tester.tap(find.text(l10n.setupContinue));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.setupContinue));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l10n.setupGoal5k));
      await tester.pump();
      await tester.tap(find.text(l10n.setupGoal5k));
      await tester.pump();
      // Advance to the final step.
      for (var i = 2; i < onboardingTotalSteps - 1; i++) {
        await tester.tap(find.text(l10n.setupContinue));
        await tester.pumpAndSettle();
      }
      expect(find.widgetWithText(FilledButton, l10n.setupCreatePlanCta),
          findsOneWidget);
      expect(find.widgetWithText(FilledButton, l10n.setupOpenDashboard),
          findsNothing);
      expect(find.widgetWithText(OutlinedButton, l10n.setupOpenDashboard),
          findsOneWidget);
      expect(find.text(l10n.setupDoneHintGoal), findsOneWidget);
    });

    testWidgets('Finish persists the answers via completeOnboarding',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Step 1: name.
      await tester.enterText(find.byType(TextField).first, 'Alex Runner');
      await tester.tap(find.text(l10n.setupContinue));
      await tester.pumpAndSettle();
      // Step 2: pick miles.
      await tester.tap(find.text(l10n.setupUnitMi));
      await tester.pump();
      await tester.tap(find.text(l10n.setupContinue));
      await tester.pumpAndSettle();
      // Remaining steps: just advance.
      for (var i = 2; i < onboardingTotalSteps - 1; i++) {
        await tester.tap(find.text(l10n.setupContinue));
        await tester.pumpAndSettle();
      }
      // Final step: Open dashboard. Settle the success toast's timer +
      // the pop animation so no timer outlives the disposed tree.
      await tester.tap(find.text(l10n.setupOpenDashboard));
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(api.completeOnboardingCalled, isTrue);
      expect(api.completedDisplayName, 'Alex Runner');
      expect(api.completedUnit, 'mi');
      // No DOB / gender chosen → consent stays false (Art 9 not granted).
      expect(api.completedConsent, isFalse);
    });

    testWidgets(
        'health-consent checkbox only appears after a demographic is entered',
        (tester) async {
      final api = _FakeApi();
      await _pump(tester, api, await _prefs());
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      // Advance to the About-you step (step index 3).
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(l10n.setupContinue));
        await tester.pumpAndSettle();
      }
      // No demographic chosen yet → no consent checkbox.
      expect(find.byType(CheckboxListTile), findsNothing);
      // Choose a gender → the Art 9 consent checkbox surfaces.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.setupGenderFemale).last);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    group('offline fail-safe exit (issue #246)', () {
      testWidgets(
          'a failing Skip reveals Finish later, which dismisses the wizard '
          'with zero connectivity', (tester) async {
        final api = _FakeApi()..failWrites = true;
        final prefs = await _prefs();
        await _pump(tester, api, prefs);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        // No fail-safe exit before a save ever failed — the normal exits
        // own the happy path.
        expect(find.text(l10n.setupFinishLater), findsNothing);

        await tester.tap(find.text(l10n.setupSkip));
        // Drain the failure banner's auto-dismiss timer.
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Still trapped on the wizard (canPop is false) — but the
        // fail-safe exit is now offered.
        expect(find.text(l10n.setupPageTitle), findsOneWidget);
        expect(find.text(l10n.setupFinishLater), findsOneWidget);

        await tester.tap(find.text(l10n.setupFinishLater));
        await tester.pumpAndSettle();

        // The wizard popped without any server write, and the dismissal
        // was recorded locally so the gate defers the stamp instead of
        // re-pushing the wizard.
        expect(find.text(l10n.setupPageTitle), findsNothing);
        expect(find.text('open'), findsOneWidget);
        expect(prefs.setupWizardDismissed, isTrue);
        expect(api.markOnboardedCalled, isFalse);
      });

      testWidgets('a failing Finish reveals the same fail-safe exit',
          (tester) async {
        final api = _FakeApi()..failWrites = true;
        final prefs = await _prefs();
        await _pump(tester, api, prefs);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));

        for (var i = 0; i < onboardingTotalSteps - 1; i++) {
          await tester.tap(find.text(l10n.setupContinue));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(find.text(l10n.setupFinishLater), findsOneWidget);

        await tester.tap(find.text(l10n.setupFinishLater));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
        expect(prefs.setupWizardDismissed, isTrue);
      });
    });

    group('locale-derived unit default', () {
      Future<void> finish(WidgetTester tester, AppLocalizations l10n) async {
        for (var i = 0; i < onboardingTotalSteps - 1; i++) {
          await tester.tap(find.text(l10n.setupContinue));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(l10n.setupOpenDashboard));
        await tester.pumpAndSettle(const Duration(seconds: 4));
      }

      void setDeviceLocale(WidgetTester tester, Locale locale) {
        tester.platformDispatcher.localeTestValue = locale;
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      }

      testWidgets('en_US device locale seeds miles when no unit was chosen',
          (tester) async {
        final api = _FakeApi();
        setDeviceLocale(tester, const Locale('en', 'US'));
        await _pump(tester, api, await _prefs(), locale: const Locale('en'));
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await finish(tester, l10n);
        expect(api.completedUnit, 'mi');
      });

      testWidgets('de_DE device locale seeds kilometres', (tester) async {
        final api = _FakeApi();
        setDeviceLocale(tester, const Locale('de', 'DE'));
        await _pump(tester, api, await _prefs(), locale: const Locale('en'));
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await finish(tester, l10n);
        expect(api.completedUnit, 'km');
      });

      testWidgets('an explicit prior choice overrides the locale seed',
          (tester) async {
        final api = _FakeApi();
        setDeviceLocale(tester, const Locale('en', 'US'));
        await _pump(tester, api, await _prefs(),
            locale: const Locale('en'), initialPreferredUnit: 'km');
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await finish(tester, l10n);
        expect(api.completedUnit, 'km');
      });
    });
  });
}

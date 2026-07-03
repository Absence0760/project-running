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

  @override
  String? get userId => 'u1';

  @override
  Future<void> markOnboarded() async {
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

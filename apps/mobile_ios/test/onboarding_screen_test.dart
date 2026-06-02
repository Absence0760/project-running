import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/onboarding_screen.dart';

/// Stub the geolocator platform channel so the final-page "Grant
/// permission" tap doesn't blow up on the missing native impl. Return
/// `always` (index 3) for checkPermission so the flow skips
/// requestPermission and proceeds straight to completion.
void _mockGeolocator(WidgetTester tester) {
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
      (call) async {
    if (call.method == 'checkPermission') return 3; // LocationPermission.always
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  VoidCallback? onDone,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OnboardingScreen(
        preferences: prefs,
        onDone: onDone ?? () {},
      ),
    ),
  );
}

void main() {
  group('OnboardingScreen', () {
    testWidgets('renders the first page title and description',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      expect(find.text('Track every run'), findsOneWidget);
      expect(find.byIcon(Icons.directions_run), findsOneWidget);
    });

    testWidgets('first-page CTA reads "Next"', (tester) async {
      // Reason: only the final page swaps to "Grant permission" — if
      // the first page already says that, the location prompt would
      // fire too early.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Grant permission'), findsNothing);
    });

    testWidgets('renders four page indicator dots (3 info + privacy)',
        (tester) async {
      // Reason: the indicator row is generated from _pageCount —
      // 4 dots means the three info pages + the privacy chooser are
      // all wired up (persona #56).
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      expect(find.byType(AnimatedContainer), findsNWidgets(4));
    });

    testWidgets('page-indicator animates over 200ms by default (WCAG 2.3.3)',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      final dots = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      for (final d in dots) {
        expect(d.duration, const Duration(milliseconds: 200));
      }
    });

    testWidgets(
        'page-indicator collapses to instant swap under reduce-motion '
        '(WCAG 2.3.3)', (tester) async {
      final prefs = await _makePrefs();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: OnboardingScreen(preferences: prefs, onDone: () {}),
          ),
        ),
      );
      final dots = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(dots, isNotEmpty);
      for (final d in dots) {
        expect(d.duration, Duration.zero);
      }
    });

    testWidgets('tapping Next advances to the second page', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Follow routes'), findsOneWidget);
      expect(find.byIcon(Icons.route), findsOneWidget);
    });

    testWidgets('the location page keeps the "Next" CTA (not the final page)',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.tap(find.text('Next')); // → Follow routes
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next')); // → Location access
      await tester.pumpAndSettle();
      expect(find.text('Location access'), findsOneWidget);
      // The privacy chooser now follows, so location is no longer final.
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Grant permission'), findsNothing);
    });

    testWidgets('the privacy chooser is the final page with the grant CTA',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Who sees your runs?'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Followers'), findsOneWidget);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Grant permission'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
    });

    testWidgets('completing onboarding persists the chosen privacy default',
        (tester) async {
      _mockGeolocator(tester);
      final prefs = await _makePrefs();
      var done = false;
      await _pump(tester, prefs: prefs, onDone: () => done = true);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      // Pick a non-default option, then finish.
      await tester.tap(find.text('Followers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grant permission'));
      await tester.pumpAndSettle();
      expect(prefs.privacyDefault, 'followers');
      expect(prefs.onboarded, isTrue);
      expect(done, isTrue);
    });

    testWidgets('privacy default is private until the user changes it',
        (tester) async {
      _mockGeolocator(tester);
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs, onDone: () {});
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Grant permission'));
      await tester.pumpAndSettle();
      expect(prefs.privacyDefault, 'private');
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';
import '../lib/widgets/safety_nudge_banner.dart';
import '../lib/widgets/workout_execution_band.dart';

Future<void> _pump(
  WidgetTester tester, {
  double? offRouteMetres,
  bool permissionLost = false,
  bool gpsLost = false,
  bool weakGps = false,
  bool safetyNudgeVisible = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: RunTopBanners(
            offRouteMetres: offRouteMetres,
            permissionLost: permissionLost,
            gpsLost: gpsLost,
            weakGps: weakGps,
            safetyNudgeVisible: safetyNudgeVisible,
            onSafetyNudgeShare: () {},
            onSafetyNudgeDismiss: () {},
          ),
        ),
      ),
    ),
  );
}

Rect _cardOf(WidgetTester tester, String text) => tester.getRect(
    find.ancestor(of: find.text(text), matching: find.byType(Card)).first);

const _offRoute = 'Off route — 120m away';
const _gpsLost = 'GPS signal lost — move to open sky';

void main() {
  testWidgets('off-route + GPS-lost render together without overlapping '
      '(issue #666 V10)', (tester) async {
    await _pump(tester, offRouteMetres: 120, gpsLost: true);
    expect(find.text(_offRoute), findsOneWidget);
    expect(find.text(_gpsLost), findsOneWidget);
    final offRoute = _cardOf(tester, _offRoute);
    final gps = _cardOf(tester, _gpsLost);
    expect(offRoute.overlaps(gps), isFalse);
    expect(offRoute.bottom, lessThanOrEqualTo(gps.top));
  });

  testWidgets('all three layers stack vertically: off-route, status, nudge',
      (tester) async {
    await _pump(tester,
        offRouteMetres: 120, gpsLost: true, safetyNudgeVisible: true);
    final offRoute = _cardOf(tester, _offRoute);
    final gps = _cardOf(tester, _gpsLost);
    final nudge = tester.getRect(find.byType(SafetyNudgeBanner));
    expect(offRoute.overlaps(gps), isFalse);
    expect(offRoute.overlaps(nudge), isFalse);
    expect(gps.overlaps(nudge), isFalse);
    expect(offRoute.bottom, lessThanOrEqualTo(gps.top));
    expect(gps.bottom, lessThanOrEqualTo(nudge.top));
  });

  testWidgets('status banners stay mutually exclusive: permission wins',
      (tester) async {
    await _pump(tester,
        permissionLost: true, gpsLost: true, weakGps: true);
    expect(find.text('Location permission revoked'), findsOneWidget);
    expect(find.text(_gpsLost), findsNothing);
    expect(find.text('Weak GPS — distance paused'), findsNothing);
  });

  testWidgets('weak GPS shows alone when nothing outranks it',
      (tester) async {
    await _pump(tester, weakGps: true);
    expect(find.text('Weak GPS — distance paused'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('renders nothing when no banner is active', (tester) async {
    await _pump(tester);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(SafetyNudgeBanner), findsNothing);
  });

  group('RunTopOverlay — the armed-workout case (issue #666 A3)', () {
    testWidgets('the workout band stacks above the badges and the banners, '
        'never over them', (tester) async {
      await _pumpOverlay(tester, armed: true, offRouteMetres: 120,
          gpsLost: true);

      final band = tester.getRect(find.byType(WorkoutExecutionBand));
      final badge = tester.getRect(find.byKey(_badgeKey));
      final offRoute = _cardOf(tester, _offRoute);
      final gps = _cardOf(tester, _gpsLost);

      // Pre-fix the band was its own Positioned anchored on the status-bar
      // inset, so it painted straight over the top: 56 badge row.
      expect(band.overlaps(badge), isFalse);
      expect(band.overlaps(offRoute), isFalse);
      expect(band.overlaps(gps), isFalse);
      expect(band.bottom, lessThanOrEqualTo(badge.top));
      expect(badge.bottom, lessThanOrEqualTo(offRoute.top));
      expect(offRoute.bottom, lessThanOrEqualTo(gps.top));
    });

    testWidgets('no workout armed leaves the badges at the column top',
        (tester) async {
      await _pumpOverlay(tester, armed: false, offRouteMetres: 120);
      expect(find.byType(WorkoutExecutionBand), findsNothing);
      final badge = tester.getRect(find.byKey(_badgeKey));
      expect(badge.top, RunTopOverlay.topInset);
    });

    testWidgets('the column clears a status-bar inset taller than the default',
        (tester) async {
      const tall = RunTopOverlay.topInset + 20;
      await _pumpOverlay(tester, armed: true, topPadding: tall);
      expect(tester.getRect(find.byType(WorkoutExecutionBand)).top, tall);
    });
  });
}

const _badgeKey = ValueKey<String>('badges');

WorkoutBandState _bandState() => WorkoutBandState(
      step: WorkoutStep(
        kind: WorkoutStepKind.rep,
        targetDistanceMetres: 400,
        targetPaceSecPerKm: 240,
        label: 'Rep 3/6',
        repIndex: 3,
        repTotal: 6,
      ),
      totalSteps: 14,
      currentIndex: 4,
      progress: 0.25,
      remainingMetres: 300,
      actualPaceSecPerKm: 235,
      adherence: PaceAdherence.ahead,
      complete: false,
      abandoned: false,
    );

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required bool armed,
  double? offRouteMetres,
  bool gpsLost = false,
  double topPadding = 0,
}) {
  final notifier = ValueNotifier<WorkoutBandState>(_bandState());
  addTearDown(notifier.dispose);
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(padding: EdgeInsets.only(top: topPadding)),
        child: Scaffold(
          body: Stack(
            children: [
              RunTopOverlay(
                workoutBand: armed
                    ? WorkoutExecutionBand(
                        state: notifier,
                        onSkip: () {},
                        onRewind: () {},
                        onAbandon: () {},
                      )
                    : null,
                badges: const SizedBox(key: _badgeKey, height: 40),
                banners: RunTopBanners(
                  offRouteMetres: offRouteMetres,
                  permissionLost: false,
                  gpsLost: gpsLost,
                  weakGps: false,
                  safetyNudgeVisible: false,
                  onSafetyNudgeShare: () {},
                  onSafetyNudgeDismiss: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

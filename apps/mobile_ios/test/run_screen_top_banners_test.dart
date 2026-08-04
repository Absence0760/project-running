import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';
import '../lib/widgets/safety_nudge_banner.dart';

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
}

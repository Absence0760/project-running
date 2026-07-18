import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/guided_runs_screen.dart';

void main() {
  testWidgets(
      'list reserves bottom padding beyond the system gesture-nav inset',
      (tester) async {
    // Regression: a flat `vertical: 8` padding left the last card
    // crowded right against the bottom of the screen, with no
    // clearance for the gesture-nav bar on devices that have one.
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GuidedRunsScreen(),
      ),
    );

    final listView = tester.widget<ListView>(find.byType(ListView));
    final padding = listView.padding as EdgeInsets;
    expect(padding.bottom, greaterThanOrEqualTo(24 + 34),
        reason: 'Bottom padding must clear the safe-area inset plus '
            'breathing room, not just a flat constant.');
  });
}

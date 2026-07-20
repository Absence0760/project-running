import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_screen.dart';

Future<void> _pumpButton(
  WidgetTester tester, {
  required VoidCallback onHoldComplete,
  bool showHint = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: HoldToStopButton(
            onHoldComplete: onHoldComplete,
            showHint: showHint,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the "hold to stop" hint and no ring at rest',
      (tester) async {
    await _pumpButton(tester, onHoldComplete: () {});

    expect(find.text('Hold to stop'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('hides the hint when showHint is false', (tester) async {
    await _pumpButton(tester, onHoldComplete: () {}, showHint: false);

    expect(find.text('Hold to stop'), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('a short tap does not stop the run', (tester) async {
    var stopped = false;
    await _pumpButton(tester, onHoldComplete: () => stopped = true);

    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump(const Duration(milliseconds: 50));

    expect(stopped, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('holding advances the progress ring, then stops the run',
      (tester) async {
    var stopped = false;
    await _pumpButton(tester, onHoldComplete: () => stopped = true);

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.stop_rounded)));
    // Advance partway through the hold window in small steps: the ring should
    // become visible and partly filled, but the run not yet stopped. The first
    // frames establish the ticker baseline before progress starts advancing.
    final ringFinder = find.byType(CircularProgressIndicator);
    for (var i = 0; i < 4 && ringFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(ringFinder, findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(ringFinder);
    expect(ring.value, isNotNull);
    expect(ring.value!, greaterThan(0.0));
    expect(ring.value!, lessThan(1.0));
    expect(stopped, isFalse);

    // Cross the full hold threshold.
    await tester.pump(const Duration(milliseconds: 900));
    expect(stopped, isTrue);

    await gesture.up();
    await tester.pump();
  });
}

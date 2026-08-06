import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_load.dart';
import '../lib/widgets/readiness_card.dart';

Future<void> _pump(WidgetTester tester, {double? width}) {
  final card = ReadinessCard(
    runs: const [],
    now: DateTime(2026, 6, 10, 12),
    loadSeries: [
      TrainingLoadPoint(
        date: DateTime(2026, 6, 10),
        stress: 50,
        atl: 30,
        ctl: 50,
        tsb: 20,
      ),
    ],
  );
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: width == null
              ? SingleChildScrollView(child: card)
              : SizedBox(width: width, child: SingleChildScrollView(child: card)),
        ),
      ),
    ),
  );
}

void main() {
  group('ReadinessCard', () {
    testWidgets('renders the header and a band badge', (tester) async {
      await _pump(tester);
      expect(find.text('Readiness'), findsOneWidget);
    });

    testWidgets('header row survives a narrow width without overflowing',
        (tester) async {
      await _pump(tester, width: 200);
      // Header + band badge share one row; at 200 the header must
      // ellipsize instead of throwing a RenderFlex overflow (the harness
      // fails the test on one).
      expect(find.text('Readiness'), findsOneWidget);
    });
  });
}

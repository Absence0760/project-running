import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/live_cutoff_eta.dart';
import '../lib/widgets/cutoff_card.dart';

/// Pins the shared `CutoffCard` render contract. The card is rendered by BOTH
/// the live spectator screen and the runner's own recording screen, so its
/// four states are guarded here in isolation (the spectator + runner wiring
/// tests exercise it in context).

Future<void> _pump(WidgetTester tester, LiveCutoffEta eta, bool stale) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: CutoffCard(eta: eta, stale: stale)),
    ),
  );
}

LiveCutoffEta _eta({
  required LiveCutoffStatus status,
  double distanceToM = 1500,
  double? projectedArrivalElapsedS,
  double? marginS,
  String label = 'Aid 1',
}) =>
    LiveCutoffEta(
      checkpoint: LiveCutoffCheckpoint(kind: 'cutoff', label: label),
      distanceToM: distanceToM,
      projectedArrivalElapsedS: projectedArrivalElapsedS,
      marginS: marginS,
      status: status,
    );

void main() {
  group('CutoffCard', () {
    testWidgets('on-pace shows a "to spare" margin chip + projected arrival',
        (tester) async {
      await _pump(
        tester,
        _eta(
          status: LiveCutoffStatus.on,
          marginS: 25 * 60,
          projectedArrivalElapsedS: 2 * 3600 + 34 * 60,
        ),
        false,
      );
      expect(find.text('Aid 1'), findsOneWidget);
      expect(find.textContaining('to spare'), findsOneWidget);
      expect(find.textContaining('2:34:00'), findsOneWidget);
      expect(find.textContaining('Signal lost'), findsNothing);
    });

    testWidgets('behind shows the "behind" chip', (tester) async {
      await _pump(
        tester,
        _eta(
          status: LiveCutoffStatus.behind,
          marginS: -12 * 60,
          projectedArrivalElapsedS: 3 * 3600,
        ),
        false,
      );
      expect(find.textContaining('behind'), findsOneWidget);
      expect(find.textContaining('to spare'), findsNothing);
    });

    testWidgets('unknown + stale reads the amber signal-lost line',
        (tester) async {
      await _pump(tester, _eta(status: LiveCutoffStatus.unknown), true);
      expect(find.textContaining('Signal lost'), findsOneWidget);
      expect(find.textContaining('Waiting for a fresh signal'), findsNothing);
      final lost = tester.widget<Text>(find.textContaining('Signal lost'));
      expect(lost.style?.color, const Color(0xFFF59E0B));
    });

    testWidgets('unknown + fresh keeps the neutral waiting line',
        (tester) async {
      await _pump(tester, _eta(status: LiveCutoffStatus.unknown), false);
      expect(find.textContaining('Waiting for a fresh signal'), findsOneWidget);
      expect(find.textContaining('Signal lost'), findsNothing);
      expect(find.textContaining('to spare'), findsNothing);
    });
  });
}

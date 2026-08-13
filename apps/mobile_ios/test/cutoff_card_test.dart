import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors;

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
  double? requiredPaceSecPerKm,
  bool limitPassed = false,
  String label = 'Aid 1',
}) =>
    LiveCutoffEta(
      checkpoint: LiveCutoffCheckpoint(kind: 'cutoff', label: label),
      distanceToM: distanceToM,
      projectedArrivalElapsedS: projectedArrivalElapsedS,
      marginS: marginS,
      requiredPaceSecPerKm: requiredPaceSecPerKm,
      limitPassed: limitPassed,
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
      expect(lost.style?.color, AppSemanticColors.light.warning);
    });

    testWidgets('unknown + fresh keeps the neutral waiting line',
        (tester) async {
      await _pump(tester, _eta(status: LiveCutoffStatus.unknown), false);
      expect(find.textContaining('Waiting for a fresh signal'), findsOneWidget);
      expect(find.textContaining('Signal lost'), findsNothing);
      expect(find.textContaining('to spare'), findsNothing);
    });

    testWidgets('chip + projection row survives a narrow width without '
        'overflowing', (tester) async {
      await tester.binding.setSurfaceSize(const Size(220, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(
        tester,
        _eta(
          status: LiveCutoffStatus.on,
          marginS: 25 * 60,
          projectedArrivalElapsedS: 2 * 3600 + 34 * 60,
        ),
        false,
      );
      // The margin chip and the projected-arrival text share one row; at
      // 220 the chip must ellipsize instead of throwing a RenderFlex
      // overflow (the harness fails the test on one).
      expect(find.textContaining('to spare'), findsOneWidget);
    });

    testWidgets('an expired limit is stated, not left behind "signal lost"',
        (tester) async {
      // The deadline is gone whether or not the fix is current, and it is the
      // fact the crew at the checkpoint is deciding on. It must show ALONGSIDE
      // the signal-lost line, not be replaced by it.
      await _pump(
        tester,
        _eta(status: LiveCutoffStatus.unknown, limitPassed: true),
        true,
      );
      expect(find.textContaining('Cut-off time has passed'), findsOneWidget);
      expect(find.textContaining('Signal lost'), findsOneWidget);
      expect(find.textContaining('Needs'), findsNothing);
    });

    testWidgets('a stale fix still reports the pace needed, from the last fix',
        (tester) async {
      // requiredPace does not depend on recent pace, so suppressing the
      // verdict must not suppress the go/no-go number. Labelling it "from the
      // last fix" keeps it from reading as measured from where they are now.
      await _pump(
        tester,
        _eta(status: LiveCutoffStatus.unknown, requiredPaceSecPerKm: 390),
        true,
      );
      expect(find.textContaining('from the last fix'), findsOneWidget);
      expect(find.textContaining('Signal lost'), findsOneWidget);
      expect(find.textContaining('Cut-off time has passed'), findsNothing);
    });

    testWidgets('a fresh behind verdict reports the pace needed from here',
        (tester) async {
      await _pump(
        tester,
        _eta(
          status: LiveCutoffStatus.behind,
          marginS: -10 * 60,
          projectedArrivalElapsedS: 3600,
          requiredPaceSecPerKm: 390,
        ),
        false,
      );
      expect(find.textContaining('from here'), findsOneWidget);
      expect(find.textContaining('behind'), findsOneWidget);
    });

    testWidgets('a comfortable on-pace card stays free of required-pace noise',
        (tester) async {
      await _pump(
        tester,
        _eta(
          status: LiveCutoffStatus.on,
          marginS: 25 * 60,
          projectedArrivalElapsedS: 2 * 3600,
          requiredPaceSecPerKm: 900,
        ),
        false,
      );
      expect(find.textContaining('Needs'), findsNothing);
      expect(find.textContaining('to spare'), findsOneWidget);
    });
  });
}

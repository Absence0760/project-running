import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/run_screen.dart';

void main() {
  group('StatColumn — overflow safety', () {
    testWidgets(
      'four wide-value columns in a Row at a narrow width do not overflow',
      (tester) async {
        // Mimic the finished-run summary: four StatColumns in a Row, each
        // Expanded, on a deliberately cramped width with values wide enough
        // (a multi-hour time, a 4-digit ultra distance, a long pace+unit
        // pair) to overflow an unconstrained Text. The FittedBox scale-down
        // must keep them painting cleanly with no overflow stripe.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: Row(
                    children: const [
                      Expanded(
                        child: StatColumn(
                            label: 'Distance', value: '1234.56'),
                      ),
                      Expanded(
                        child: StatColumn(label: 'Time', value: '12:34:56'),
                      ),
                      Expanded(
                        child:
                            StatColumn(label: 'Moving', value: '12:30:01'),
                      ),
                      Expanded(
                        child: StatColumn(
                            label: 'Avg pace', value: '12:34', unit: '/km'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // tester.takeException() returns any exception thrown during the
        // frame (a RenderFlex overflow throws in test mode). It must be null.
        expect(tester.takeException(), isNull);
        expect(find.text('1234.56'), findsOneWidget);
        expect(find.text('12:34:56'), findsOneWidget);
        expect(find.text('/km'), findsOneWidget);
      },
    );

    testWidgets(
      'a long label is ellipsised rather than overflowing its column',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 60,
                  child: StatColumn(
                    // A long localized label (German compound words are the
                    // canonical case) must clip with an ellipsis, not paint
                    // an overflow stripe.
                    label: 'Durchschnittsgeschwindigkeit',
                    value: '10.0',
                    unit: 'km/h',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        final label = tester.widget<Text>(
          find.text('Durchschnittsgeschwindigkeit'),
        );
        expect(label.maxLines, 1);
        expect(label.overflow, TextOverflow.ellipsis);
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/widgets/error_state.dart';

Future<void> _pump(
  WidgetTester tester, {
  required String message,
  required VoidCallback onRetry,
  IconData icon = Icons.cloud_off,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ErrorState(
          message: message,
          onRetry: onRetry,
          icon: icon,
        ),
      ),
    ),
  );
}

void main() {
  group('ErrorState', () {
    testWidgets('renders the provided message text', (tester) async {
      await _pump(
        tester,
        message: 'Something went wrong loading your runs.',
        onRetry: () {},
      );
      expect(find.text('Something went wrong loading your runs.'),
          findsOneWidget);
    });

    testWidgets('renders a Retry button', (tester) async {
      await _pump(tester, message: 'Error', onRetry: () {});
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('calls onRetry callback when Retry button is tapped',
        (tester) async {
      var retried = 0;
      await _pump(tester, message: 'Error', onRetry: () => retried++);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('renders with a custom icon when supplied', (tester) async {
      await _pump(
        tester,
        message: 'No network',
        onRetry: () {},
        icon: Icons.wifi_off,
      );
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsNothing);
    });

    testWidgets('renders with the default cloud_off icon when none supplied',
        (tester) async {
      await _pump(tester, message: 'Error', onRetry: () {});
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plans_screen.dart';
import '../lib/training_service.dart';

Future<void> _pump(WidgetTester tester, {required TrainingService training}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlansScreen(training: training, apiClient: null),
    ),
  );
}

void main() {
  group('PlansScreen — not signed in', () {
    testWidgets('renders the Training plans app-bar title', (tester) async {
      final training = TrainingService();
      await _pump(tester, training: training);
      await tester.pump();
      expect(find.text('Training plans'), findsOneWidget);
    });

    testWidgets('shows the sign-in prompt body when apiClient is null',
        (tester) async {
      final training = TrainingService();
      await _pump(tester, training: training);
      await tester.pump();
      expect(find.text('Sign in to use training plans'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('hides the New plan FAB when apiClient is null',
        (tester) async {
      final training = TrainingService();
      await _pump(tester, training: training);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('New plan'), findsNothing);
    });

    testWidgets('does not render the loading spinner over the sign-in prompt',
        (tester) async {
      // Reason: the not-signed-in branch must short-circuit BEFORE the
      // _loading flag has a chance to surface a CircularProgressIndicator.
      final training = TrainingService();
      await _pump(tester, training: training);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

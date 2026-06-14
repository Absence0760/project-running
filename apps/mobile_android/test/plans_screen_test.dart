import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
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

class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'u';
}

class _FakeTraining extends TrainingService {
  _FakeTraining(this._plans, {this.throwOnUpdate = false});
  final List<TrainingPlanRow> _plans;
  final bool throwOnUpdate;
  int updateCalls = 0;
  String? lastUpdateStatus;

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async => _plans;

  @override
  Future<void> updateStatus(String id, String status) async {
    updateCalls++;
    lastUpdateStatus = status;
    if (throwOnUpdate) throw Exception('boom');
  }
}

TrainingPlanRow _activePlan() => TrainingPlanRow(
      id: 'p1',
      userId: 'u',
      name: 'Richmond Half',
      goalEvent: 'distance_half',
      goalDistanceM: 21097,
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 5, 24),
      daysPerWeek: 4,
      status: 'active',
      source: 'generated',
      isTemplate: false,
      isPublicTemplate: false,
    );

Future<void> _pumpSignedIn(WidgetTester tester, _FakeTraining training) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlansScreen(training: training, apiClient: _SignedInApi()),
    ),
  );
  await tester.pump();
  await tester.pump();
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

  group('PlansScreen — abandon confirm', () {
    testWidgets('abandoning an active plan asks for confirmation first',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();

      // Confirm dialog shows; nothing mutated yet.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Abandon "Richmond Half"?'), findsOneWidget);
      expect(training.updateCalls, 0);
    });

    testWidgets('cancelling the abandon dialog is a no-op', (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(training.updateCalls, 0);
    });

    testWidgets('confirming the abandon dialog updates the status',
        (tester) async {
      final training = _FakeTraining([_activePlan()]);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      // The confirm button shares the "Abandon" label with the tile —
      // scope to the dialog.
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pumpAndSettle();

      expect(training.updateCalls, 1);
      expect(training.lastUpdateStatus, 'abandoned');
    });

    testWidgets('a failed abandon surfaces a banner', (tester) async {
      final training = _FakeTraining([_activePlan()], throwOnUpdate: true);
      await _pumpSignedIn(tester, training);

      await tester.tap(find.text('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Abandon')));
      await tester.pumpAndSettle();

      expect(training.updateCalls, 1);
      expect(find.textContaining("Couldn't update the plan"), findsOneWidget);
      // showTopBanner leaves a 4s auto-dismiss timer — drain it.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

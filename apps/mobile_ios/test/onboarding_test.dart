import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/onboarding.dart';
import '../lib/training.dart';

/// Pure-contract twin of web `apps/web/src/lib/settings/onboarding.test.ts`.
/// Keeps the mobile setup-wizard enum + step count in lockstep with web.
void main() {
  group('onboarding contract', () {
    test('primaryGoalKey is the universal-prefs bag key the wizard writes', () {
      expect(primaryGoalKey, 'primary_goal');
      // And it's the SAME constant the SettingsKeys registry exposes, so a
      // rename can't silently split the writer from the reader.
      expect(primaryGoalKey, SettingsKeys.primaryGoal);
    });

    test('primaryGoalValues covers the fixed six-value enum, in order', () {
      expect(primaryGoalValues, [
        'general_fitness',
        'weight_loss',
        '5k',
        '10k',
        'half_marathon',
        'marathon',
      ]);
    });

    test('primaryGoalValues includes the four distance goals + two non-distance',
        () {
      for (final v in ['5k', '10k', 'half_marathon', 'marathon']) {
        expect(primaryGoalValues.contains(v), isTrue, reason: 'missing $v');
      }
      expect(primaryGoalValues.contains('general_fitness'), isTrue);
      expect(primaryGoalValues.contains('weight_loss'), isTrue);
      expect(primaryGoalValues.length, 6);
    });

    test('onboardingTotalSteps matches web (7)', () {
      expect(onboardingTotalSteps, 7);
    });

    test('planPresetForGoal maps distance goals 1:1 and seeds beginners into '
        'walk-run 5K', () {
      expect(planPresetForGoal('10k').goalEvent, GoalEvent.distance10k);
      expect(planPresetForGoal('10k').beginnerWalkRun, isFalse);
      expect(planPresetForGoal('half_marathon').goalEvent, GoalEvent.distanceHalf);
      expect(planPresetForGoal('marathon').goalEvent, GoalEvent.distanceFull);
      for (final v in ['5k', 'general_fitness', 'weight_loss']) {
        expect(planPresetForGoal(v).goalEvent, GoalEvent.distance5k,
            reason: '$v should seed the 5K');
        expect(planPresetForGoal(v).beginnerWalkRun, isTrue,
            reason: '$v should tick the walk-run toggle');
      }
    });

    test('ApiClient.dateOnly emits a zone-free YYYY-MM-DD calendar day', () {
      // A DOB is a calendar day, not an instant — the wizard must not let
      // a user east/west of UTC roll a day. Pad single digits.
      expect(ApiClient.dateOnly(DateTime(2001, 2, 3)), '2001-02-03');
      expect(ApiClient.dateOnly(DateTime(1990, 11, 25)), '1990-11-25');
      // A late-evening local instant keeps its local calendar day (no UTC
      // conversion that would advance to the next date).
      expect(ApiClient.dateOnly(DateTime(2001, 2, 3, 23, 30)), '2001-02-03');
    });
  });
}

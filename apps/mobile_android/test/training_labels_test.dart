import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training.dart';
import '../lib/training_labels.dart';

// Pins the localized workout-kind / plan-phase labels (audit/i18n-readiness
// W-4). The English values mirror the web catalogue keys workoutKind.* /
// planPhase.*; the de case proves the label follows the active locale.

void main() {
  test('workoutKindLabel / planPhaseLabel return the English catalogue values',
      () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(workoutKindLabel(en, WorkoutKind.easy), 'Easy');
    expect(workoutKindLabel(en, WorkoutKind.walkRun), 'Walk-run');
    expect(workoutKindLabel(en, WorkoutKind.marathonPace), 'Marathon pace');
    expect(planPhaseLabel(en, PlanPhase.base), 'Base');
    expect(planPhaseLabel(en, PlanPhase.race), 'Race week');
  });

  test('labels follow the active locale (de)', () async {
    final de = await AppLocalizations.delegate.load(const Locale('de'));
    expect(workoutKindLabel(de, WorkoutKind.easy), 'Locker');
    expect(workoutKindLabel(de, WorkoutKind.race), 'Wettkampf');
    expect(planPhaseLabel(de, PlanPhase.base), 'Grundlage');
  });
}

/// Post-signup setup-wizard contract — Dart twin of web
/// `apps/web/src/lib/settings/onboarding.ts`. Shared between the
/// [SetupWizardScreen] and the home-screen routing gate.
///
/// The `onboarded_at` column on `user_profiles` (migration
/// 20261016_001) is the single source of truth — null means the wizard
/// hasn't been seen yet. The wizard stamps `now()` on either Finish or
/// Skip, so a returning user never re-sees it.
library;

/// Universal-prefs bag key the wizard's Goal step writes into. Hard-coded
/// by name across the wizard + the (future) plan-suggestion surface, so a
/// rename without grepping every consumer would orphan the saved value.
/// Matches web's `PRIMARY_GOAL_KEY`.
const String primaryGoalKey = 'primary_goal';

/// Fixed enum the Goal step writes. The four distance goals map 1:1 to
/// `training.dart`'s goal-event enum so a future plan-creation flow can
/// translate without a mapping table; `general_fitness` + `weight_loss`
/// are the two non-distance targets. Mirrors web's `PRIMARY_GOAL_VALUES`
/// (order included).
const List<String> primaryGoalValues = [
  'general_fitness',
  'weight_loss',
  '5k',
  '10k',
  'half_marathon',
  'marathon',
];

/// Total wizard steps. Drives the progress-dot indicator + the per-step
/// navigation math. Mirrors web's `ONBOARDING_TOTAL_STEPS`.
const int onboardingTotalSteps = 7;

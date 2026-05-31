/// Onboarding wizard contract — shared between the `/onboarding` page,
/// the layout-level routing gate, and the Settings "finish setup"
/// nudge.
///
/// Persona-hunt finding (new-runner persona finding-area #1):
/// "after sign-up the persona is dropped at an empty dashboard with
/// no guidance." The wizard walks through display name, units, goal,
/// optional demographics (gender + DOB + weight with GDPR Art 9
/// consent), privacy default, and push notifications.
///
/// The `onboarded_at` column on `user_profiles` (migration
/// 20261016_001) is the single source of truth — null means the
/// wizard hasn't been seen yet. The wizard stamps `now()` on either
/// Finish or Skip-onboarding, so a returning user never re-sees it.

export const PRIMARY_GOAL_KEY = 'primary_goal';

/// Fixed enum the wizard's Goal step writes into
/// `user_settings.prefs.primary_goal`. A future post-onboarding
/// nudge will use this to suggest a training plan ("would you like
/// to create a 10k plan?") without re-asking — same shape the
/// /plans/new wizard already uses for `GoalEvent`.
///
/// `general_fitness` and `weight_loss` are the two non-distance
/// targets. The four distance targets map 1:1 to the
/// `training.ts#GoalEvent` enum so a future plan-creation flow can
/// translate without an extra mapping table.
export const PRIMARY_GOAL_VALUES = [
	'general_fitness',
	'weight_loss',
	'5k',
	'10k',
	'half_marathon',
	'marathon',
] as const;

export type PrimaryGoal = (typeof PRIMARY_GOAL_VALUES)[number];

export const PRIMARY_GOAL_LABELS: Record<PrimaryGoal, string> = {
	general_fitness: 'Stay fit + healthy',
	weight_loss: 'Lose weight',
	'5k': 'Run a 5K',
	'10k': 'Run a 10K',
	half_marathon: 'Run a half marathon',
	marathon: 'Run a marathon',
};

/// Total wizard steps. Drives the progress-dot indicator + the
/// per-step navigation math. Increment when adding a step (and add
/// the step's <section> + bound state in /onboarding/+page.svelte).
export const ONBOARDING_TOTAL_STEPS = 7;

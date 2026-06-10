import 'package:flutter/material.dart';

import '../food_search.dart' show FoodMacros;
import '../l10n/gen/app_localizations.dart';
import '../nutrition_budget.dart';
import '../nutrition_targets.dart' show NutritionTargets;
import '../nutrition_totals.dart' show MacroTotals, ringFraction;

/// Home "today's nutrition" card (multi_modal.md § Home): the four macro
/// rings (kcal / protein / carbs / fat) against the user's targets. When
/// targets are absent (no body metrics) the rings render unfilled and show
/// the raw consumed numbers — no zeroed/garbage target. Self-hiding is the
/// caller's job (the dashboard only builds this when food was logged today).
/// Tap opens the Nutrition surface.
class NutritionRingsCard extends StatelessWidget {
  final MacroTotals consumed;
  final NutritionTargets? targets;
  final VoidCallback onTap;
  const NutritionRingsCard({
    super.key,
    required this.consumed,
    required this.targets,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final budget = computeDayBudget(
      FoodMacros(
        calories: consumed.calories,
        proteinG: consumed.proteinG,
        carbsG: consumed.carbsG,
        fatG: consumed.fatG,
      ),
      targets,
    );
    final rings = <_Ring>[
      _Ring(l10n.nutritionCalories, consumed.calories, targets?.calories,
          budget?.calories),
      _Ring(l10n.nutritionProtein, consumed.proteinG, targets?.proteinG,
          budget?.protein),
      _Ring(l10n.nutritionCarbs, consumed.carbsG, targets?.carbsG, budget?.carbs),
      _Ring(l10n.nutritionFat, consumed.fatG, targets?.fatG, budget?.fat),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.restaurant,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.nutritionTitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          letterSpacing: 0.6,
                        )),
                  ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [for (final r in rings) _ringWidget(theme, r)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ringWidget(ThemeData theme, _Ring r) {
    final frac = ringFraction(r.consumed, r.target);
    // Ceiling rings (calories/fat) over target recolour to danger so a Home
    // glance shows the overshoot the clamped arc would otherwise hide.
    final over = r.budget?.exceeded ?? false;
    final ringColor = over ? theme.colorScheme.error : theme.colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: frac ?? 0,
                  strokeWidth: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: ringColor,
                ),
              ),
              if (over)
                Text('+${r.budget!.over}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.error))
              else
                Text('${r.consumed}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          r.label,
          style:
              theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}

class _Ring {
  final String label;
  final int consumed;
  final int? target;
  final MacroBudget? budget;
  const _Ring(this.label, this.consumed, this.target, this.budget);
}

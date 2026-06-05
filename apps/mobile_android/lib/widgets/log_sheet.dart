import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The four capture types the centre Log button can start (multi_modal.md
/// § Bottom nav). Persisted as a wire string in `Preferences.lastLogType`.
enum LogAction { run, lift, meal, snack }

/// Wire name for [Preferences.lastLogType] persistence + the `food_log`
/// meal slot for the snack path.
extension LogActionWire on LogAction {
  String get wire => switch (this) {
        LogAction.run => 'run',
        LogAction.lift => 'lift',
        LogAction.meal => 'meal',
        LogAction.snack => 'snack',
      };
}

/// Parse a persisted [Preferences.lastLogType] back to a [LogAction], or
/// null when absent / unrecognised (caller falls back to run).
LogAction? logActionFromWire(String? wire) => switch (wire) {
      'run' => LogAction.run,
      'lift' => LogAction.lift,
      'meal' => LogAction.meal,
      'snack' => LogAction.snack,
      _ => null,
    };

/// Display order with [recent] floated to the top (multi_modal.md: "the most
/// recently used capture type floats to the top, so a daily lifter sees
/// 'Start lift' first"). Stable for the remaining items. Pure so it can be
/// unit-tested without pumping the sheet.
List<LogAction> orderedLogActions(LogAction? recent) {
  const base = [LogAction.run, LogAction.lift, LogAction.meal, LogAction.snack];
  if (recent == null) return base;
  return [recent, ...base.where((a) => a != recent)];
}

/// The Log bottom sheet — Start run / Start lift / Log meal / Log snack.
/// Resolves to the picked [LogAction], or null on dismiss. The caller
/// (HomeScreen) performs the navigation so the sheet stays free of store /
/// api dependencies.
Future<LogAction?> showLogSheet({
  required BuildContext context,
  LogAction? recent,
}) {
  return showModalBottomSheet<LogAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _LogSheet(recent: recent),
  );
}

class _LogSheet extends StatelessWidget {
  final LogAction? recent;
  const _LogSheet({required this.recent});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final actions = orderedLogActions(recent);
    return SafeArea(
      top: false,
      // A single focus group so a screen reader presents the four capture
      // options as one cohesive menu (multi_modal.md § Accessibility).
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: l10n.logSheetTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(l10n.logSheetTitle, style: theme.textTheme.titleMedium),
            ),
            for (final a in actions) _tile(context, l10n, a),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, AppLocalizations l10n, LogAction a) {
    final (icon, label) = switch (a) {
      LogAction.run => (Icons.directions_run, l10n.logStartRun),
      LogAction.lift => (Icons.fitness_center, l10n.logStartLift),
      LogAction.meal => (Icons.restaurant, l10n.logMeal),
      LogAction.snack => (Icons.bakery_dining, l10n.logSnack),
    };
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.of(context).pop(a),
    );
  }
}

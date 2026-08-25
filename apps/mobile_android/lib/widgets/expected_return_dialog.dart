import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// What the runner chose in [showExpectedReturnDialog]: a new deadline, or
/// clearing the armed one. Null out of the dialog means "changed my mind" —
/// distinct from [ExpectedReturnChoice.clear], which is a deliberate disarm.
class ExpectedReturnChoice {
  final DateTime? at;
  const ExpectedReturnChoice._(this.at);

  factory ExpectedReturnChoice.at(DateTime when) =>
      ExpectedReturnChoice._(when);
  static const ExpectedReturnChoice clear = ExpectedReturnChoice._(null);

  bool get isClear => at == null;
}

/// Offsets from now the runner can arm. A ladder rather than a clock picker:
/// mid-run, on a phone, at arm's length, "I should be done in two hours" is
/// the thought a runner actually has — converting it to a wall-clock time is
/// arithmetic the app can do and a tired runner shouldn't have to.
const List<Duration> kExpectedReturnOffsets = <Duration>[
  Duration(minutes: 30),
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
  Duration(hours: 8),
];

/// The per-run "not back by X" picker (docs/features/safety.md, decisions
/// §240). [armed] is the deadline currently on the server — the caller reads
/// it before opening, so this dialog never has to guess.
Future<ExpectedReturnChoice?> showExpectedReturnDialog(
  BuildContext context, {
  DateTime? armed,
  DateTime Function()? now,
}) {
  final l10n = AppLocalizations.of(context);
  final materialL10n = MaterialLocalizations.of(context);
  final from = (now ?? DateTime.now)();

  String label(DateTime when) {
    final time = materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(when));
    // A deadline past midnight read as a bare clock time is the one a runner
    // could take for this afternoon.
    if (when.year == from.year &&
        when.month == from.month &&
        when.day == from.day) {
      return time;
    }
    return '${materialL10n.formatMediumDate(when)} $time';
  }

  return showDialog<ExpectedReturnChoice>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Text(l10n.runExpectedReturnTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.runExpectedReturnIntro,
                  style: theme.textTheme.bodyMedium),
              if (armed != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.runExpectedReturnActive(label(armed)),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
              const SizedBox(height: 8),
              for (final offset in kExpectedReturnOffsets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    offset.inMinutes < 60
                        ? l10n.runExpectedReturnOptionMinutes(offset.inMinutes)
                        : l10n.runExpectedReturnOptionHours(offset.inHours),
                  ),
                  subtitle:
                      Text(l10n.runExpectedReturnBy(label(from.add(offset)))),
                  onTap: () => Navigator.of(ctx).pop(
                      ExpectedReturnChoice.at(from.add(offset))),
                ),
              const SizedBox(height: 4),
              Text(
                l10n.runExpectedReturnServerNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          if (armed != null)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(ExpectedReturnChoice.clear),
              child: Text(
                l10n.runExpectedReturnClear,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}

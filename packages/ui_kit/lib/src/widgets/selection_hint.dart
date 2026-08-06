import 'package:flutter/material.dart';

/// One-line caption telling the reader that a long press opens multi-select.
///
/// A long press is the only route into multi-select on the runs and routes
/// lists, and a gesture that is the only route to a capability is invisible:
/// there is no hover, no menu entry, and nothing on screen changes until the
/// press lands. This is the hint, not a second affordance.
///
/// [label] is required for the reason [ActivityLoader]'s is — ui_kit has no
/// localization catalogue, so a default could only be English.
class SelectionHint extends StatelessWidget {
  const SelectionHint({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.touch_app_outlined,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

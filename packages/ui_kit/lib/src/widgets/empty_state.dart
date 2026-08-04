import 'package:flutter/material.dart';

/// Shared whole-surface empty state — the "no data yet" sibling of the
/// app-side ErrorState, with the same proportions (icon 48, 32 padding,
/// titleMedium title, bodySmall body) so empty and errored surfaces read
/// as one family instead of drifting per screen.
///
/// Under bounded height it fills the surface, centres vertically, and
/// stays scrollable when cramped (keyboard up, pull-to-refresh hosts).
/// Under unbounded height (embedded in an outer scrollable) it renders
/// just the content, leaving scrolling to the host.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final IconData ctaIcon;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.ctaLabel,
    this.onCta,
    this.ctaIcon = Icons.add,
  }) : assert((ctaLabel == null) == (onCta == null),
            'ctaLabel and onCta must be provided together');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (ctaLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCta,
                icon: Icon(ctaIcon),
                label: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return content;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }
}

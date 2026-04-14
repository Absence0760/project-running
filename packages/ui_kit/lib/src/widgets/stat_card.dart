import 'package:flutter/material.dart';

/// Metric display card for distance, pace, HR, etc.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 20, color: theme.colorScheme.primary),
            if (icon != null) const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Run history row displaying date, distance, duration, and pace.
class RunListTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  const RunListTile({
    super.key,
    required this.title,
    this.subtitle = '',
    this.trailing = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.directions_run, color: theme.colorScheme.primary),
      ),
      title: Text(title),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: trailing.isNotEmpty
          ? Text(trailing, style: theme.textTheme.bodySmall)
          : null,
      onTap: onTap,
    );
  }
}

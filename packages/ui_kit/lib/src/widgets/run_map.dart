import 'package:flutter/material.dart';

/// Map placeholder widget — displays coordinates until Google Maps is configured.
class RunMap extends StatelessWidget {
  final double? latitude;
  final double? longitude;

  const RunMap({super.key, this.latitude, this.longitude});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text('Map', style: theme.textTheme.titleMedium),
            if (latitude != null && longitude != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

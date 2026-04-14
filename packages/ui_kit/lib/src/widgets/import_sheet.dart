import 'package:flutter/material.dart';

/// Bottom sheet for GPX/KML file selection and import.
class ImportSheet extends StatelessWidget {
  final VoidCallback? onImport;

  const ImportSheet({super.key, this.onImport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.upload_file, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Import a route', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('GPX, KML, or GeoJSON', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose file'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../mock_data.dart';

/// Route library with import and route list.
class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Routes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Import GPX/KML coming soon')),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: mockRoutes
            .map((route) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: Icon(Icons.route,
                          color: theme.colorScheme.secondary),
                    ),
                    title: Text(route.name),
                    subtitle: Text(
                        '${route.formattedDistance}  •  ${route.formattedElevation}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('${route.name} detail coming soon')),
                      );
                    },
                  ),
                ))
            .toList(),
      ),
    );
  }
}

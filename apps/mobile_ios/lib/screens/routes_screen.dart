import 'package:flutter/material.dart';

/// Route library with import and route list.
class RoutesScreen extends StatelessWidget {
  const RoutesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Routes')),
      body: const Center(
        child: Text('No routes yet'),
      ),
      // TODO: Add import button, route list
    );
  }
}

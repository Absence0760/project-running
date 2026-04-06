import 'package:flutter/material.dart';

/// Main run recording screen with start button and live stats.
class RunScreen extends StatelessWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Run')),
      body: const Center(
        child: Text('Tap Start to begin recording'),
      ),
      // TODO: Add start/stop FAB, map, live stats
    );
  }
}

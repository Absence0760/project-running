import 'package:flutter/material.dart';

/// Run history list with weekly summary.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: const Center(
        child: Text('No runs yet'),
      ),
      // TODO: Add weekly summary card, run list
    );
  }
}

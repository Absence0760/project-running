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
    // TODO: Implement stat card design
    return const Placeholder();
  }
}

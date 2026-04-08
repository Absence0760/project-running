import 'dart:async';
import 'package:flutter/material.dart';

/// Main run recording screen with start button and live stats.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key});

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  bool _isRunning = false;
  int _elapsedSeconds = 0;
  double _distanceMetres = 0;
  Timer? _timer;

  void _start() {
    setState(() {
      _isRunning = true;
      _elapsedSeconds = 0;
      _distanceMetres = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsedSeconds++;
        // Simulate ~5:00/km pace (~3.3 m/s)
        _distanceMetres += 3.3;
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    final dist = (_distanceMetres / 1000).toStringAsFixed(2);
    final pace = _formattedPace;
    setState(() => _isRunning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Run saved: $dist km at $pace')),
    );
  }

  String get _formattedTime {
    final m = _elapsedSeconds ~/ 60;
    final s = _elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get _formattedDistance =>
      '${(_distanceMetres / 1000).toStringAsFixed(2)} km';

  String get _formattedPace {
    if (_distanceMetres < 10) return '--:-- /km';
    final paceSeconds = _elapsedSeconds / (_distanceMetres / 1000);
    final m = paceSeconds ~/ 60;
    final s = (paceSeconds % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')} /km';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Run')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Timer
            Text(
              _formattedTime,
              style: theme.textTheme.displayLarge?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 32),

            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatColumn(label: 'Distance', value: _formattedDistance),
                _StatColumn(label: 'Pace', value: _formattedPace),
              ],
            ),
            const SizedBox(height: 48),

            // Start/Stop button
            SizedBox(
              width: 120,
              height: 120,
              child: FilledButton(
                onPressed: _isRunning ? _stop : _start,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor:
                      _isRunning ? theme.colorScheme.error : Colors.green,
                ),
                child: Text(
                  _isRunning ? 'Stop' : 'Start',
                  style: const TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

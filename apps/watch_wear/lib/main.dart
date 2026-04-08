import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WearRunApp());
}

class WearRunApp extends StatelessWidget {
  const WearRunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const RunWatchScreen(),
    );
  }
}

enum RunState { preRun, running, postRun }

/// Main watch screen showing start button and live metrics.
class RunWatchScreen extends StatefulWidget {
  const RunWatchScreen({super.key});

  @override
  State<RunWatchScreen> createState() => _RunWatchScreenState();
}

class _RunWatchScreenState extends State<RunWatchScreen> {
  RunState _state = RunState.preRun;
  Timer? _timer;
  int _elapsedSeconds = 0;
  double _distanceMetres = 0.0;
  final Random _random = Random();

  String get _formattedTime {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get _formattedDistance {
    return '${(_distanceMetres / 1000).toStringAsFixed(2)} km';
  }

  String get _formattedPace {
    if (_distanceMetres < 10) return '--:-- /km';
    final secondsPerKm = _elapsedSeconds / (_distanceMetres / 1000);
    final paceMinutes = secondsPerKm ~/ 60;
    final paceSeconds = (secondsPerKm % 60).toInt();
    return '$paceMinutes:${paceSeconds.toString().padLeft(2, '0')} /km';
  }

  void _startRun() {
    setState(() {
      _state = RunState.running;
      _elapsedSeconds = 0;
      _distanceMetres = 0.0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsedSeconds++;
        // Simulate running: add 2-5 metres per second (~7-18 km/h)
        _distanceMetres += 2.0 + _random.nextDouble() * 3.0;
      });
    });
  }

  void _stopRun() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _state = RunState.postRun;
    });
  }

  void _reset() {
    setState(() {
      _state = RunState.preRun;
      _elapsedSeconds = 0;
      _distanceMetres = 0.0;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: switch (_state) {
            RunState.preRun => _buildPreRun(),
            RunState.running => _buildRunning(),
            RunState.postRun => _buildPostRun(),
          },
        ),
      ),
    );
  }

  Widget _buildPreRun() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Ready to Run',
          style: TextStyle(
            fontSize: 18,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 96,
          height: 96,
          child: ElevatedButton(
            onPressed: _startRun,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              'Start',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _formattedTime,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _formattedDistance,
          style: const TextStyle(
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formattedPace,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 72,
          height: 72,
          child: ElevatedButton(
            onPressed: _stopRun,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: const Text(
              'Stop',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPostRun() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Run Complete!',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _formattedTime,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formattedDistance,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          _formattedPace,
          style: const TextStyle(fontSize: 14, color: Colors.white60),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _reset,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[800],
            foregroundColor: Colors.white,
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

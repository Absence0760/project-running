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
      theme: ThemeData.dark(useMaterial3: true),
      home: const RunWatchScreen(),
    );
  }
}

/// Main watch screen showing start button and live metrics.
class RunWatchScreen extends StatelessWidget {
  const RunWatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ready to run', style: TextStyle(fontSize: 18)),
            SizedBox(height: 16),
            // TODO: Start button, live pace/distance/HR
          ],
        ),
      ),
    );
  }
}

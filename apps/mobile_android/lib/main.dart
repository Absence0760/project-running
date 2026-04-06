import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

// Android app shares screens with iOS via the shared packages.
// The main.dart is a separate entry point for Android-specific configuration.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO: Initialize Supabase
  // TODO: Initialize local database
  runApp(const RunApp());
}

class RunApp extends StatelessWidget {
  const RunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(
        body: Center(child: Text('Run App - Android')),
      ),
      // TODO: Share HomeScreen with iOS via ui_kit or a shared app package
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:api_client/api_client.dart';
import 'package:ui_kit/ui_kit.dart';

import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');

  await ApiClient.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Auto sign-in as test user
  final api = ApiClient();
  try {
    await api.signIn(email: 'runner@test.com', password: 'testtest');
  } catch (e) {
    debugPrint('Auto sign-in failed: $e');
  }

  runApp(RunApp(apiClient: api));
}

class RunApp extends StatelessWidget {
  final ApiClient apiClient;
  const RunApp({super.key, required this.apiClient});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: HomeScreen(apiClient: apiClient),
    );
  }
}

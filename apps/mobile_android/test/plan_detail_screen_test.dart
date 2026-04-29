import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/screens/plan_detail_screen.dart';
import '../lib/training_service.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: PlanDetailScreen(
        training: TrainingService(),
        planId: 'fake-plan-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('PlanDetailScreen — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold with just a centered spinner — no AppBar yet. This
      // is the only deterministic surface without a stub TrainingService.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('initial Scaffold has no AppBar yet', (tester) async {
      // Reason: the loading-state Scaffold is bare; the AppBar with
      // the plan name only paints after the fetch resolves.
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });
}

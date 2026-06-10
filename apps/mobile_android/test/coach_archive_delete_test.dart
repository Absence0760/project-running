import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/training_service.dart';

/// Seeds one archive and lets the test choose whether the delete throws,
/// so the swipe-to-delete path can be exercised end to end without a
/// network. Everything else returns the empty / consented defaults so the
/// screen renders its main Scaffold (with the archives drawer).
class _ArchiveApi extends ApiClient {
  _ArchiveApi({required this.throwOnDelete});
  final bool throwOnDelete;
  int deleteCalls = 0;

  @override
  Future<DateTime?> fetchCoachConsentAt() async => DateTime(2026, 1, 1);

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async => [];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async =>
      [DateTime.utc(2026, 3, 1, 10)];

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;

  @override
  Future<void> deleteCoachArchive({
    required DateTime archivedAt,
    String? planId,
  }) async {
    deleteCalls++;
    if (throwOnDelete) throw Exception('boom');
  }
}

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

Future<void> _pumpAndOpenDrawer(WidgetTester tester, _ArchiveApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(api: api, training: TrainingService()),
    ),
  );
  // Let consent + _reloadAll resolve and the streaming timer fire.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.byTooltip('Chat history'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_ensureSupabase);

  group('CoachScreen — swipe to delete archive', () {
    testWidgets('a failed delete snaps the row back and shows a banner',
        (tester) async {
      final api = _ArchiveApi(throwOnDelete: true);
      await _pumpAndOpenDrawer(tester, api);

      final archiveRow = find.byKey(const ValueKey('2026-03-01T10:00:00.000Z'));
      expect(archiveRow, findsOneWidget);
      await tester.drag(archiveRow, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, 1);
      // confirmDismiss returned false → the row stayed.
      expect(find.byKey(const ValueKey('2026-03-01T10:00:00.000Z')),
          findsOneWidget);
      expect(find.text("Couldn't delete archive: Exception: boom"),
          findsOneWidget);

      // Let the banner's auto-dismiss timer fire so it isn't left
      // pending when the widget tree is disposed.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a successful delete removes the row', (tester) async {
      final api = _ArchiveApi(throwOnDelete: false);
      await _pumpAndOpenDrawer(tester, api);

      final archiveRow = find.byKey(const ValueKey('2026-03-01T10:00:00.000Z'));
      expect(archiveRow, findsOneWidget);
      await tester.drag(archiveRow, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, 1);
      expect(find.byKey(const ValueKey('2026-03-01T10:00:00.000Z')),
          findsNothing);
    });
  });
}

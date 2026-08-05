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
/// so the delete path can be exercised end to end without a network.
/// Everything else returns the empty / consented defaults so the screen
/// renders its main Scaffold (with the archives drawer).
class _ArchiveApi extends ApiClient {
  _ArchiveApi({required this.throwOnDelete});
  final bool throwOnDelete;
  int deleteCalls = 0;

  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get userId => 'u-viewer';

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

final _archiveRow = find.byKey(const ValueKey('2026-03-01T10:00:00.000Z'));

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

Future<void> _openRowMenuAndChooseDelete(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Conversation actions'));
  await tester.pumpAndSettle();
  // The menu item and the confirm dialog's confirm button carry the same
  // label, so scope the finder to the menu item before the dialog exists.
  await tester
      .tap(find.widgetWithText(PopupMenuItem<String>, 'Delete conversation'));
  await tester.pumpAndSettle();
}

Future<void> _tapInDialog(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_ensureSupabase);

  group('CoachScreen — delete archive from the row menu', () {
    testWidgets('the destructive action is in the overflow menu, not a swipe',
        (tester) async {
      final api = _ArchiveApi(throwOnDelete: false);
      await _pumpAndOpenDrawer(tester, api);

      expect(_archiveRow, findsOneWidget);
      expect(find.byType(Dismissible), findsNothing);

      // A drag across the row must not destroy anything. The gesture this
      // row used to advertise deleted the conversation without asking.
      // The row itself goes with the drawer the drag closes, so the delete
      // count is what carries the claim.
      await tester.drag(_archiveRow, const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, 0);
    });

    testWidgets('choosing Delete asks for confirmation before deleting',
        (tester) async {
      final api = _ArchiveApi(throwOnDelete: false);
      await _pumpAndOpenDrawer(tester, api);
      await _openRowMenuAndChooseDelete(tester);

      expect(find.text('Delete this conversation?'), findsOneWidget);
      expect(api.deleteCalls, 0);
    });

    testWidgets('cancelling the confirm leaves the archive alone',
        (tester) async {
      final api = _ArchiveApi(throwOnDelete: false);
      await _pumpAndOpenDrawer(tester, api);
      await _openRowMenuAndChooseDelete(tester);
      await _tapInDialog(tester, 'Cancel');

      expect(api.deleteCalls, 0);
      expect(_archiveRow, findsOneWidget);
    });

    testWidgets('a confirmed delete removes the row', (tester) async {
      final api = _ArchiveApi(throwOnDelete: false);
      await _pumpAndOpenDrawer(tester, api);
      await _openRowMenuAndChooseDelete(tester);
      await _tapInDialog(tester, 'Delete conversation');

      expect(api.deleteCalls, 1);
      expect(_archiveRow, findsNothing);
    });

    testWidgets('a failed delete keeps the row and shows a banner',
        (tester) async {
      final api = _ArchiveApi(throwOnDelete: true);
      await _pumpAndOpenDrawer(tester, api);
      await _openRowMenuAndChooseDelete(tester);
      await _tapInDialog(tester, 'Delete conversation');

      expect(api.deleteCalls, 1);
      expect(_archiveRow, findsOneWidget);
      // The banner carries classified copy, not the raw exception —
      // the SDK text lives in debugPrint only (issue #240).
      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(find.textContaining('Exception: boom'), findsNothing);

      // Let the banner's auto-dismiss timer fire so it isn't left
      // pending when the widget tree is disposed.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

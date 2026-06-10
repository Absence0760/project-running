import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_social_section.dart';

/// Renders the viewer's own comment (so the delete affordance shows)
/// and records delete calls, with [throwOnDelete] to drive the error
/// path. The comment vanishes from the re-fetch once deleted.
class _CommentApi extends ApiClient {
  _CommentApi({this.throwOnDelete = false});
  final bool throwOnDelete;
  int deleteCalls = 0;
  bool _deleted = false;

  @override
  String? get userId => 'viewer-1';

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async => {};

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async =>
      const ProfileSummary(
        id: 'viewer-1',
        displayName: 'Me',
        followerCount: 0,
        followingCount: 0,
        viewerFollows: false,
      );

  @override
  Future<List<RunCommentWithAuthor>> fetchRunCommentsWithAuthors(
      String runId,
      {int limit = 200}) async {
    if (_deleted) return const [];
    return [
      RunCommentWithAuthor(
        comment: RunCommentRow(
          id: 'c1',
          runId: runId,
          authorId: 'viewer-1',
          body: 'e2e-comment-body',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
        author: const PublicProfile(id: 'viewer-1', displayName: 'Me'),
      ),
    ];
  }

  @override
  Future<void> deleteRunComment(String commentId) async {
    deleteCalls++;
    if (throwOnDelete) throw Exception('boom');
    _deleted = true;
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

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunSocialSection(
          api: ApiClient(),
          runId: 'fake-run-id',
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('RunSocialSection — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the widget renders only a
      // CircularProgressIndicator inside a centered Padding.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('RunSocialSection — delete comment confirm', () {
    Future<void> pumpLoaded(WidgetTester tester, _CommentApi api) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RunSocialSection(api: api, runId: 'fake-run-id'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder confirmDelete() => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Delete'),
        );

    testWidgets('Cancel keeps the comment and never calls delete',
        (tester) async {
      final api = _CommentApi();
      await pumpLoaded(tester, api);
      expect(find.text('e2e-comment-body'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this comment?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(api.deleteCalls, 0);
      expect(find.text('e2e-comment-body'), findsOneWidget);
    });

    testWidgets('Confirm deletes the comment', (tester) async {
      final api = _CommentApi();
      await pumpLoaded(tester, api);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(confirmDelete());
      await tester.pumpAndSettle();

      expect(api.deleteCalls, 1);
      expect(find.text('e2e-comment-body'), findsNothing);
    });

    testWidgets('a failed delete surfaces a banner and keeps the comment',
        (tester) async {
      final api = _CommentApi(throwOnDelete: true);
      await pumpLoaded(tester, api);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(confirmDelete());
      await tester.pumpAndSettle();

      expect(api.deleteCalls, 1);
      expect(find.text('e2e-comment-body'), findsOneWidget);
      expect(find.textContaining('Failed to delete'), findsOneWidget);

      // Drain the banner's auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

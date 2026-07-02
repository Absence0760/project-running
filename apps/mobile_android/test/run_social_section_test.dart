import 'dart:async';

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

/// Full-fidelity fake driving kudos + comment flows. Records the
/// outbound calls + lets each test plant the engagement seed, comment
/// list, and error injections for the optimistic-update / rollback /
/// double-submit assertions.
class _SocialApi extends ApiClient {
  _SocialApi({
    this.viewer = 'viewer-1',
    this.kudosCount = 0,
    this.viewerHasKudos = false,
    this.commentCount = 0,
    this.seedComments = const [],
    this.throwOnGive = false,
    this.throwOnRescind = false,
    this.throwOnAdd = false,
    this.giveReturnsNoOp = false,
    this.rescindReturnsNoOp = false,
  });

  final String? viewer;
  final int kudosCount;
  final bool viewerHasKudos;
  final int commentCount;
  final List<RunCommentWithAuthor> seedComments;
  final bool throwOnGive;
  final bool throwOnRescind;
  final bool throwOnAdd;
  // Simulate the DB-level no-op the optimistic UI must reconcile: a
  // duplicate insert (23505 → false) / a delete that matched nothing.
  final bool giveReturnsNoOp;
  final bool rescindReturnsNoOp;

  int giveCalls = 0;
  int rescindCalls = 0;
  int addCalls = 0;
  final List<String> addedBodies = [];
  // Gates the addRunComment future so a test can fire a second submit
  // while the first is in flight (double-submit guard).
  Completer<void>? addGate;

  @override
  String? get userId => viewer;

  @override
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async => {
            for (final id in runIds)
              id: (
                kudosCount: kudosCount,
                viewerHasKudos: viewerHasKudos,
                commentCount: commentCount,
              ),
          };

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async =>
      ProfileSummary(
        id: viewer ?? 'anon',
        displayName: 'Me',
        followerCount: 0,
        followingCount: 0,
        viewerFollows: false,
      );

  @override
  Future<List<RunCommentWithAuthor>> fetchRunCommentsWithAuthors(
      String runId,
      {int limit = 200}) async => seedComments;

  @override
  Future<bool> giveKudos(String runId) async {
    giveCalls++;
    if (throwOnGive) throw Exception('give-boom');
    return !giveReturnsNoOp;
  }

  @override
  Future<bool> rescindKudos(String runId) async {
    rescindCalls++;
    if (throwOnRescind) throw Exception('rescind-boom');
    return !rescindReturnsNoOp;
  }

  @override
  Future<RunCommentRow> addRunComment({
    required String runId,
    required String body,
    String? parentCommentId,
  }) async {
    addCalls++;
    addedBodies.add(body);
    if (addGate != null) await addGate!.future;
    if (throwOnAdd) throw Exception('add-boom');
    return RunCommentRow(
      id: 'new-${addCalls}',
      runId: runId,
      authorId: viewer ?? 'anon',
      body: body,
      parentCommentId: parentCommentId,
      createdAt: DateTime(2026, 2, 1),
      updatedAt: DateTime(2026, 2, 1),
    );
  }
}

Future<void> _pumpApi(WidgetTester tester, ApiClient api,
    {String? runOwnerId}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: RunSocialSection(
          api: api,
          runId: 'fake-run-id',
          runOwnerId: runOwnerId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RunCommentWithAuthor _comment(
  String id, {
  String authorId = 'someone-else',
  String body = 'nice run',
  String? parentId,
}) =>
    RunCommentWithAuthor(
      comment: RunCommentRow(
        id: id,
        runId: 'fake-run-id',
        authorId: authorId,
        body: body,
        parentCommentId: parentId,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
      author: PublicProfile(id: authorId, displayName: authorId),
    );

void main() {
  setUpAll(_ensureSupabase);

  group('RunSocialSection — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the widget renders only a
      // CircularProgressIndicator inside a centered Padding.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty thread renders the no-comments hint + composer',
        (tester) async {
      final api = _SocialApi();
      await _pumpApi(tester, api);
      expect(find.text('No comments yet.'), findsOneWidget);
      // Composer is visible for a signed-in viewer.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders seeded kudos count + comment bodies', (tester) async {
      final api = _SocialApi(
        kudosCount: 7,
        commentCount: 1,
        seedComments: [_comment('c1', body: 'great pace')],
      );
      await _pumpApi(tester, api);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('great pace'), findsOneWidget);
      expect(find.text('No comments yet.'), findsNothing);
    });

    testWidgets('signed-out viewer (userId == null) hides the composer',
        (tester) async {
      final api = _SocialApi(viewer: null);
      await _pumpApi(tester, api);
      // No composer TextField for anon.
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('RunSocialSection — kudos', () {
    testWidgets('tapping the pill optimistically increments + calls giveKudos',
        (tester) async {
      final api = _SocialApi(kudosCount: 2, viewerHasKudos: false);
      await _pumpApi(tester, api);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byType(TextButton).first);
      await tester.pump();
      // Optimistic bump before the await resolves.
      expect(find.text('3'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(api.giveCalls, 1);
      expect(api.rescindCalls, 0);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('kudos pill carries an accessibility label for its state',
        (tester) async {
      final api = _SocialApi(kudosCount: 2, viewerHasKudos: false);
      await _pumpApi(tester, api);
      // Not-yet-kudoed → "give" label.
      expect(find.bySemanticsLabel('Give kudos'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove kudos'), findsNothing);
    });

    testWidgets('kudoed pill exposes the remove-kudos accessibility label',
        (tester) async {
      final api = _SocialApi(kudosCount: 5, viewerHasKudos: true);
      await _pumpApi(tester, api);
      expect(find.bySemanticsLabel('Remove kudos'), findsOneWidget);
      expect(find.bySemanticsLabel('Give kudos'), findsNothing);
    });

    testWidgets('un-kudos calls rescindKudos and decrements', (tester) async {
      final api = _SocialApi(kudosCount: 5, viewerHasKudos: true);
      await _pumpApi(tester, api);
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(api.rescindCalls, 1);
      expect(api.giveCalls, 0);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('a no-op give (already kudoed elsewhere) undoes the +1 drift',
        (tester) async {
      // The viewer kudoed this run from another tab, so the server
      // already has the row, but this widget's local flag is stale
      // (viewerHasKudos: false, count excludes their kudos). Tapping
      // fires an insert that 23505s as a no-op → giveKudos returns
      // false → the UI must NOT keep the optimistic +1.
      final api = _SocialApi(
        kudosCount: 2,
        viewerHasKudos: false,
        giveReturnsNoOp: true,
      );
      await _pumpApi(tester, api);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(api.giveCalls, 1);
      // Count reconciled back to 2 (no real change), flag stays kudoed —
      // the optimistic +1 did NOT stick on a duplicate-insert no-op.
      expect(find.text('3'), findsNothing);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a no-op rescind (already un-kudoed elsewhere) undoes the -1 drift',
        (tester) async {
      // Symmetric to the no-op give: the viewer un-kudoed this run from
      // another tab, so the server row is already gone, but this widget's
      // local flag is stale (viewerHasKudos: true). Tapping fires a delete
      // that matches nothing → rescindKudos returns false → the UI must NOT
      // keep the optimistic -1.
      final api = _SocialApi(
        kudosCount: 5,
        viewerHasKudos: true,
        rescindReturnsNoOp: true,
      );
      await _pumpApi(tester, api);
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(api.rescindCalls, 1);
      // Count reconciled back to 5 (no real change) — the optimistic -1 did
      // NOT stick on a delete that matched nothing.
      expect(find.text('4'), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('a failed give rolls back the optimistic bump + shows a banner',
        (tester) async {
      final api = _SocialApi(
        kudosCount: 2,
        viewerHasKudos: false,
        throwOnGive: true,
      );
      await _pumpApi(tester, api);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(api.giveCalls, 1);
      // Rolled back to the pre-tap count.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      expect(find.textContaining('kudos'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('a failed un-kudos rolls back the optimistic decrement + shows a banner',
        (tester) async {
      final api = _SocialApi(
        kudosCount: 5,
        viewerHasKudos: true,
        throwOnRescind: true,
      );
      await _pumpApi(tester, api);

      await tester.tap(find.byType(TextButton).first);
      await tester.pumpAndSettle();
      expect(api.rescindCalls, 1);
      // Rolled back to the pre-tap count.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('4'), findsNothing);
      expect(find.textContaining('kudos'), findsWidgets);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('owner viewing own run cannot kudos (pill disabled, no call)',
        (tester) async {
      final api = _SocialApi(viewer: 'owner-1', kudosCount: 1);
      await _pumpApi(tester, api, runOwnerId: 'owner-1');
      // The pill is disabled; tapping it does nothing.
      await tester.tap(find.byType(TextButton).first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(api.giveCalls, 0);
      expect(api.rescindCalls, 0);
    });
  });

  group('RunSocialSection — comment post', () {
    testWidgets('posting a comment appends it optimistically + bumps count',
        (tester) async {
      final api = _SocialApi(commentCount: 0);
      await _pumpApi(tester, api);
      await tester.enterText(find.byType(TextField), 'first comment');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect(api.addCalls, 1);
      expect(api.addedBodies.single, 'first comment');
      expect(find.text('first comment'), findsOneWidget);
      expect(find.text('No comments yet.'), findsNothing);
    });

    testWidgets('blank / whitespace comment does not call addRunComment',
        (tester) async {
      final api = _SocialApi();
      await _pumpApi(tester, api);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect(api.addCalls, 0);
    });

    testWidgets('double-submit guard — second tap while posting is a no-op',
        (tester) async {
      final api = _SocialApi()..addGate = Completer<void>();
      await _pumpApi(tester, api);
      await tester.enterText(find.byType(TextField), 'busy comment');
      // First tap starts the (gated) post — _posting is now true.
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pump();
      // While posting, the button shows a spinner + is disabled, so a
      // second tap can't fire a second addRunComment.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(api.addCalls, 1);
      // Release the gate; the single post completes.
      api.addGate!.complete();
      await tester.pumpAndSettle();
      expect(api.addCalls, 1);
      expect(find.text('busy comment'), findsOneWidget);
    });

    testWidgets('a failed post surfaces a banner and does not append',
        (tester) async {
      final api = _SocialApi(throwOnAdd: true);
      await _pumpApi(tester, api);
      await tester.enterText(find.byType(TextField), 'doomed');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect(api.addCalls, 1);
      // The optimistic append only happens after a successful insert, so
      // the thread is still empty. (The draft text stays in the composer
      // for retry, so we assert on the list state, not the raw string.)
      expect(find.text('No comments yet.'), findsOneWidget);
      expect(find.textContaining('Failed to post'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
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

  group('RunSocialSection — comment action tap targets (a11y >=48dp)', () {
    testWidgets('inline Reply + Delete meet the 48dp minimum hit target',
        (tester) async {
      final api = _CommentApi();
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

      final reply = find.widgetWithText(TextButton, 'Reply');
      final del = find.widgetWithText(TextButton, 'Delete');
      expect(reply, findsOneWidget);
      expect(del, findsOneWidget);
      expect(tester.getSize(reply).height, greaterThanOrEqualTo(48.0));
      expect(tester.getSize(del).height, greaterThanOrEqualTo(48.0));
    });
  });
}

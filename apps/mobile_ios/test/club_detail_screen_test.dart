import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/club_detail_screen.dart';
import '../lib/social_service.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ClubDetailScreen(
        social: SocialService(),
        training: TrainingService(),
        slug: 'fake-slug',
      ),
    ),
  );
}

ClubView _memberClub() => ClubView(
      row: ClubRow(shadowHidden: false, 
        id: 'club-1',
        ownerId: 'owner',
        name: 'Track Club',
        slug: 'track-club',
        isPublic: true,
        joinPolicy: 'open',
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 5,
      viewerRole: 'member',
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

class _FakeSocial extends SocialService {
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _memberClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [];
  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

class _FakeApi extends ApiClient {
  final List<GymRoutineRow> routines;
  _FakeApi(this.routines);

  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get userId => 'u-viewer';
  @override
  Future<List<GymRoutineRow>> fetchClubGymRoutineTemplates(String clubId) async =>
      routines;
  @override
  Future<List<SessionPlanRow>> fetchClubSessionTemplates(String clubId) async =>
      const [];
}

class _FakeTraining extends TrainingService {
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async => const [];
}

ClubView _adminClub() => ClubView(
      row: ClubRow(shadowHidden: false, 
        id: 'club-1',
        ownerId: 'owner',
        name: 'Track Club',
        slug: 'track-club',
        isPublic: true,
        joinPolicy: 'request',
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 5,
      viewerRole: 'admin',
      viewerStatus: 'active',
      joinPolicy: 'request',
    );

/// Admin club with one pending request and a gated approve so the in-flight
/// window stays open while the test taps a second time.
class _PendingSocial extends SocialService {
  int approveCalls = 0;
  final Completer<void> approveGate = Completer<void>();

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _adminClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [
        ClubMemberRow(
          clubId: 'club-1',
          userId: 'pendinguser-0001',
          role: 'member',
          status: 'pending',
        ),
      ];
  @override
  Future<void> approveJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    approveCalls++;
    await approveGate.future;
  }

  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

/// Admin club with one pending request that records deny calls so the
/// deny-confirm dialog flow can be asserted.
class _DenySocial extends SocialService {
  int denyCalls = 0;

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _adminClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [
        ClubMemberRow(
          clubId: 'club-1',
          userId: 'pendinguser-0001',
          role: 'member',
          status: 'pending',
        ),
      ];
  @override
  Future<void> denyJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    denyCalls++;
  }

  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

/// Member club with one top-level post and a gated createPost so the
/// in-flight window stays open while the test taps Send a second time.
class _ReplySocial extends SocialService {
  int createCalls = 0;
  final Completer<void> createGate = Completer<void>();

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _memberClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async => [
        ClubPostView(
          row: ClubPostRow(
            id: 'post-1',
            clubId: 'club-1',
            authorId: 'someone',
            body: 'Saturday long run?',
            createdAt: DateTime.utc(2026, 5, 1),
          ),
          authorName: 'Sam',
          replyCount: 0,
        ),
      ];
  @override
  Future<List<ClubPostView>> fetchPostReplies(String parentId, {int limit = 200}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [];
  @override
  Future<void> createPost({
    required String clubId,
    required String body,
    String? parentPostId,
    String? eventId,
    DateTime? eventInstanceStart,
  }) async {
    createCalls++;
    await createGate.future;
  }

  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

/// Member club with an empty feed and a gated createPost so the in-flight
/// window stays open while the test taps the compose Post button again.
class _ComposeSocial extends SocialService {
  int createCalls = 0;
  final Completer<void> createGate = Completer<void>();

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _memberClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [];
  @override
  Future<void> createPost({
    required String clubId,
    required String body,
    String? parentPostId,
    String? eventId,
    DateTime? eventInstanceStart,
  }) async {
    createCalls++;
    await createGate.future;
  }

  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

/// Training service that surfaces one plan template and gates the clone
/// so the in-flight window stays open across a second Adopt tap.
class _AdoptTraining extends TrainingService {
  int cloneCalls = 0;
  final Completer<void> cloneGate = Completer<void>();

  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async => [
        TrainingPlanRow(
          id: 'tmpl-1',
          userId: 'owner',
          name: 'Club 10k Plan',
          goalEvent: 'distance_10k',
          goalDistanceM: 10000,
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 7, 1),
          daysPerWeek: 4,
          status: 'active',
          source: 'generated',
          isTemplate: true,
          isPublicTemplate: false,
        ),
      ];

  @override
  Future<String> clonePlanTemplate({
    required String templateId,
    DateTime? startDate,
  }) async {
    cloneCalls++;
    await cloneGate.future;
    return 'new-plan';
  }
}

GymRoutineRow _routine(String id, String title, int count) => GymRoutineRow(
      id: id,
      authorId: 'author',
      clubId: 'club-1',
      title: title,
      periodisation: 'none',
      exerciseCount: count,
      isPublicTemplate: false,
      lastModifiedAt: DateTime.utc(2026, 5, 1),
      createdAt: DateTime.utc(2026, 5, 1),
    );

void main() {
  setUpAll(_ensureSupabase);

  group('ClubDetailScreen — initial render', () {
    testWidgets('first frame shows the loading spinner', (tester) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold with just a centered spinner.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('initial Scaffold has no AppBar yet', (tester) async {
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('ClubDetailScreen — Templates tab gym routines', () {
    testWidgets('renders a gym-routine template row with Adopt',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _FakeSocial(),
            training: _FakeTraining(),
            apiClient: _FakeApi([_routine('r-1', 'Club push day', 3)]),
            slug: 'track-club',
          ),
        ),
      );
      // Let _load resolve the club + parallel fetches.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // The club header should now be up.
      expect(find.text('Track Club'), findsWidgets);
      // Switch to the Templates tab (index 4) → _loadTemplates fires.
      await tester.tap(find.text('Templates'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Gym routine templates'), findsOneWidget);
      expect(find.text('Club push day'), findsOneWidget);
      expect(find.text('3 exercises'), findsOneWidget);
      expect(find.text('Adopt'), findsWidgets);
    });

    testWidgets('double-tapping a plan-template Adopt clones only once',
        (tester) async {
      final training = _AdoptTraining();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _FakeSocial(),
            training: training,
            apiClient: _FakeApi(const []),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Templates'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Club 10k Plan'), findsOneWidget);
      final adopt = find.widgetWithText(FilledButton, 'Adopt');
      expect(adopt, findsOneWidget);

      await tester.tap(adopt);
      await tester.pump();
      // Second tap while the gated clone is in flight — button disabled now.
      await tester.tap(adopt, warnIfMissed: false);
      await tester.pump();

      expect(training.cloneCalls, 1);
      // Gate left pending intentionally: completing it would navigate to
      // PlanDetailScreen (unstubbed). cloneCalls is the assertion.
    });
  });

  group('ClubDetailScreen — pending approve double-submit guard', () {
    testWidgets('rapid double-tap of Approve only fires the RPC once',
        (tester) async {
      final social = _PendingSocial();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: social,
            training: _FakeTraining(),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Switch to the Members tab (index 2) where the pending panel renders.
      await tester.tap(find.text('Members'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final approveBtn = find.widgetWithText(FilledButton, 'Approve');
      expect(approveBtn, findsOneWidget);

      await tester.tap(approveBtn);
      await tester.pump();
      // Second tap while the first is still in flight (gate not completed).
      await tester.tap(approveBtn);
      await tester.pump();

      expect(social.approveCalls, 1);

      // Let the gated approve finish so no timer/future leaks.
      social.approveGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('ClubDetailScreen — deny join request confirm', () {
    Future<_DenySocial> openMembers(WidgetTester tester) async {
      final social = _DenySocial();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: social,
            training: _FakeTraining(),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Members'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      return social;
    }

    testWidgets('tapping Deny opens a confirm dialog instead of denying',
        (tester) async {
      final social = await openMembers(tester);
      final denyBtn = find.widgetWithText(TextButton, 'Deny');
      expect(denyBtn, findsOneWidget);
      await tester.ensureVisible(denyBtn);
      await tester.pump();
      await tester.tap(denyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Reject join request'), findsOneWidget);
      expect(social.denyCalls, 0);
    });

    testWidgets('cancelling the dialog does not deny', (tester) async {
      final social = await openMembers(tester);
      final denyBtn = find.widgetWithText(TextButton, 'Deny');
      expect(denyBtn, findsOneWidget);
      await tester.ensureVisible(denyBtn);
      await tester.pump();
      await tester.tap(denyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsNothing);
      expect(social.denyCalls, 0);
    });

    testWidgets('confirming the dialog denies once', (tester) async {
      final social = await openMembers(tester);
      final denyBtn = find.widgetWithText(TextButton, 'Deny');
      expect(denyBtn, findsOneWidget);
      await tester.ensureVisible(denyBtn);
      await tester.pump();
      await tester.tap(denyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Deny'),
        ));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(social.denyCalls, 1);
    });
  });

  group('ClubDetailScreen — reply double-submit guard', () {
    testWidgets('rapid double-tap of reply Send only fires createPost once',
        (tester) async {
      final social = _ReplySocial();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: social,
            training: _FakeTraining(),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Feed is the default tab; expand the post's reply thread to reveal
      // the composer (replyCount == 0 → the toggle reads "Reply").
      await tester.tap(find.text('Reply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
          find.widgetWithText(TextField, 'Write a reply…'), 'On for 7am');
      await tester.pump();

      final sendBtn = find.widgetWithText(FilledButton, 'Send');
      expect(sendBtn, findsOneWidget);

      await tester.tap(sendBtn);
      await tester.pump();
      // Second tap while the first createPost is still gated in flight —
      // the button is now disabled, so the tap is expected to miss.
      await tester.tap(sendBtn, warnIfMissed: false);
      await tester.pump();

      expect(social.createCalls, 1);

      // Release the gate so no future leaks.
      social.createGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('ClubDetailScreen — compose double-submit guard', () {
    testWidgets('rapid double-tap of compose Post only fires createPost once',
        (tester) async {
      final social = _ComposeSocial();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: social,
            training: _FakeTraining(),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Feed is the default tab; the member composer renders inline.
      await tester.enterText(
          find.widgetWithText(TextField, 'Share an update…'), 'Long run Sat 7am');
      await tester.pump();

      final postBtn = find.widgetWithText(FilledButton, 'Post');
      expect(postBtn, findsOneWidget);

      await tester.tap(postBtn);
      await tester.pump();
      // Second tap while the first createPost is still gated in flight — the
      // button is now disabled, so the tap is expected to miss.
      await tester.tap(postBtn, warnIfMissed: false);
      await tester.pump();

      expect(social.createCalls, 1);

      // Release the gate so no future leaks.
      social.createGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('ClubDetailScreen — load failure / not-found', () {
    testWidgets('a null club renders the not-found state with Retry',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _NotFoundSocial(),
            training: _FakeTraining(),
            slug: 'ghost-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text("Couldn't load this club."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a thrown load renders the error message + Retry',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _ThrowingSocial(),
            training: _FakeTraining(),
            slug: 'broken-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text("Couldn't load this club."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('ClubDetailScreen — header + membership CTA', () {
    testWidgets('a member club renders the name + the five tabs',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _FakeSocial(),
            training: _FakeTraining(),
            apiClient: _FakeApi(const []),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Track Club'), findsWidgets);
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Routes'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
    });

    testWidgets('an admin sees the Edit-club action in the AppBar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _AdminSocial(),
            training: _FakeTraining(),
            apiClient: _FakeApi(const []),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('a plain member does NOT see the Edit-club action',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _FakeSocial(),
            training: _FakeTraining(),
            apiClient: _FakeApi(const []),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('an admin sees the Create-event button on the Events tab',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: _AdminSocial(),
            training: _FakeTraining(),
            apiClient: _FakeApi(const []),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Events'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Empty events + admin → the create-event CTA renders.
      expect(find.text('Create event'), findsWidgets);
    });
  });

  group('ClubDetailScreen — join non-member', () {
    testWidgets('a non-member sees Join and tapping it calls joinClub once',
        (tester) async {
      final social = _NonMemberSocial();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ClubDetailScreen(
            social: social,
            training: _FakeTraining(),
            apiClient: _FakeApi(const []),
            slug: 'track-club',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final join = find.widgetWithText(FilledButton, 'Join');
      expect(join, findsOneWidget);
      await tester.tap(join);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(social.joinCalls, 1);
    });
  });
}

ClubView _nonMemberClub() => ClubView(
      row: ClubRow(shadowHidden: false, 
        id: 'club-1',
        ownerId: 'owner',
        name: 'Track Club',
        slug: 'track-club',
        isPublic: true,
        joinPolicy: 'open',
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 5,
      viewerRole: null,
      viewerStatus: null,
      joinPolicy: 'open',
    );

class _NotFoundSocial extends SocialService {
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => null;
  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

class _ThrowingSocial extends SocialService {
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async =>
      throw Exception('club load down');
  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

class _AdminSocial extends SocialService {
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _adminClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [];
  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

class _NonMemberSocial extends SocialService {
  int joinCalls = 0;
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _nonMemberClub();
  @override
  Future<List<EventView>> fetchUpcomingEvents(String clubId) async => const [];
  @override
  Future<List<ClubPostView>> fetchClubPosts(String clubId, {int limit = 20}) async =>
      const [];
  @override
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async => const [];
  @override
  Future<String> joinClub(String clubId, String policy) async {
    joinCalls++;
    return 'active';
  }

  @override
  RealtimeChannel subscribeToClub(String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$clubId');
}

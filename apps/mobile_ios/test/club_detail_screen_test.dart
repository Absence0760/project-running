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
      row: ClubRow(
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
      row: ClubRow(
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

GymRoutineRow _routine(String id, String title, int count) => GymRoutineRow(
      id: id,
      authorId: 'author',
      clubId: 'club-1',
      title: title,
      periodisation: 'none',
      exerciseCount: count,
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
}

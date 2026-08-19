import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show FullBodyLoader, TextLane;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/challenge_detail_screen.dart';
import '../lib/social_service.dart';

/// Never resolves the challenge fetch, so the loading frame is observable.
class _HangingSocial extends SocialService {
  @override
  String? get currentUserId => 'me';

  @override
  Future<ChallengeView?> fetchChallengeById(String id) =>
      Completer<ChallengeView?>().future;

  @override
  Future<List<ChallengeLeaderboardEntry>> fetchChallengeLeaderboard(
    String id, {
    bool byTeam = false,
  }) async =>
      const [];

  @override
  Future<List<ClubView>> fetchMyClubs() async => const [];
}

class _FakeSocial extends SocialService {
  final ChallengeView? challenge;
  final bool throwOnFetch;
  final bool throwOnDelete;
  final List<ChallengeLeaderboardEntry> board;
  final List<ClubView> clubs;
  _FakeSocial(
    this.challenge, {
    this.throwOnFetch = false,
    this.throwOnDelete = false,
    this.board = const [],
    this.clubs = const [],
  });

  @override
  String? get currentUserId => 'me';

  @override
  Future<ChallengeView?> fetchChallengeById(String id) async {
    if (throwOnFetch) throw Exception('network down');
    return challenge;
  }

  @override
  Future<List<ChallengeLeaderboardEntry>> fetchChallengeLeaderboard(
    String id, {
    bool byTeam = false,
  }) async =>
      board;

  @override
  Future<List<ClubView>> fetchMyClubs() async => clubs;

  @override
  Future<void> deleteChallenge(String id) async {
    if (throwOnDelete) throw Exception('delete failed');
  }
}

ChallengeView _ch({
  required num? myValue,
  num? goalValue = 100000,
  String creatorId = 'creator',
  String scope = 'individual',
  String? myTeamClubId,
}) {
  final now = DateTime.now();
  return ChallengeView(
    id: 'c1',
    creatorId: creatorId,
    clubId: null,
    title: 'Pace challenge',
    description: null,
    metric: 'distance',
    scope: scope,
    goalValue: goalValue,
    activityType: null,
    // 60 % elapsed: 6 days in, 4 to go.
    startsAt: now.subtract(const Duration(days: 6)),
    endsAt: now.add(const Duration(days: 4)),
    isPublic: true,
    joined: true,
    myValue: myValue,
    myTeamClubId: myTeamClubId,
  );
}

ClubView _club(String id, String name) => ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: id,
        ownerId: 'owner',
        name: name,
        slug: name.toLowerCase(),
        isPublic: true,
        joinPolicy: 'open',
        memberCount: 3,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 3,
      viewerRole: 'member',
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

Widget _app(SocialService social) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChallengeDetailScreen(social: social, challengeId: 'c1'),
    );

void main() {
  testWidgets('the loading frame is the full-body loader, not a bare spinner',
      (tester) async {
    await tester.pumpWidget(_app(_HangingSocial()));
    await tester.pump();

    expect(find.byType(FullBodyLoader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('behind-pace joined challenge shows the verdict + required rate',
      (tester) async {
    // 20 km logged against an expected ~60 km at 60 % elapsed → behind.
    await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: 20000))));
    await tester.pump();

    expect(find.text('Behind pace'), findsOneWidget);
    expect(find.textContaining('per day to finish'), findsOneWidget);
  });

  testWidgets('ahead-pace joined challenge shows the ahead verdict only',
      (tester) async {
    // 80 km against ~60 km expected → ahead, no required-rate line.
    await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: 80000))));
    await tester.pump();

    expect(find.text('Ahead of pace'), findsOneWidget);
    expect(find.textContaining('per day to finish'), findsNothing);
  });

  testWidgets('goal-less board renders no pace hint', (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: 20000, goalValue: null))));
    await tester.pump();

    expect(find.text('Behind pace'), findsNothing);
    expect(find.text('Ahead of pace'), findsNothing);
    expect(find.text('On pace to finish'), findsNothing);
  });

  testWidgets('a fetch failure shows the ErrorState + retry, not "not found"',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(null, throwOnFetch: true)));
    await tester.pump(); // resolve the throwing fetch

    // Distinct from the genuine missing-row path.
    expect(find.text("This challenge isn't available."), findsNothing);
    expect(find.text("Couldn't load challenges."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a genuinely missing challenge shows the not-found copy',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(null)));
    await tester.pump();

    expect(find.text("This challenge isn't available."), findsOneWidget);
    expect(find.text("Couldn't load challenges."), findsNothing);
  });

  testWidgets('club-vs-club leaderboard shows club names, not raw UUIDs',
      (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(
      _ch(myValue: null, scope: 'club_vs_club'),
      board: const [
        ChallengeLeaderboardEntry(
          userId: null,
          displayName: null,
          teamClubId: 'club-42',
          value: 5000,
          rank: 1,
        ),
      ],
      clubs: [_club('club-42', 'Track Club')],
    )));
    await tester.pump(); // fetch challenge + board + clubs

    expect(find.text('Track Club'), findsOneWidget);
    expect(find.text('club-42'), findsNothing);
  });

  testWidgets('a failed delete shows the delete-specific message', (tester) async {
    await tester.pumpWidget(_app(_FakeSocial(
      _ch(myValue: 20000, creatorId: 'me'),
      throwOnDelete: true,
    )));
    await tester.pump(); // load

    // Owner sees the delete action.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle(); // open the confirm dialog

    // Confirm the deletion.
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Delete'),
    );
    expect(confirm, findsOneWidget);
    await tester.tap(confirm);
    await tester.pump(); // dialog pop + throwing delete

    expect(find.text("Couldn't delete the challenge."), findsOneWidget);
    // NOT the misleading load-failure copy.
    expect(find.text("Couldn't load challenges."), findsNothing);

    // Drain the showTopBanner auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
  });

  group('ChallengeDetailScreen — the viewer standing card', () {
    ChallengeLeaderboardEntry row(String id, num value, int rank) =>
        ChallengeLeaderboardEntry(
          userId: id,
          displayName: id == 'me' ? 'Me' : id,
          teamClubId: null,
          value: value,
          rank: rank,
        );

    testWidgets('states the rank, the board size and both neighbour gaps',
        (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(
        _ch(myValue: 20000),
        board: [row('Alex', 30000, 1), row('me', 20000, 2), row('Sam', 10000, 3)],
      )));
      await tester.pump();

      expect(find.byKey(const Key('challenge-standing')), findsOneWidget);
      expect(find.text('Your standing'), findsOneWidget);
      expect(find.text('#2 of 3'), findsOneWidget);
      expect(find.textContaining('behind Alex'), findsOneWidget);
      expect(find.textContaining('ahead of Sam'), findsOneWidget);
      expect(find.text('Leading'), findsNothing);
    });

    testWidgets('an outright leader is named as leading, with nobody chased',
        (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(
        _ch(myValue: 30000),
        board: [row('me', 30000, 1), row('Sam', 10000, 2)],
      )));
      await tester.pump();

      expect(find.text('#1 of 2'), findsOneWidget);
      expect(find.text('Leading'), findsOneWidget);
      expect(find.textContaining('behind'), findsNothing);
    });

    testWidgets('a tied leader reports the tie instead of claiming the lead',
        (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(
        _ch(myValue: 30000),
        board: [row('me', 30000, 1), row('Alex', 30000, 1)],
      )));
      await tester.pump();

      expect(find.text('Tied with 1 other'), findsOneWidget);
      expect(find.text('Leading'), findsNothing);
    });

    testWidgets('a viewer who is not on the board gets no card', (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(
        _ch(myValue: null),
        board: [row('Alex', 30000, 1), row('Sam', 10000, 2)],
      )));
      await tester.pump();

      expect(find.byKey(const Key('challenge-standing')), findsNothing);
    });

    testWidgets('a one-entrant board gets no card rather than "#1 of 1"',
        (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(
        _ch(myValue: 30000),
        board: [row('me', 30000, 1)],
      )));
      await tester.pump();

      expect(find.byKey(const Key('challenge-standing')), findsNothing);
      expect(find.text('#1 of 1'), findsNothing);
    });

    testWidgets('an empty board gets no card', (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(_ch(myValue: null))));
      await tester.pump();

      expect(find.byKey(const Key('challenge-standing')), findsNothing);
    });

    // A runner in two competing clubs must be credited to the one their
    // participant row names, not to whichever of theirs tops the board.
    testWidgets('a team board keys on the club the viewer joined under',
        (tester) async {
      await tester.pumpWidget(_app(_FakeSocial(
        _ch(myValue: null, scope: 'club_vs_club', myTeamClubId: 'club-b'),
        board: const [
          ChallengeLeaderboardEntry(
            userId: null,
            displayName: null,
            teamClubId: 'club-a',
            value: 30000,
            rank: 1,
          ),
          ChallengeLeaderboardEntry(
            userId: null,
            displayName: null,
            teamClubId: 'club-b',
            value: 10000,
            rank: 2,
          ),
        ],
        clubs: [_club('club-a', 'Road Club'), _club('club-b', 'Trail Club')],
      )));
      await tester.pump();

      expect(find.text("Your team's standing"), findsOneWidget);
      expect(find.text('#2 of 2'), findsOneWidget);
      expect(find.textContaining('behind Road Club'), findsOneWidget);
    });
  });

  group('ChallengeDetailScreen — the leaderboard rank lane', () {
    // The rank sat in a 36px box. "#999" needs 48.7px in real Roboto at
    // bodyMedium w600 once the OS text scale reaches 1.5x and 64.9 at 2x, and
    // a rank token has no break opportunity, so it painted over the
    // participant's name beside it. A four-digit rank clears the box at 1.0x.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane whose floor tracks
    // the scale here tracks it on a device too.
    Future<void> pumpBoard(WidgetTester tester, {double scale = 1.0}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ChallengeDetailScreen(
            social: _FakeSocial(
              _ch(myValue: 20000),
              board: const [
                ChallengeLeaderboardEntry(
                  userId: 'u-1',
                  displayName: 'Backmarker',
                  teamClubId: null,
                  value: 500,
                  rank: 999,
                ),
              ],
            ),
            challengeId: 'c1',
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the lane widens to the rank instead of overpainting',
        (tester) async {
      await pumpBoard(tester);
      final lane = find.ancestor(
        of: find.text('#999'),
        matching: find.byType(TextLane),
      );
      expect(lane, findsOneWidget);
      final rank = tester.renderObject<RenderParagraph>(find.text('#999'));
      expect(
        tester.getSize(lane).width,
        greaterThanOrEqualTo(rank.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('the lane floor grows with the OS text scale', (tester) async {
      await pumpBoard(tester, scale: 2.0);
      final lane = find.byType(TextLane).first;
      expect(tester.getSize(lane).width,
          greaterThanOrEqualTo(tester.widget<TextLane>(lane).width * 2));
    });
  });
}

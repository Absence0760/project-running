import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/geocoding.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/clubs_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/verified_badge.dart';

ClubView _club({
  String id = 'club-1',
  String name = 'Track Club',
  String slug = 'track-club',
  bool isPublic = true,
  bool isVerified = false,
  String? locationLabel,
  int memberCount = 5,
  String? viewerRole,
}) =>
    ClubView(
      row: ClubRow(
        id: id,
        ownerId: 'owner',
        name: name,
        slug: slug,
        isPublic: isPublic,
        isVerified: isVerified,
        locationLabel: locationLabel,
        joinPolicy: 'open',
        memberCount: memberCount,
        requiresActivityWaiver: false,
      ),
      memberCount: memberCount,
      viewerRole: viewerRole,
      viewerStatus: viewerRole == null ? null : 'active',
      joinPolicy: 'open',
    );

/// Fake that returns canned browse / mine lists. Captures the term passed
/// to searchClubs so the Browse search wiring can be asserted.
class _FakeSocial extends SocialService {
  _FakeSocial({this.browse = const [], this.mine = const []});
  List<ClubView> browse;
  List<ClubView> mine;
  String? lastSearchTerm;
  int browseCalls = 0;

  @override
  Future<List<ClubView>> browseClubs({String? query}) async {
    browseCalls++;
    return browse;
  }

  @override
  Future<List<ClubView>> searchClubs(
    String query, {
    required String mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
  }) async {
    lastSearchTerm = query;
    return browse;
  }

  @override
  Future<List<ClubView>> fetchMyClubs() async => mine;
}

/// Fake whose load throws, to drive the generic error state.
class _ThrowingSocial extends SocialService {
  @override
  Future<List<ClubView>> browseClubs({String? query}) async =>
      throw Exception('boom');
  @override
  Future<List<ClubView>> fetchMyClubs() async => const [];
}

/// Fake whose load stays in flight until [gate] is completed, so a test
/// can observe the loading spinner before resolving it cleanly.
class _SlowSocial extends SocialService {
  final Completer<List<ClubView>> gate = Completer<List<ClubView>>();
  @override
  Future<List<ClubView>> browseClubs({String? query}) => gate.future;
  @override
  Future<List<ClubView>> fetchMyClubs() async => const [];
}

Future<void> _pump(WidgetTester tester, SocialService social) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ClubsScreen(
        social: social,
        training: TrainingService(),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    // ClubsScreen._load reads dotenv.env['MAPTILER_KEY']; without a
    // testLoad the access throws NotInitializedError and the load fails
    // into the error state before any list can render.
    dotenv.loadFromString(isOptional: true);
  });

  group('ClubsScreen — initial render', () {
    testWidgets('renders the Clubs app-bar title', (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.text('Clubs'), findsOneWidget);
    });

    testWidgets('renders the Browse / My clubs segmented button',
        (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
      expect(find.text('My clubs'), findsOneWidget);
    });

    testWidgets('starts on the My clubs tab — search field is hidden',
        (tester) async {
      // Reason: returning users default to "My clubs" so they see the
      // clubs they're already in. Browse-only widgets (the search
      // TextField) must NOT render on first paint.
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search by name or location'),
          findsNothing);
    });

    testWidgets('renders the New club FAB with an add icon',
        (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('New club'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('switching to the Browse tab reveals the search field',
        (tester) async {
      await _pump(tester, _FakeSocial());
      await tester.pump();
      // Tap the "Browse" segment.
      await tester.tap(find.text('Browse'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Search by name or location'),
          findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('the Browse search field exposes a persistent accessible name',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _FakeSocial());
      await tester.pump();
      await tester.tap(find.text('Browse'));
      await tester.pump();
      // Semantics wrapper keeps the field named once the hint disappears on
      // typing (web parity: SocialClubs' aria-label).
      expect(
        find.bySemanticsLabel(RegExp('Search by name or location')),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });
  });

  group('ClubsScreen — list rendering', () {
    testWidgets('renders a row per "my club" once the load resolves',
        (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [
          _club(id: 'a', name: 'Morning Milers', slug: 'morning-milers'),
          _club(id: 'b', name: 'Sunset Striders', slug: 'sunset-striders'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Morning Milers'), findsOneWidget);
      expect(find.text('Sunset Striders'), findsOneWidget);
    });

    testWidgets('a private club shows the PRIVATE badge', (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(name: 'Secret Squad', isPublic: false)]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PRIVATE'), findsOneWidget);
    });

    testWidgets('a verified club renders the verified badge', (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(name: 'Richmond Marathon', isVerified: true)]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(VerifiedBadge), findsOneWidget);
    });

    testWidgets('a club with a location renders the place label',
        (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(locationLabel: 'Norfolk, VA')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Norfolk, VA'), findsOneWidget);
      expect(find.byIcon(Icons.place), findsOneWidget);
    });

    testWidgets('a viewer role pill shows for clubs the user belongs to',
        (tester) async {
      await _pump(
        tester,
        _FakeSocial(mine: [_club(viewerRole: 'admin')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('admin'), findsOneWidget);
    });
  });

  group('ClubsScreen — empty states', () {
    testWidgets('an empty My clubs tab shows the mine empty state',
        (tester) async {
      await _pump(tester, _FakeSocial(mine: const [], browse: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // person_add_alt_1 is the My-clubs empty glyph.
      expect(find.byIcon(Icons.person_add_alt_1), findsOneWidget);
    });

    testWidgets('an empty Browse tab shows the browse empty state',
        (tester) async {
      await _pump(tester, _FakeSocial(mine: const [], browse: const []));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Browse'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // groups is the Browse empty glyph.
      expect(find.byIcon(Icons.groups), findsOneWidget);
    });
  });

  group('ClubsScreen — error states', () {
    testWidgets('a failed load shows the generic error state with Retry',
        (tester) async {
      await _pump(tester, _ThrowingSocial());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a slow load shows the loading spinner before it resolves',
        (tester) async {
      final social = _SlowSocial();
      await _pump(tester, social);
      await tester.pump();
      // Load is gated → spinner persists until the gate completes.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Release the gate so the .timeout(...) timer + future drain cleanly.
      social.gate.complete(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });

  group('ClubsScreen — Browse search', () {
    testWidgets('submitting a Browse query routes through searchClubs',
        (tester) async {
      final social = _FakeSocial(browse: const []);
      await _pump(tester, social);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Browse'));
      await tester.pump();

      await tester.enterText(
          find.widgetWithText(TextField, 'Search by name or location'),
          'Virginia');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(social.lastSearchTerm, 'Virginia');
    });
  });
}

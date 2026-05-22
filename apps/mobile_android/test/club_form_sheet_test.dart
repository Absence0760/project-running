import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/social_service.dart';
import '../lib/widgets/club_form_sheet.dart';

/// Test double that bypasses Supabase entirely. Only `createClub` is
/// overridden — every other method on `SocialService` is unreachable
/// in the bottom-sheet widget tree, so leaving them as superclass
/// invocations is safe.
class _FakeSocialService extends SocialService {
  final Object _throwOnCreate;
  _FakeSocialService(this._throwOnCreate);
  // The page now probes `isReady` BEFORE calling createClub (defence
  // against the "Bad state: SocialService called before Supabase
  // .initialize() resolved." crash the user reported). Test doubles
  // must opt-in to "ready" so the throwOnCreate path actually fires.
  @override
  bool get isReady => true;
  @override
  Future<ClubRow> createClub({
    required String name,
    required String slug,
    String? description,
    String? locationLabel,
    bool isPublic = true,
    String joinPolicy = 'open',
  }) async {
    throw _throwOnCreate;
  }
}

class _Launcher extends StatefulWidget {
  final SocialService social;
  const _Launcher({required this.social});

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  String? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () async {
                final r = await showClubFormSheet(context, social: widget.social);
                setState(() => _result = r ?? '<cancelled>');
              },
              child: const Text('Open'),
            ),
            if (_result != null) Text('result=$_result'),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSheet(WidgetTester tester, {SocialService? social}) async {
  // Bottom sheet content overflows the default 600x800 test viewport;
  // give it room so the SegmentedButton at the bottom of the form
  // actually paints into the layer tree.
  await tester.binding.setSurfaceSize(const Size(600, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: _Launcher(social: social ?? SocialService())),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('showClubFormSheet', () {
    testWidgets('renders the New club heading and Name / Description / Location fields',
        (tester) async {
      await _openSheet(tester);
      expect(find.text('New club'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Description (optional)'),
          findsOneWidget);
      expect(find.widgetWithText(TextField, 'Location (optional)'),
          findsOneWidget);
    });

    testWidgets('renders the Public / Private visibility segmented button',
        (tester) async {
      await _openSheet(tester);
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    });

    testWidgets(
        'create_club P0001 rate-limit surfaces the friendly "slow down" message',
        (tester) async {
      // Mirror of the web e2e in clubs/new.spec.ts: when the BEFORE
      // INSERT trigger from migration 20260907_001 fires, the
      // PostgrestException is caught in club_form_sheet.dart and run
      // through rate_limit_errors.dart. The friendly message replaces
      // the raw exception toString. Pin the wording so a refactor
      // can't silently revert to the verbose form.
      final fake = _FakeSocialService(PostgrestException(
        message: 'rate limit exceeded for create_club, retry in 1234s',
        code: 'P0001',
      ));
      await _openSheet(tester, social: fake);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'My Spam Club',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('creating clubs too quickly'),
          findsOneWidget);
      // Negative pin: the raw verbose PostgrestException toString
      // (which leaks SQLSTATE and the bucket name) must NOT appear.
      expect(find.textContaining('P0001'), findsNothing);
      expect(find.textContaining('PostgrestException'), findsNothing);
    });

    testWidgets(
        'non-rate-limit errors still surface verbatim (debug info preserved)',
        (tester) async {
      // The catch in club_form_sheet should ONLY translate the rate-
      // limit path; unrelated PostgrestExceptions (RLS denies, foreign
      // key violations, etc.) keep their raw text so debugging info
      // isn't hidden.
      final fake = _FakeSocialService(PostgrestException(
        message: 'permission denied for table clubs',
        code: '42501',
      ));
      await _openSheet(tester, social: fake);

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Locked-out Club',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission denied for table clubs'),
          findsOneWidget);
      expect(find.textContaining('creating clubs too quickly'),
          findsNothing);
    });

    testWidgets(
      'opens as a full-screen page with an AppBar back button — '
      'NOT a modal bottom sheet (user-requested layout change)',
      (tester) async {
        // The user surfaced "they also seem to be using the old modal,
        // and not the page with the back button" — pin the new
        // MaterialPageRoute shape so a future refactor that reverts
        // to showModalBottomSheet fails this test loud.
        await _openSheet(tester);
        // Full-screen page anchored AppBar.
        expect(find.byType(AppBar), findsOneWidget);
        // Back arrow auto-injected by MaterialPageRoute.
        expect(find.byTooltip('Back'), findsOneWidget);
      },
    );

    testWidgets(
      'readiness probe fires friendly inline error when '
      'SocialService is not ready — no raw StateError leak',
      (tester) async {
        // The user reported "Bad state: SocialService called before
        // Supabase.initialize() resolved" on Create. The page now
        // probes `isReady` BEFORE the call so the friendly copy
        // surfaces instead of the raw stack trace.
        await _openSheet(tester);
        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'Loop Club',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining("Can't reach the server right now"),
          findsOneWidget,
        );
        // Raw stack-trace fragments must not reach the surface.
        expect(find.textContaining('Bad state'), findsNothing);
        expect(
          find.textContaining('Supabase.initialize'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'defensive catch maps late StateError from createClub to the '
      'same friendly copy (readiness probe was stale)',
      (tester) async {
        // If the readiness probe was stale between the pre-flight
        // check and the actual call (race), the defensive catch in
        // _submit must catch + remap the StateError so the user
        // never sees the raw "Bad state:" prefix.
        final fake = _FakeSocialService(
          StateError(
            'SocialService called before Supabase.initialize() resolved.',
          ),
        );
        await _openSheet(tester, social: fake);
        await tester.enterText(
          find.widgetWithText(TextField, 'Name'),
          'Loop Club',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining("Can't reach the server right now"),
          findsOneWidget,
        );
        expect(find.textContaining('Bad state'), findsNothing);
      },
    );

    testWidgets(
      'form body is wrapped in SingleChildScrollView — prevents the '
      '"BOTTOM OVERFLOWED" overflow under a shrunk viewport',
      (tester) async {
        // The user reported "BOTTOM OVERFLOWED BY 54 PIXELS" on the
        // New Club page when a typing field had focus + keyboard up.
        // Pin the new scrollable form layout.
        await _openSheet(tester);
        expect(
          find.byType(SingleChildScrollView),
          findsOneWidget,
          reason: 'Form must wrap its column in SingleChildScrollView '
              'so the body can scroll when the keyboard shrinks the '
              'viewport.',
        );
      },
    );
  });

  group('SocialService.isReady', () {
    test('returns false when Supabase has not been initialised', () {
      // The probe must return false WITHOUT throwing so UIs can
      // gate their submit-buttons / show friendly errors. Pre-fix,
      // touching `_c` threw immediately; isReady is the safe probe.
      final social = SocialService();
      expect(social.isReady, isFalse);
    });

    test('does NOT throw — probe is safe to call before any Supabase work',
        () {
      // The whole point of the probe: pre-flight check without
      // crashing. Pin so a refactor that re-throws (e.g.
      // delegating to `_c` directly) gets caught at test time.
      final social = SocialService();
      expect(
        () => social.isReady,
        returnsNormally,
        reason: 'isReady must never throw — the WHOLE point of the '
            'probe is to be a safe pre-flight check. Pre-fix, '
            'touching `_c` threw immediately, which is what the '
            'user reported as "Bad state: SocialService called '
            'before Supabase.initialize() resolved."',
      );
    });

    test('test-double subclass can opt-in via `isReady` override', () {
      // The club-form-sheet test pattern uses subclasses overriding
      // `isReady` so the screen\'s pre-flight check passes through
      // to the createClub stub. Pin that the override path actually
      // works — without it the new readiness gate would short-
      // circuit every existing test_double-driven test.
      final readyDouble = _AlwaysReadySocial();
      expect(readyDouble.isReady, isTrue);
    });
  });
}

/// Minimal test double that opts-in to "ready" via the override
/// hook. Mirrors the pattern used in club_form_sheet_test.dart.
class _AlwaysReadySocial extends SocialService {
  _AlwaysReadySocial() : super();
  @override
  bool get isReady => true;
}

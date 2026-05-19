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
  });
}

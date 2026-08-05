import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/widgets/sign_in_required_state.dart';
import '../lib/training_service.dart';

/// Reports a non-null consent timestamp so the screen renders its main
/// (consented) Scaffold — the one whose left drawer used to swallow the
/// back button — instead of the GDPR consent gate.
class _ConsentedApi extends ApiClient {
  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get userId => 'u-viewer';
  @override
  Future<DateTime?> fetchCoachConsentAt() async => DateTime(2026, 1, 1);
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

/// Signed in, but every fetch fails against the unconnected local
/// Supabase — so `_consentAt` resolves to null. Stands in for "signed
/// in, consent not yet given", which is what the GDPR gate is about;
/// the chat surface itself is auth-only, so a viewer id is required to
/// reach it at all.
class _SignedInApi extends ApiClient {
  @override
  String? get userId => 'u-viewer';
}

class _SignedOutApi extends ApiClient {
  @override
  String? get userId => null;
}

/// Consented, with one loaded message so the new-chat action renders, and
/// an archive write that always fails — drives the archive-failure banner
/// + its Retry action (which must re-run the mutation, not the dialog).
class _ArchiveFailApi extends ApiClient {
  int archiveCalls = 0;

  @override
  String? get userId => 'u-viewer';

  @override
  Future<DateTime?> fetchCoachConsentAt() async => DateTime(2026, 1, 1);

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async => [
        CoachMessageRow(
          id: 'm1',
          userId: 'u-viewer',
          role: 'user',
          content: 'How was my week?',
          createdAt: DateTime.utc(2026, 6, 1),
        ),
      ];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => const [];

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;

  @override
  Future<void> archiveCoachThread({String? planId}) async {
    archiveCalls++;
    throw Exception('network down');
  }
}

/// Consented, with one archived thread so the history drawer renders a row —
/// drives the archive-row overflow delete + its confirm.
class _ArchivesApi extends ApiClient {
  int deleteCalls = 0;
  final archivedAt = DateTime.utc(2026, 6, 1, 8);

  @override
  String? get userId => 'u-viewer';

  @override
  Future<DateTime?> fetchCoachConsentAt() async => DateTime(2026, 1, 1);

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async =>
      const [];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async =>
      [archivedAt];

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
  }
}

/// Unmount the screen, then pump past the disconnect timer its realtime
/// unsubscribe schedules. `CoachScreen.dispose` calls
/// `RealtimeChannel.unsubscribe`, and realtime_client arms a 50 s pending
/// disconnect from inside that call — so the timer does not exist until the
/// tree is torn down, and no amount of pumping beforehand can drain it.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 60));
}

Future<void> _pump(WidgetTester tester, {ApiClient? api}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachScreen(
        api: api ?? _SignedInApi(),
        training: TrainingService(),
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('CoachScreen — initial render', () {
    testWidgets('renders the Coach app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Coach'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('the consented view renders an explicit back button (the left '
        'drawer used to swallow it)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CoachScreen(api: _ConsentedApi(), training: TrainingService()),
        ),
      );
      // Let the consent lookup resolve so the main Scaffold mounts.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The archive drawer is reachable from an explicit history action
      // instead, so the leading slot stays a real back affordance.
      expect(find.byType(BackButton), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('does not render the plan-switcher dropdown when there is at most one plan',
        (tester) async {
      // Reason: the title-row dropdown only mounts when _plans has
      // more than one entry — in tests there's no Supabase data so
      // the list stays empty and the dropdown stays hidden.
      await _pump(tester);
      expect(find.byType(DropdownButton<String>), findsNothing);
      await _drain(tester);
    });

    testWidgets('a signed-out viewer gets the sign-in state, not the chat '
        '(issue #237)', (tester) async {
      // The chat is auth-only (consent stamp, usage cap, message
      // persistence). Signed out, every RPC silently defaulted and the
      // user only found out at send time — fail closed instead.
      await _pump(tester, api: _SignedOutApi());
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(find.text('Before you chat with Coach'), findsNothing);
    });

    testWidgets('without coach_consent_at the chat is gated behind the GDPR '
        'disclosure (audit/gdpr 2026-05-25)', (tester) async {
      // Reason: Coach forwards health-adjacent data to Anthropic
      // (US sub-processor) — GDPR Art 6(1)(a) requires an
      // affirmative consent act before the first dispatch. The
      // _bootstrap fetch fails against the unconnected local
      // Supabase, so _consentAt resolves to null, which must render
      // the disclosure copy instead of the chat composer.
      await _pump(tester);
      // Pump past the post-frame fetch attempt + the 100ms safety
      // margin to let _consentChecked flip true on failure.
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('Before you chat with Coach'),
        findsOneWidget,
        reason: 'consent disclosure must be visible when '
            'coach_consent_at is null — see audit/gdpr (2026-05-25).',
      );
      expect(
        find.text('I consent — start Coach'),
        findsOneWidget,
        reason: 'the I-consent CTA must be reachable from the '
            'gate so the user can accept.',
      );
      await _drain(tester);
    });
  });

  group('CoachScreen — archive failure retry (issue #666 U9)', () {
    testWidgets(
        'a failed new-conversation archive shows a Retry banner that '
        're-runs the mutation without re-prompting', (tester) async {
      final api = _ArchiveFailApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CoachScreen(api: api, training: TrainingService()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // One loaded message → the new-chat action renders in the AppBar.
      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pump();
      expect(find.text('Start a new conversation?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'New chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.archiveCalls, 1);
      expect(find.text('Could not start a new conversation.'), findsOneWidget);
      final retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.archiveCalls, 2);
      // Retry re-runs the mutation directly — no second confirm dialog.
      expect(find.text('Start a new conversation?'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      await _drain(tester);
    });
  });

  group('CoachScreen — archived-conversation delete (issue #666 U7)', () {
    // The archive list was the app's only swipe-to-delete surface, and its
    // `confirmDismiss` ran the delete instead of asking: a stray swipe erased
    // a conversation with no confirm and no undo. It now uses the same
    // overflow-menu idiom as every other row in the app.
    Future<_ArchivesApi> openDrawer(WidgetTester tester) async {
      final api = _ArchivesApi();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CoachScreen(api: api, training: TrainingService()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Chat history'));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('the archive row is not swipeable and teaches no swipe',
        (tester) async {
      await openDrawer(tester);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.textContaining('swipe'), findsNothing);
      expect(find.text('Tap to view'), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('the overflow delete asks before erasing, and cancel keeps it',
        (tester) async {
      final api = await openDrawer(tester);

      await tester.tap(find.byTooltip('Conversation actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this conversation?'), findsOneWidget);
      expect(api.deleteCalls, 0);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel'),
      ));
      await tester.pumpAndSettle();
      expect(api.deleteCalls, 0);
      await _drain(tester);
    });

    testWidgets('confirming deletes once and drops the row', (tester) async {
      final api = await openDrawer(tester);

      await tester.tap(find.byTooltip('Conversation actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete conversation'),
      ));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, 1);
      expect(find.byTooltip('Conversation actions'), findsNothing);
      await _drain(tester);
    });
  });
}

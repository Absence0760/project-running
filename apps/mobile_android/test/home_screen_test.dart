import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/settings_destination.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/screens/home_screen.dart';
import '../lib/screens/run_screen.dart';
import '../lib/screens/settings_about_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/screens/setup_wizard_screen.dart';

/// Drives auth transitions for the setup-wizard gate (#232): a fresh
/// account (onboarded_at null) signs in after launch.
class _WizardApi extends ApiClient {
  String? uid;
  final _controller = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;

  @override
  Stream<String?> get authUserChanges => _controller.stream;

  @override
  Future<cm.UserProfileRow?> fetchMyProfile() async => uid == null
      ? null
      : cm.UserProfileRow(shadowHidden: false, id: uid!, displayName: null);

  void emit() => _controller.add(uid);
}

Directory? _runsDir;

Future<({
  LocalRunStore runStore,
  LocalRouteStore routeStore,
  LocalGearStore gearStore,
  LocalGymStore gymStore,
  LocalFoodStore foodStore,
  Preferences prefs,
  SocialService social,
  TrainingService training,
  BleHeartRate heartRate,
  BleTreadmill treadmill,
  AudioCues audioCues,
  RaceController raceController,
})> _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('home_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  final routeStore = LocalRouteStore();
  final gearStore = LocalGearStore();
  await gearStore.init(
      overrideDirectory:
          Directory.systemTemp.createTempSync('gear_store_test_'));
  final gymStore = LocalGymStore();
  await gymStore.init(
      overrideDirectory: Directory.systemTemp.createTempSync('gym_store_test_'));
  final foodStore = LocalFoodStore();
  await foodStore.init(
      overrideDirectory:
          Directory.systemTemp.createTempSync('food_store_test_'));
  final social = SocialService();
  final training = TrainingService();
  final heartRate = BleHeartRate();
  final treadmill = BleTreadmill();
  final audioCues = AudioCues();
  final raceController = RaceController(social);

  return (
    runStore: runStore,
    routeStore: routeStore,
    gearStore: gearStore,
    gymStore: gymStore,
    foodStore: foodStore,
    prefs: prefs,
    social: social,
    training: training,
    heartRate: heartRate,
    treadmill: treadmill,
    audioCues: audioCues,
    raceController: raceController,
  );
}

Future<void> _pump(WidgetTester tester, dynamic s, {ApiClient? api}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(
        apiClient: api,
        runStore: s.runStore,
        routeStore: s.routeStore,
        gearStore: s.gearStore,
        gymStore: s.gymStore,
        foodStore: s.foodStore,
        preferences: s.prefs,
        audioCues: s.audioCues,
        social: s.social,
        raceController: s.raceController,
        training: s.training,
        heartRate: s.heartRate,
        treadmill: s.treadmill,
      ),
    ),
  );
  // Single pump — pumpAndSettle risks hanging when RunScreen's async
  // refresh tasks (fetchNextRsvpedEvent, fetchActiveOverview) fail against
  // an uninitialised Supabase instance and reschedule timers.
  await tester.pump();
}

class _StampApi extends ApiClient {
  int markOnboardedCalls = 0;
  bool failStamp = false;

  @override
  String? get userId => 'u1';

  @override
  Future<void> markOnboarded() async {
    markOnboardedCalls++;
    if (failStamp) throw Exception('network unreachable');
  }
}

void main() {
  tearDown(() {
    // The swipe-lock signal is a process-global ValueNotifier; reset it so a
    // recording-active test can't leak the lock into the next test (#490).
    runRecordingActive.value = false;
    // Null when the test never built the stores (the pure gate-helper
    // group below has no run store on disk).
    if (_runsDir?.existsSync() ?? false) {
      _runsDir!.deleteSync(recursive: true);
    }
    _runsDir = null;
  });

  group('deferredOnboardingStampHandled (issue #246)', () {
    Future<Preferences> makePrefs() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      return prefs;
    }

    test('no dismissal flag: gate proceeds normally, no stamp attempt',
        () async {
      final prefs = await makePrefs();
      final api = _StampApi();
      expect(await deferredOnboardingStampHandled(api, prefs), isFalse);
      expect(api.markOnboardedCalls, 0);
    });

    test('flag set + stamp lands: wizard suppressed, flag cleared', () async {
      final prefs = await makePrefs();
      await prefs.setSetupWizardDismissed(true);
      final api = _StampApi();
      expect(await deferredOnboardingStampHandled(api, prefs), isTrue);
      expect(api.markOnboardedCalls, 1);
      expect(prefs.setupWizardDismissed, isFalse,
          reason: 'a landed stamp retires the deferred flag');
    });

    test('flag set + stamp still failing: wizard suppressed, flag kept',
        () async {
      final prefs = await makePrefs();
      await prefs.setSetupWizardDismissed(true);
      final api = _StampApi()..failStamp = true;
      expect(await deferredOnboardingStampHandled(api, prefs), isTrue,
          reason: 'the user chose Finish later — never re-trap them in '
              'the wizard while the stamp is queued');
      expect(prefs.setupWizardDismissed, isTrue,
          reason: 'the queued stamp retries on the next launch');
    });
  });

  group('HomeScreen multi-modal shell', () {
    testWidgets('uses a BottomAppBar + a centre Log FAB, not a NavigationBar',
        (tester) async {
      // Phase 4 reshape (multi_modal.md § Bottom nav): Run leaves the nav as
      // a top-level destination; the centre slot becomes the raised Log
      // action button.
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(BottomAppBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets(
        'shows Home/Fitness/Social/You nav labels; Run/History/Settings are not nav labels',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      final bar = find.byType(BottomAppBar);
      for (final label in ['Home', 'Fitness', 'Social', 'You']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
          reason: 'expected "$label" nav label inside BottomAppBar',
        );
      }
      // History is absorbed into Fitness → All; Settings folds into You;
      // Run is captured via the Log button — none are bottom-nav labels.
      for (final gone in ['Run', 'History', 'Settings']) {
        expect(
          find.descendant(of: bar, matching: find.text(gone)),
          findsNothing,
          reason: '"$gone" is no longer a bottom-nav destination',
        );
      }
    });

    testWidgets('the centre Log action shows a visible text label (#256)',
        (tester) async {
      // Every nav tab carries a text label; the centre Log action used to be
      // an unlabelled "+" FAB with a tooltip only. It now caption's "Log"
      // inside the bar so the affordance is discoverable without a hover.
      final s = await _makeStores();
      await _pump(tester, s);
      final bar = find.byType(BottomAppBar);
      expect(
        find.descendant(of: bar, matching: find.text('Log')),
        findsOneWidget,
        reason: 'the centre Log action must carry a visible label in the bar',
      );
    });

    testWidgets('initial page is Home (welcome empty state)', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.pump();
      expect(find.text('Welcome!'), findsAtLeastNWidgets(1));
    });

    testWidgets('body is a PageView', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('tapping the Log FAB fans the capture speed-dial (default mode)',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Log run'), findsOneWidget);
      expect(find.byTooltip('Log lift'), findsOneWidget);
      expect(find.byTooltip('Log food'), findsOneWidget);
      // Each fan item carries its label as visible text, not only a tooltip.
      expect(find.text('Log run'), findsOneWidget);
    });

    testWidgets('keepRunPrimary: tapping the Log FAB starts a run, no menu',
        (tester) async {
      final s = await _makeStores();
      await s.prefs.setKeepRunPrimary(true);
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump();
      // No fan — the tap jumped straight to the Run page.
      expect(find.byTooltip('Log lift'), findsNothing);
    });

    testWidgets('picking Log lift lands on the Gym dwell-in page', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Log lift'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Not a modal composer — the Log action navigates the PageView to the
      // in-shell Gym page (same model as the run recorder), so the bottom nav
      // stays visible alongside the page's own "Gym" AppBar title.
      expect(find.text('Gym'), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget);
    });

    testWidgets('picking Log food lands on the Nutrition dwell-in page',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Log food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget);
    });

    testWidgets(
        'setup wizard fires for a fresh account signing in after launch (#232)',
        (tester) async {
      final s = await _makeStores();
      final api = _WizardApi();
      await _pump(tester, s, api: api);
      await tester.pump();
      // Launched signed out: the post-frame gate must not push anything.
      expect(find.byType(SetupWizardScreen), findsNothing);

      // The normal signup flow — the account is created after launch. The
      // gate used to run once per process, so this user never saw the
      // wizard (nor did a fresh account B signing in over A's session).
      api.uid = 'u9';
      api.emit();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SetupWizardScreen), findsOneWidget);
    });
  });

  group('HomeScreen expanded (tablet) shell', () {
    testWidgets('expanded swaps the BottomAppBar for a NavigationRail',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomAppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Fitness'), findsOneWidget);
    });

    testWidgets('rail destinations navigate and the Log FAB fans the dial',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.text('Fitness'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Runs'), findsWidgets);
      // The Fitness page contributes its own Add-run FAB, so scope to the
      // rail's Log tooltip.
      await tester.tap(find.byTooltip('Log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Log food'), findsOneWidget);
      final fab = tester.getCenter(find.byTooltip('Log'));
      final item = tester.getCenter(find.byTooltip('Log food'));
      expect(item.dx, greaterThan(fab.dx));
      await tester.tapAt(const Offset(1200, 700));
      await tester.pump();
    });

    testWidgets('medium width keeps the phone shell', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(BottomAppBar), findsOneWidget);
    });

    // The derivation, not a dp figure: whichever shell is up, a page reads the
    // SAME bottom padding, so `SafeArea(bottom: false)` and
    // `fabScrollClearance` mean the same thing on a tablet as on a phone
    // (issue #666 C14, decisions § 538). Both shells are asserted in one test
    // so the equality is the assertion, not a constant either side could
    // drift from.
    testWidgets('both shells hand a page the same bottom inset', (
      tester,
    ) async {
      Future<double> bottomPaddingOn(Size size) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2.0;
        // A phone's 3-button navigation bar. Without a real inset the two
        // shells agree at zero and the test proves nothing (decisions § 534).
        tester.view.padding = const FakeViewPadding(bottom: 48 * 2);
        tester.view.viewPadding = const FakeViewPadding(bottom: 48 * 2);
        final s = await _makeStores();
        await _pump(tester, s);
        return MediaQuery.of(
          tester.element(find.byType(PageView)),
        ).padding.bottom;
      }

      addTearDown(tester.view.reset);
      final phone = await bottomPaddingOn(const Size(390, 844));
      expect(find.byType(BottomAppBar), findsOneWidget);
      final tablet = await bottomPaddingOn(const Size(1280, 800));
      expect(find.byType(NavigationRail), findsOneWidget);

      expect(phone, 0, reason: 'the BottomAppBar already spent the inset');
      expect(
        tablet,
        phone,
        reason: 'the rail shell left the system inset for the pages to '
            'consume, and they pass bottom: false',
      );
    });
  });

  group('HomeScreen swipe lock during recording (#490)', () {
    testWidgets('idle: the tab PageView is swipeable', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      final physics = tester.widget<PageView>(find.byType(PageView)).physics;
      expect(physics, isNot(isA<NeverScrollableScrollPhysics>()),
          reason: 'with no run recording the tabs stay swipeable');
    });

    testWidgets('actively recording: the tab swipe gesture is locked',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      runRecordingActive.value = true;
      await tester.pump();
      final physics = tester.widget<PageView>(find.byType(PageView)).physics;
      expect(physics, isA<NeverScrollableScrollPhysics>(),
          reason: 'an active run must block the accidental swipe-away');
    });

    testWidgets('recording: a bottom-nav tap still switches pages',
        (tester) async {
      // The lock only kills the drag gesture — deliberate navigation via a
      // nav tap drives the page controller directly and must still work, so a
      // runner is never trapped on the recording surface.
      final s = await _makeStores();
      await _pump(tester, s);
      runRecordingActive.value = true;
      await tester.pump();
      await tester.tap(find.text('Fitness'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Runs'), findsWidgets,
          reason: 'the Fitness hub mounted, so the tap navigated the PageView '
              'despite the locked swipe physics');
    });
  });

  group('Settings destination seam (decisions § 710)', () {
    // The shell is the host for "open a Settings sub-screen" because it is
    // the one place holding every dependency those screens take. A surface
    // buried in a tab names the destination; these pin that the name is what
    // actually reaches the screen.
    setUp(() => pendingSettingsDestination.value = null);
    tearDown(() => pendingSettingsDestination.value = null);

    /// Lets the pushed route's transition run without pumpAndSettle, which
    /// hangs on the shell's rescheduling async tabs.
    Future<void> openAndSettle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a parked preferences intent opens SettingsPreferencesScreen',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(SettingsPreferencesScreen), findsNothing);

      openSettings(SettingsDestination.preferences);
      await openAndSettle(tester);

      expect(find.byType(SettingsPreferencesScreen), findsOneWidget,
          reason: 'the People tab holds neither a Preferences nor a '
              'SettingsSyncService — naming the destination has to be enough');
    });

    testWidgets('the shell clears the slot as it navigates', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      openSettings(SettingsDestination.preferences);
      await openAndSettle(tester);

      expect(pendingSettingsDestination.value, isNull,
          reason: 'a slot left full would swallow the next identical request, '
              'since a ValueNotifier is silent on an unchanged value');
    });

    testWidgets('each name reaches its own screen', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      openSettings(SettingsDestination.about);
      await openAndSettle(tester);

      expect(find.byType(SettingsAboutScreen), findsOneWidget);
      expect(find.byType(SettingsPreferencesScreen), findsNothing);
    });

    testWidgets('an unrequested shell pushes nothing', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await openAndSettle(tester);
      expect(find.byType(SettingsPreferencesScreen), findsNothing);
      expect(find.byType(SettingsAboutScreen), findsNothing);
    });

    testWidgets('a request parked before the shell mounts still opens',
        (tester) async {
      // Same contract pendingPushTarget carries: a cold start drains on the
      // first frame, so an intent set before any Navigator existed is not lost.
      final s = await _makeStores();
      openSettings(SettingsDestination.preferences);
      await _pump(tester, s);
      await openAndSettle(tester);

      expect(find.byType(SettingsPreferencesScreen), findsOneWidget);
    });
  });
}

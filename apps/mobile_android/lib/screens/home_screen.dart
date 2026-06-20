import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;

import '../audio_cues.dart';
import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../local_gear_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../main.dart' show pendingStartWorkout;
import '../preferences.dart';
import '../race_controller.dart';
import '../settings_sync.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../widgets/billing_issue_banner.dart';
import '../widgets/log_sheet.dart';
import '../widgets/top_banner.dart';
import 'dashboard_screen.dart';
import 'fitness_hub_screen.dart';
import 'gym_screen.dart';
import 'nutrition_screen.dart';
import 'run_screen.dart';
import 'setup_wizard_screen.dart';
import 'social_screen.dart';
import 'you_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGearStore gearStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final SocialService social;
  final RaceController raceController;
  final TrainingService training;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final SettingsSyncService? settingsSync;
  final cm.Run? recoveredRun;

  /// Banner copy emitted by the in-progress recovery helper at app
  /// start. Surfaced once on the first build of the Home tab. Covers
  /// both "Recovered a 2.3 km partial..." and the new
  /// "Discarded a 38 m partial recording..." case (Casual #3). Null
  /// when the recovery pass had nothing to say.
  final String? recoveryBannerMessage;

  const HomeScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.gearStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    required this.audioCues,
    required this.social,
    required this.raceController,
    required this.training,
    required this.heartRate,
    required this.treadmill,
    this.settingsSync,
    this.recoveredRun,
    this.recoveryBannerMessage,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // PageView page indices. The bottom nav exposes four destinations
  // (Home / Fitness / Social / You) plus a centre Log action; the Run page
  // has no nav destination but stays a keep-alive PageView page so an
  // in-progress recording survives navigating away (multi_modal.md §
  // Bottom nav). Fitness is the modality hub (All/Runs/Gym/Nutrition); the
  // former standalone History tab is absorbed into its All sub-tab, and
  // Settings folds into You.
  static const _pageHome = 0;
  static const _pageFitness = 1;
  // Run / Gym / Nutrition have no bottom-nav destination — they're the
  // dwell-in capture surfaces reached via the centre Log action, each a
  // keep-alive page so an in-progress session (a live recording, a
  // half-built workout, the day's food log) survives swiping to Home and
  // back. Run can't be anything else (a foreground-service GPS session
  // can't collapse into a modal); Gym + Nutrition match it so all three
  // Log actions behave the same way. These are DISTINCT from the Fitness
  // hub's review surfaces (which mount separate Gym/Nutrition instances).
  static const _pageRun = 2;
  static const _pageGym = 3;
  static const _pageFood = 4;
  static const _pageSocial = 5;
  static const _pageYou = 6;
  static const _initialIndex = _pageHome;

  /// Current page index. A `ValueNotifier` instead of a `setState` int so
  /// page changes during a swipe only rebuild the bottom bar — not the
  /// entire 5-page subtree. The PageView's children are built once in
  /// `initState` and never re-created.
  final _currentIndex = ValueNotifier<int>(_initialIndex);

  late final PageController _pageController =
      PageController(initialPage: _initialIndex);

  cm.Route? _preselectedRoute;

  /// Built once and cached, so each page change during a swipe reuses the
  /// same widget instances instead of recreating them and relying on
  /// Flutter's reconciliation step.
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _rebuildPages();
    pendingStartWorkout.addListener(_onPendingStartWorkout);
    // Surface the recovery banner from main.dart's in-progress
    // evaluation. Casual #3: this also fires on DISCARD ("Discarded a
    // 38 m partial recording...") — pre-fix that path was silent and
    // a casual user couldn't tell whether the app saw + dropped their
    // tap-Start-then-quit attempt or just lost the run entirely.
    final bannerMessage = widget.recoveryBannerMessage;
    if (bannerMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showTopBanner(
          context,
          bannerMessage,
          duration: const Duration(seconds: 6),
        );
      });
    }
    // Post-signup setup-wizard gate (mobile twin of web's
    // `/onboarding` redirect). A signed-in user whose
    // `user_profiles.onboarded_at` is still null is a fresh signup that
    // hasn't seen the wizard yet — push it once, over the dashboard, so
    // the same fields web collects get set. Skipped offline / signed out
    // (the fetch returns null and we never push). Fires after the first
    // frame so the dashboard is mounted underneath.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeShowSetupWizard();
    });
  }

  bool _setupWizardShown = false;

  Future<void> _maybeShowSetupWizard() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    if (_setupWizardShown) return;
    cm.UserProfileRow? profile;
    try {
      profile = await api.fetchMyProfile();
    } catch (e) {
      debugPrint('setup-wizard gate: fetchMyProfile failed: $e');
      return;
    }
    if (!mounted) return;
    // Only a fresh signup with a materialised row but no onboarded_at
    // stamp gets the wizard. A null profile (offline / RLS) is left alone
    // — better to skip than to block a signed-in user behind a wizard we
    // can't persist.
    if (profile == null || profile.onboardedAt != null) return;
    _setupWizardShown = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => SetupWizardScreen(
          apiClient: api,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
          initialDisplayName: profile!.displayName,
          initialPreferredUnit: profile.preferredUnit,
        ),
      ),
    );
  }

  /// Bring the user to the Run tab when something deeper in the nav
  /// stack (e.g. plan_detail's calendar → workout_detail → Start) signals
  /// that a structured workout should start. RunScreen handles the actual
  /// workout-load on its end via the same notifier.
  void _onPendingStartWorkout() {
    if (pendingStartWorkout.value == null) return;
    if (!mounted) return;
    if (_currentIndex.value != _pageRun) {
      _currentIndex.value = _pageRun;
      _pageController.jumpToPage(_pageRun);
    }
  }

  void _rebuildPages() {
    // Each page is wrapped in `_LazyKeepAliveTab`, which only constructs
    // its heavy child on the first `build` call. PageView lazily builds
    // its children (only the visible page + cacheExtent neighbours) so
    // tabs the user hasn't touched stay un-initialised — saving their
    // initState `_load()` network calls and listener registrations
    // until the user actually swipes there.
    _pages = [
      _LazyKeepAliveTab(
        builder: () => DashboardScreen(
          key: const PageStorageKey('dashboard'),
          apiClient: widget.apiClient,
          training: widget.training,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gymStore: widget.gymStore,
          foodStore: widget.foodStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => FitnessHubScreen(
          key: const PageStorageKey('fitness'),
          apiClient: widget.apiClient,
          social: widget.social,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gymStore: widget.gymStore,
          foodStore: widget.foodStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
          training: widget.training,
          onStartRun: _startRunWithRoute,
        ),
      ),
      _LazyKeepAliveTab(
        // rebuildKey ties the cached child to the preselected
        // route's id — when `_startRunWithRoute` updates
        // `_preselectedRoute`, the id flips, the cache invalidates,
        // and the next build calls the RunScreen builder with the
        // freshly-set `initialRoute`. Without this, a user who
        // tapped "Start Run" from a route detail jumped to the
        // Run page but the route stayed unselected.
        rebuildKey: _preselectedRoute?.id,
        builder: () => RunScreen(
          key: const PageStorageKey('run'),
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          audioCues: widget.audioCues,
          settingsSync: widget.settingsSync,
          social: widget.social,
          raceController: widget.raceController,
          training: widget.training,
          heartRate: widget.heartRate,
          treadmill: widget.treadmill,
          initialRoute: _preselectedRoute,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => GymScreen(
          key: const PageStorageKey('gym'),
          api: widget.apiClient,
          store: widget.gymStore,
          social: widget.social,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => NutritionScreen(
          key: const PageStorageKey('nutrition'),
          api: widget.apiClient,
          store: widget.foodStore,
          settingsSync: widget.settingsSync,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => SocialScreen(
          key: const PageStorageKey('social'),
          api: widget.apiClient ?? ApiClient(),
          social: widget.social,
          training: widget.training,
          routeStore: widget.routeStore,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => YouScreen(
          key: const PageStorageKey('you'),
          apiClient: widget.apiClient,
          preferences: widget.preferences,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          gearStore: widget.gearStore,
          heartRate: widget.heartRate,
          treadmill: widget.treadmill,
          settingsSync: widget.settingsSync,
        ),
      ),
    ];
  }

  @override
  void dispose() {
    pendingStartWorkout.removeListener(_onPendingStartWorkout);
    _pageController.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  void _startRunWithRoute(cm.Route route) {
    // The Run page takes a preselected route via constructor; changing it
    // means rebuilding that page. Cheap — only called from the Routes tab's
    // "start with this route" flow, not during a swipe.
    _preselectedRoute = route;
    setState(_rebuildPages);
    _currentIndex.value = _pageRun;
    _pageController.jumpToPage(_pageRun);
  }

  void _goToPage(int index) {
    if (index == _currentIndex.value) return;
    _currentIndex.value = index;
    // Jump instead of animate — sweeping across several pages would be slow
    // and distracting. Destinations, not a sequence.
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    _currentIndex.value = index;
  }

  // --- Centre Log button (multi_modal.md § Bottom nav) ---

  /// Tap on the centre Log button. When the user has opted to keep Run as
  /// the one-tap primary action, this starts a run directly; otherwise it
  /// opens the Log capture sheet.
  void _onLogTap() {
    if (widget.preferences.keepRunPrimary) {
      _performLogAction(LogAction.run);
    } else {
      _openLogSheet();
    }
  }

  /// Long-press on the centre Log button. In runner-primary mode this opens
  /// the full sheet (so gym / nutrition stay reachable); otherwise it
  /// repeats the last logged modality — preserving the one-gesture "start a
  /// run" muscle memory for a pure runner.
  void _onLogLongPress() {
    if (widget.preferences.keepRunPrimary) {
      _openLogSheet();
    } else {
      _performLogAction(
          logActionFromWire(widget.preferences.lastLogType) ?? LogAction.run);
    }
  }

  Future<void> _openLogSheet() async {
    final picked = await showLogSheet(
      context: context,
      recent: logActionFromWire(widget.preferences.lastLogType),
    );
    if (picked != null) _performLogAction(picked);
  }

  void _performLogAction(LogAction action) {
    widget.preferences.setLastLogType(action.wire);
    // Each Log action lands on that modality's dwell-in capture page (decisions
    // §63) — the same in-shell keep-alive page model the live recorder uses, so
    // all three behave identically: you arrive on a workspace you can operate in
    // for as long as the session lasts (record the run, build the workout over
    // several sets, log the day's meals) rather than a one-shot modal that
    // closes after a single entry. Each page surfaces its composer one tap away.
    switch (action) {
      case LogAction.run:
        _goToPage(_pageRun);
      case LogAction.lift:
        _goToPage(_pageGym);
      case LogAction.food:
        _goToPage(_pageFood);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // PageView replaces IndexedStack so the user can swipe left/right
      // between tabs. Each child is wrapped in `_KeepAlive` so the state
      // of a tab (scroll position, live run recorder, in-flight fetches)
      // survives being swiped off-screen — the same guarantee IndexedStack
      // gave us for free.
      //
      // BillingIssueBanner sits above the PageView so it surfaces on
      // every authed tab when a Pro user has a failed renewal payment
      // sitting in the store's grace period. Cleared automatically
      // when the revenuecat-webhook fires RENEWAL / EXPIRATION /
      // CANCELLATION. Mirrors web's root-layout banner; renders
      // nothing when the flag is null or the user is on the free
      // tier — zero footprint in the common case.
      body: Column(
        children: [
          BillingIssueBanner(apiClient: widget.apiClient),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              physics: const PageScrollPhysics(),
              children: _pages,
            ),
          ),
        ],
      ),
      // The raised centre "+" is the Log action (multi_modal.md § Bottom
      // nav). FloatingActionButton has no long-press, so the GestureDetector
      // wrapper claims that gesture while the button keeps the tap; the
      // Semantics label makes the action explicit for screen readers, and
      // the 56 dp FAB clears the >=48 dp target.
      floatingActionButton: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return GestureDetector(
            onLongPress: _onLogLongPress,
            child: Semantics(
              button: true,
              label: l10n.logA11yLabel,
              child: FloatingActionButton(
                onPressed: _onLogTap,
                tooltip: l10n.navLog,
                child: const Icon(Icons.add),
              ),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _currentIndex,
        builder: (context, index, _) {
          final l10n = AppLocalizations.of(context);
          return BottomAppBar(
            height: 64,
            padding: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BottomNavItem(
                  icon: Icons.dashboard,
                  label: l10n.navHome,
                  selected: index == _pageHome,
                  onTap: () => _goToPage(_pageHome),
                ),
                _BottomNavItem(
                  icon: Icons.fitness_center,
                  label: l10n.navFitness,
                  selected: index == _pageFitness,
                  onTap: () => _goToPage(_pageFitness),
                ),
                // Gap under the docked Log FAB.
                const SizedBox(width: 56),
                _BottomNavItem(
                  icon: Icons.public,
                  label: l10n.navSocial,
                  selected: index == _pageSocial,
                  onTap: () => _goToPage(_pageSocial),
                ),
                _BottomNavItem(
                  icon: Icons.person,
                  label: l10n.navYou,
                  selected: index == _pageYou,
                  onTap: () => _goToPage(_pageYou),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One destination in the [BottomAppBar] — icon over label, tinted when
/// selected. A real button for accessibility (role + selected state), with
/// a >=48 dp tap target.
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lazy + keep-alive tab wrapper. Combines two roles:
///
///  1. `AutomaticKeepAliveClientMixin` — preserves the child's State once
///     it has been built (the page survives swiping off-screen, which is
///     the contract we used to get from `IndexedStack`).
///  2. Lazy construction — the child widget itself (and its heavy
///     `initState` chain: network loads, listener registrations) is only
///     instantiated on the first `build` call. PageView's lazy delegate
///     means tabs the user hasn't visited stay un-built, which keeps
///     cold-start work scoped to the initial page.
class _LazyKeepAliveTab extends StatefulWidget {
  final Widget Function() builder;

  /// Bump this whenever an upstream input the builder closes over
  /// has meaningfully changed and the tab must re-mount its child.
  /// Without this, the cache below kept the very first build of
  /// the child alive across the lifetime of the tab — which meant
  /// `_startRunWithRoute` could set `_preselectedRoute` + rebuild
  /// the pages list, but RunScreen never saw the new `initialRoute`
  /// (the cached instance from the FIRST build was returned again).
  /// User-visible symptom: tapping "Start run" on a route's detail
  /// FAB jumped to the Run tab but the route wasn't selected.
  final Object? rebuildKey;

  const _LazyKeepAliveTab({required this.builder, this.rebuildKey});

  @override
  State<_LazyKeepAliveTab> createState() => _LazyKeepAliveTabState();
}

class _LazyKeepAliveTabState extends State<_LazyKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  Widget? _child;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant _LazyKeepAliveTab old) {
    super.didUpdateWidget(old);
    // Invalidate the cached child when the upstream rebuildKey
    // changes. The next `build` call below re-invokes the builder
    // (with the latest closed-over state). Tabs without a
    // rebuildKey keep the original "build once, keep alive
    // forever" semantics — only the tabs that need to react to
    // external state changes pay the rebuild cost.
    if (old.rebuildKey != widget.rebuildKey) {
      _child = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _child ??= widget.builder();
  }
}

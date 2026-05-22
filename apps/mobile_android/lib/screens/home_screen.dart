import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;

import '../audio_cues.dart';
import '../ble_heart_rate.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../main.dart' show pendingStartWorkout;
import '../preferences.dart';
import '../race_controller.dart';
import '../settings_sync.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../widgets/billing_issue_banner.dart';
import '../widgets/top_banner.dart';
import 'dashboard_screen.dart';
import 'runs_screen.dart';
import 'run_screen.dart';
import 'settings_screen.dart';
import 'social_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final SocialService social;
  final RaceController raceController;
  final TrainingService training;
  final BleHeartRate heartRate;
  final SettingsSyncService? settingsSync;
  final cm.Run? recoveredRun;

  const HomeScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
    required this.social,
    required this.raceController,
    required this.training,
    required this.heartRate,
    this.settingsSync,
    this.recoveredRun,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _initialIndex = 1;

  /// Current tab index. A `ValueNotifier` instead of a `setState` int so
  /// page changes during a swipe only rebuild the NavigationBar — not the
  /// entire 5-tab subtree. The PageView's children are built once in
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
    final recovered = widget.recoveredRun;
    if (recovered != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showTopBanner(
          context,
          'Recovered unfinished run — '
          '${UnitFormat.distance(recovered.distanceMetres, widget.preferences.unit)}, '
          '${recovered.duration.inMinutes} min',
          duration: const Duration(seconds: 6),
        );
      });
    }
  }

  /// Bring the user to the Run tab when something deeper in the nav
  /// stack (e.g. plan_detail's calendar → workout_detail → Start) signals
  /// that a structured workout should start. RunScreen handles the actual
  /// workout-load on its end via the same notifier.
  void _onPendingStartWorkout() {
    if (pendingStartWorkout.value == null) return;
    if (!mounted) return;
    if (_currentIndex.value != 1) {
      _currentIndex.value = 1;
      _pageController.jumpToPage(1);
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
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
      _LazyKeepAliveTab(
        // rebuildKey ties the cached child to the preselected
        // route's id — when `_startRunWithRoute` updates
        // `_preselectedRoute`, the id flips, the cache invalidates,
        // and the next build calls the RunScreen builder with the
        // freshly-set `initialRoute`. Without this, a user who
        // tapped "Start Run" from a route detail jumped to the
        // Run tab but the route stayed unselected.
        rebuildKey: _preselectedRoute?.id,
        builder: () => RunScreen(
          key: const PageStorageKey('run'),
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          audioCues: widget.audioCues,
          social: widget.social,
          raceController: widget.raceController,
          training: widget.training,
          heartRate: widget.heartRate,
          initialRoute: _preselectedRoute,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => RunsScreen(
          key: const PageStorageKey('runs'),
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
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
          preferences: widget.preferences,
          onStartRun: _startRunWithRoute,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => SettingsScreen(
          key: const PageStorageKey('settings'),
          apiClient: widget.apiClient,
          preferences: widget.preferences,
          runStore: widget.runStore,
          heartRate: widget.heartRate,
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
    // The Run tab takes a preselected route via constructor; changing it
    // means rebuilding that page. Cheap — only called from the Routes tab's
    // "start with this route" flow, not during a swipe.
    _preselectedRoute = route;
    setState(_rebuildPages);
    _currentIndex.value = 1;
    _pageController.jumpToPage(1);
  }

  void _onNavTapped(int index) {
    if (index == _currentIndex.value) return;
    _currentIndex.value = index;
    // Jump instead of animate — sweeping across three pages from Home to
    // Routes would be slow and distracting. Tabs are destinations, not a
    // sequence.
    _pageController.jumpToPage(index);
  }

  void _onPageChanged(int index) {
    _currentIndex.value = index;
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
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _currentIndex,
        builder: (context, index, _) => NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _onNavTapped,
          destinations: const [
            // Routes lives as a sub-tab of Social on mobile — bottom nav
            // can't carry six items without crowding the labels. The web
            // side keeps Routes as a sidebar peer; mobile compresses.
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.play_arrow), label: 'Run'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.public), label: 'Social'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
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

import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;

import '../audio_cues.dart';
import '../ble_heart_rate.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../race_controller.dart';
import '../settings_sync.dart';
import '../social_service.dart';
import '../training_service.dart';
import 'clubs_screen.dart';
import 'dashboard_screen.dart';
import 'runs_screen.dart';
import 'routes_screen.dart';
import 'run_screen.dart';
import 'settings_screen.dart';

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
        builder: () => RoutesScreen(
          key: const PageStorageKey('routes'),
          apiClient: widget.apiClient,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          onStartRun: _startRunWithRoute,
        ),
      ),
      _LazyKeepAliveTab(
        builder: () => ClubsScreen(
          key: const PageStorageKey('clubs'),
          social: widget.social,
          training: widget.training,
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
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const PageScrollPhysics(),
        children: _pages,
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _currentIndex,
        builder: (context, index, _) => NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _onNavTapped,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.play_arrow), label: 'Run'),
            NavigationDestination(icon: Icon(Icons.history), label: 'History'),
            NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
            NavigationDestination(icon: Icon(Icons.groups), label: 'Clubs'),
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
  const _LazyKeepAliveTab({required this.builder});

  @override
  State<_LazyKeepAliveTab> createState() => _LazyKeepAliveTabState();
}

class _LazyKeepAliveTabState extends State<_LazyKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  Widget? _child;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _child ??= widget.builder();
  }
}

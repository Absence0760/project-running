import 'package:flutter/material.dart';
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;

import '../audio_cues.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
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
  final TrainingService training;

  const HomeScreen({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
    required this.audioCues,
    required this.social,
    required this.training,
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
    _pages = [
      _KeepAlive(
        child: DashboardScreen(
          key: const PageStorageKey('dashboard'),
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
        ),
      ),
      _KeepAlive(
        child: RunScreen(
          key: const PageStorageKey('run'),
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          audioCues: widget.audioCues,
          social: widget.social,
          training: widget.training,
          initialRoute: _preselectedRoute,
        ),
      ),
      _KeepAlive(
        child: RunsScreen(
          key: const PageStorageKey('runs'),
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
        ),
      ),
      _KeepAlive(
        child: RoutesScreen(
          key: const PageStorageKey('routes'),
          apiClient: widget.apiClient,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          onStartRun: _startRunWithRoute,
        ),
      ),
      _KeepAlive(
        child: ClubsScreen(
          key: const PageStorageKey('clubs'),
          social: widget.social,
        ),
      ),
      _KeepAlive(
        child: SettingsScreen(
          key: const PageStorageKey('settings'),
          apiClient: widget.apiClient,
          preferences: widget.preferences,
          runStore: widget.runStore,
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
            NavigationDestination(icon: Icon(Icons.history), label: 'Runs'),
            NavigationDestination(icon: Icon(Icons.route), label: 'Routes'),
            NavigationDestination(icon: Icon(Icons.groups), label: 'Clubs'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

/// Wraps a child in `AutomaticKeepAliveClientMixin` so a `PageView` that
/// holds it doesn't dispose the state when the page scrolls off-screen.
/// This is the missing piece when converting an `IndexedStack`-based tab
/// host to a swipeable one — without it, swiping away from the recording
/// tab would kill the live recorder.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

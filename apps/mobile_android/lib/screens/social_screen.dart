import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../training_service.dart';
import 'clubs_screen.dart';
import 'feed_screen.dart';
import 'people_screen.dart';
import 'routes_screen.dart';

/// The Social tab — mirrors the web `/social` hub (decisions §54)
/// plus the Routes surface (folded onto mobile since the bottom nav
/// can't carry six tabs without crowding). Four sub-tabs:
///   - Feed: 14-day activity feed of public runs from people you follow.
///   - People: name search + suggested-from-clubs discovery.
///   - Clubs: browse public clubs + the user's own memberships.
///   - Routes: saved + bookmarked routes (mobile only — on web this is
///     a top-level sidebar item; on mobile it lives here so the
///     bottom-nav stays at five tabs).
///
/// Each sub-tab embeds its screen widget in `embedded: true` mode so
/// the screen returns just its body without its own Scaffold/AppBar/FAB.
/// SocialScreen hosts the chrome — a single AppBar with a TabBar at
/// the bottom, and a single FAB slot that takes whichever child FAB
/// is appropriate for the active tab (Clubs hoists "Create club",
/// Routes hoists the dual "Build" + "Import" column).
class SocialScreen extends StatefulWidget {
  final ApiClient api;
  final SocialService social;
  final TrainingService training;
  final LocalRouteStore routeStore;
  final Preferences preferences;
  /// Optional preselect-this-route handoff used by the Run tab when a
  /// user picks "Start with this route" on a detail screen. Plumbed
  /// through to the embedded `RoutesScreen`.
  final void Function(cm.Route route)? onStartRun;
  /// Sub-tab to open on first mount. 0 = Feed, 1 = People, 2 = Clubs,
  /// 3 = Routes. Defaults to Feed (0) so a tap on the bottom-nav lands
  /// on fresh follower activity — that's the highest-value default for
  /// most sessions; users heading to a club still get there in one tap.
  final int initialTab;

  const SocialScreen({
    super.key,
    required this.api,
    required this.social,
    required this.training,
    required this.routeStore,
    required this.preferences,
    this.onStartRun,
    this.initialTab = 0,
  });

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  final _clubsKey = GlobalKey<ClubsScreenState>();
  final _routesKey = GlobalKey<RoutesScreenState>();

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
    _controller.addListener(() {
      // Repaint so the FAB visibility tracks the active tab.
      if (mounted && !_controller.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // No title — the bottom-nav already labels the tab "Social",
        // and the tab strip itself names each sub-surface. Keeping
        // the AppBar so the TabBar sits at the canonical Material
        // spot (under the system status bar).
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _controller,
          tabs: [
            Tab(text: l10n.socialTabFeed, icon: const Icon(Icons.dynamic_feed)),
            Tab(
                text: l10n.socialTabPeople,
                icon: const Icon(Icons.person_search)),
            Tab(text: l10n.socialTabClubs, icon: const Icon(Icons.groups)),
            Tab(text: l10n.socialTabRoutes, icon: const Icon(Icons.route)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          FeedScreen(api: widget.api, embedded: true),
          PeopleScreen(api: widget.api, embedded: true),
          ClubsScreen(
            key: _clubsKey,
            social: widget.social,
            training: widget.training,
            apiClient: widget.api,
            routeStore: widget.routeStore,
            embedded: true,
          ),
          RoutesScreen(
            key: _routesKey,
            apiClient: widget.api,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            onStartRun: widget.onStartRun,
            social: widget.social,
            embedded: true,
          ),
        ],
      ),
      floatingActionButton: _activeFab(),
    );
  }

  /// FAB hoisting: each embedded sub-tab exposes its own FAB widget(s)
  /// via a `buildXFab(...)` method on its public State. We render
  /// whichever matches the active tab — and nothing for tabs that
  /// don't have a FAB.
  Widget? _activeFab() {
    switch (_controller.index) {
      case 2:
        return Builder(builder: (ctx) {
          final state = _clubsKey.currentState;
          return state?.buildCreateClubFab(ctx) ?? const SizedBox.shrink();
        });
      case 3:
        return Builder(builder: (ctx) {
          final state = _routesKey.currentState;
          return state?.buildRouteFabs(ctx) ?? const SizedBox.shrink();
        });
      default:
        return null;
    }
  }
}

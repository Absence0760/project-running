import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../social_service.dart';
import '../training_service.dart';
import 'challenges_screen.dart';
import 'clubs_screen.dart';
import 'discover_screen.dart';
import 'feed_screen.dart';
import 'people_screen.dart';

/// The Social tab — mirrors the web `/social` hub (decisions §54). Four
/// sub-tabs:
///   - Feed: 14-day activity feed of public runs from people you follow.
///   - People: name search + suggested-from-clubs discovery.
///   - Clubs: browse public clubs + the user's own memberships.
///   - Discover: cross-club activity search over `search_public_events`
///     (public clubs only; category/cadence/weekday/time/price filters,
///     decisions §147).
///
/// Routes used to live here as a fourth sub-tab; the Fitness-hub redesign
/// relocated it to Fitness → Runs (a run-modality surface, not a
/// people/feed one). Each sub-tab embeds its screen widget in
/// `embedded: true` mode so the screen returns just its body without its
/// own Scaffold/AppBar/FAB. SocialScreen hosts the chrome — a single
/// AppBar with a TabBar at the bottom, and a single FAB slot that takes
/// whichever child FAB is appropriate for the active tab (Clubs hoists
/// "Create club").
class SocialScreen extends StatefulWidget {
  final ApiClient api;
  final SocialService social;
  final TrainingService training;
  /// Still required — `ClubsScreen` takes it to surface club-owned routes.
  final LocalRouteStore routeStore;
  /// Sub-tab to open on first mount. 0 = Feed, 1 = People, 2 = Clubs,
  /// 3 = Discover. Defaults to Feed (0) so a tap on the bottom-nav lands
  /// on fresh follower activity — that's the highest-value default for
  /// most sessions; users heading to a club still get there in one tap.
  final int initialTab;

  const SocialScreen({
    super.key,
    required this.api,
    required this.social,
    required this.training,
    required this.routeStore,
    this.initialTab = 0,
  });

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  final _clubsKey = GlobalKey<ClubsScreenState>();

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
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
            Tab(
                text: l10n.socialTabDiscover,
                icon: const Icon(Icons.event_available)),
            Tab(
                text: l10n.challengesTitle,
                icon: const Icon(Icons.emoji_events_outlined)),
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
          DiscoverScreen(
            api: widget.api,
            social: widget.social,
            embedded: true,
          ),
          ChallengesScreen(
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
          if (state == null) {
            // The ClubsScreen State binds to the GlobalKey during this same
            // build pass (the page is mounting in the TabBarView), so its
            // currentState is null on the first frame the Clubs tab is
            // active. Without a follow-up rebuild the hoisted FAB would
            // stay absent forever — schedule one once the element is laid
            // out so the FAB resolves on the next frame.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _controller.index == 2) setState(() {});
            });
            return const SizedBox.shrink();
          }
          return state.buildCreateClubFab(ctx);
        });
      default:
        return null;
    }
  }
}

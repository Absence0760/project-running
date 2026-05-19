import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../social_service.dart';
import '../training_service.dart';
import 'clubs_screen.dart';
import 'feed_screen.dart';
import 'people_screen.dart';

/// The Social tab — mirrors the web `/social` hub (decisions §54).
/// Three sub-tabs:
///   - Feed: 14-day activity feed of public runs from people you follow.
///   - People: name search + suggested-from-clubs discovery.
///   - Clubs: browse public clubs + the user's own memberships.
///
/// Each sub-tab embeds the existing screen widget in `embedded: true`
/// mode so the screen returns just its body without its own
/// Scaffold/AppBar/FAB. SocialScreen hosts the chrome — a single
/// AppBar with a TabBar at the bottom, and a single FAB that only
/// surfaces on the Clubs tab (matching the web Hub's behaviour where
/// the "New club" CTA only renders inside the Clubs view).
///
/// Reachable as the 5th bottom-nav tab (renamed from "Clubs"). The
/// standalone routes to FeedScreen / PeopleScreen / ClubsScreen
/// (each used from various AppBar action buttons) still work via
/// the legacy `embedded: false` path; SocialScreen is the canonical
/// surface.
class SocialScreen extends StatefulWidget {
  final ApiClient api;
  final SocialService social;
  final TrainingService training;
  /// Sub-tab to open on first mount. 0 = Feed, 1 = People, 2 = Clubs.
  /// Matches the web `?tab=feed|people|clubs` deep-link contract.
  /// Defaults to Clubs (2) — returning users mostly land here from
  /// the bottom nav to check on a club they've joined.
  final int initialTab;

  const SocialScreen({
    super.key,
    required this.api,
    required this.social,
    required this.training,
    this.initialTab = 2,
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
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
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
    return Scaffold(
      appBar: AppBar(
        // No title — the bottom-nav already labels the tab "Social",
        // and the tab strip itself names each sub-surface. Keeping
        // the AppBar so the TabBar sits at the canonical Material
        // spot (under the system status bar).
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: 'Feed', icon: Icon(Icons.dynamic_feed)),
            Tab(text: 'People', icon: Icon(Icons.person_search)),
            Tab(text: 'Clubs', icon: Icon(Icons.groups)),
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
            embedded: true,
          ),
        ],
      ),
      floatingActionButton: _controller.index == 2
          ? Builder(
              builder: (ctx) {
                final state = _clubsKey.currentState;
                return state?.buildCreateClubFab(ctx) ?? const SizedBox.shrink();
              },
            )
          : null,
    );
  }
}

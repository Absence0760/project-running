import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../social_service.dart';
import '../training_service.dart';
import 'gym_screen.dart';
import 'nutrition_screen.dart';
import 'plans_screen.dart';
import 'routes_screen.dart';
import 'runs_screen.dart';

/// The Fitness modality hub — a review/plan destination distinct from the
/// keep-alive capture pages reached via the centre Log action. A top sub-tab
/// strip switches between four surfaces:
///   - All: the unified cross-modal activity timeline (the former standalone
///     History tab, absorbed here) — `RunsScreen` mounted WITH the gym + food
///     stores, with its own kind chips suppressed since the hub's TabBar owns
///     that axis.
///   - Runs: the dedicated offline-first run list (`RunsScreen` WITHOUT a gym
///     store) plus a Routes entry, relocated here out of Social.
///   - Gym: `GymScreen`.
///   - Nutrition: `NutritionScreen`.
///
/// Each sub-tab body owns its own Scaffold/AppBar/composer; the hub provides
/// only the TabBar chrome (mirrors `social_screen.dart`'s host shape). The
/// self-hiding contract holds — empty Gym/Nutrition tabs render their own
/// onboarding empty state, never a forced card.
class FitnessHubScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final SocialService? social;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;
  final TrainingService training;

  /// Preselect-this-route handoff used by the Runs → Routes surface when a
  /// user picks "Start with this route"; plumbed up to the home shell so the
  /// run starts on the keep-alive recorder page.
  final void Function(cm.Route route)? onStartRun;

  /// Sub-tab to open on first mount. 0 = All, 1 = Runs, 2 = Gym, 3 = Nutrition.
  final int initialTab;

  const FitnessHubScreen({
    super.key,
    this.apiClient,
    this.social,
    required this.runStore,
    required this.routeStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    required this.training,
    this.settingsSync,
    this.onStartRun,
    this.initialTab = 0,
  });

  @override
  State<FitnessHubScreen> createState() => _FitnessHubScreenState();
}

class _FitnessHubScreenState extends State<FitnessHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openRoutes() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RoutesScreen(
        apiClient: widget.apiClient,
        routeStore: widget.routeStore,
        runStore: widget.runStore,
        preferences: widget.preferences,
        onStartRun: widget.onStartRun,
        social: widget.social,
      ),
    ));
  }

  void _openPlans() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlansScreen(
        training: widget.training,
        apiClient: widget.apiClient,
        runStore: widget.runStore,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _controller,
          tabs: [
            Tab(text: l10n.fitnessTabAll),
            Tab(text: l10n.fitnessTabRuns),
            Tab(text: l10n.fitnessTabGym),
            Tab(text: l10n.fitnessTabNutrition),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          RunsScreen(
            key: const PageStorageKey('fitness-all'),
            apiClient: widget.apiClient,
            runStore: widget.runStore,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            gymStore: widget.gymStore,
            foodStore: widget.foodStore,
            showKindChips: false,
          ),
          RunsScreen(
            key: const PageStorageKey('fitness-runs'),
            apiClient: widget.apiClient,
            runStore: widget.runStore,
            routeStore: widget.routeStore,
            preferences: widget.preferences,
            settingsSync: widget.settingsSync,
            onOpenRoutes: _openRoutes,
            onOpenPlans: _openPlans,
            showSyncActions: false,
            titleText: l10n.fitnessTabRuns,
          ),
          GymScreen(
            key: const PageStorageKey('fitness-gym'),
            api: widget.apiClient,
            store: widget.gymStore,
            social: widget.social,
          ),
          NutritionScreen(
            key: const PageStorageKey('fitness-nutrition'),
            api: widget.apiClient,
            store: widget.foodStore,
            settingsSync: widget.settingsSync,
          ),
        ],
      ),
    );
  }
}

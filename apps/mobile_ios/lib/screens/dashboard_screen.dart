import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../goals.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../local_gym_store.dart';
import '../lift_load.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../nutrition_targets.dart' show NutritionTargets;
import '../nutrition_totals.dart' show sumMacros;
import '../preferences.dart';
import '../run_stats.dart';
import '../settings_sync.dart';
import '../streaks.dart';
import '../training_load.dart';
import '../training_service.dart';
import '../widgets/fitness_card.dart';
import '../widgets/gym_summary_card.dart';
import '../widgets/notification_bell.dart';
import '../run_intensity.dart';
import '../widgets/intensity_card.dart';
import '../widgets/mileage_trend_card.dart';
import '../widgets/nutrition_rings_card.dart';
import '../widgets/readiness_card.dart';
import '../widgets/goal_editor_sheet.dart';
import '../widgets/todays_workout_card.dart';
import '../widgets/training_load_chart.dart';
import 'coach_screen.dart';
import 'feed_screen.dart';
import 'gym_screen.dart';
import 'import_screen.dart';
import 'nutrition_screen.dart';
import 'period_summary_screen.dart';
import 'plan_detail_screen.dart';
import 'profile_screen.dart';
import 'recap_screen.dart';

const _kCardPadding = EdgeInsets.all(20);
const _kSectionGap = SizedBox(height: 24);

/// Dashboard with goals, weekly/monthly stats, and personal bests.
class DashboardScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final TrainingService? training;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final SettingsSyncService? settingsSync;

  const DashboardScreen({
    super.key,
    this.apiClient,
    this.training,
    required this.runStore,
    required this.routeStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    this.settingsSync,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Memoised fastest-5k window per run id. Rescanning a 200-run history
  /// with several thousand waypoints each on every rebuild (and the
  /// dashboard rebuilds every time a listener fires) is the hottest loop
  /// in the app — this cache flattens it to O(1) on subsequent builds.
  /// Invalidated wholesale when the run store changes.
  final Map<String, Map<double, Duration?>> _bestEffortCache = {};

  /// Active training plan + today's workout, used to render the
  /// `TodaysWorkoutCard` at the top of the dashboard. Null when
  /// there's no active plan, no scheduled workout today, or the
  /// service hasn't returned yet. Lazy fetch on mount; refetched
  /// when the TrainingService notifies (e.g. user marks a workout
  /// done, switches plans).
  ActivePlanOverview? _planOverview;

  /// Daily nutrition targets, resolved once on mount, so the Home nutrition
  /// rings can show fill vs target. Null until resolved / when body metrics
  /// are absent (the rings then render unfilled — anti-clutter).
  NutritionTargets? _nutritionTargets;

  @override
  void initState() {
    super.initState();
    widget.runStore.addListener(_onRunStoreChanged);
    widget.preferences.addListener(_onChange);
    widget.gymStore.addListener(_onChange);
    widget.foodStore.addListener(_onChange);
    widget.training?.addListener(_refreshPlanOverview);
    _refreshPlanOverview();
    _hydrateModalities();
  }

  @override
  void dispose() {
    widget.runStore.removeListener(_onRunStoreChanged);
    widget.preferences.removeListener(_onChange);
    widget.gymStore.removeListener(_onChange);
    widget.foodStore.removeListener(_onChange);
    widget.training?.removeListener(_refreshPlanOverview);
    super.dispose();
  }

  void _onRunStoreChanged() {
    _bestEffortCache.clear();
    if (mounted) setState(() {});
  }

  /// Best-effort hydrate of the gym + food caches (so today's logged
  /// modalities surface on Home even on a fresh launch, before the user
  /// visits the Gym / Nutrition screens) plus the nutrition target. Each
  /// hop is wrapped independently (layered resilience): a gym fetch failure
  /// must not block the food fetch, and neither can break the dashboard.
  Future<void> _hydrateModalities() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final fresh = await api.fetchGymWorkoutsWithSets(limit: 100);
      await widget.gymStore.replaceFromServer(fresh);
    } catch (e) {
      debugPrint('dashboard gym hydrate failed: $e');
    }
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(const Duration(days: 6));
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final fresh = await api.fetchFoodLog(from: weekStart, to: tomorrow);
      await widget.foodStore
          .replaceFromServer([for (final r in fresh) r.toJson()]);
    } catch (e) {
      debugPrint('dashboard food hydrate failed: $e');
    }
    try {
      final t = await loadNutritionTargets(api, widget.settingsSync?.service);
      if (mounted) setState(() => _nutritionTargets = t);
    } catch (e) {
      debugPrint('dashboard nutrition targets failed: $e');
    }
  }

  /// Today's most-recent gym workout, or null when none was logged today.
  StoredGymWorkout? get _todaysLift {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    for (final w in widget.gymStore.workouts) {
      final at = w.startedAt?.toLocal();
      if (at != null && !at.isBefore(start)) return w;
    }
    return null;
  }

  /// Today's logged food entries (for the nutrition rings), oldest first.
  List<FoodEntry> get _todaysFood {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day + 1);
    return [
      for (final r in widget.foodStore.entriesForRange(start, end))
        FoodEntry.fromRow(r),
    ];
  }

  void _openGym() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          GymScreen(api: widget.apiClient, store: widget.gymStore),
    ));
  }

  void _openNutrition() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NutritionScreen(
        api: widget.apiClient,
        store: widget.foodStore,
        settingsSync: widget.settingsSync,
      ),
    ));
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshPlanOverview() async {
    final svc = widget.training;
    if (svc == null) return;
    try {
      final overview = await svc.fetchActiveOverview();
      if (mounted) setState(() => _planOverview = overview);
    } catch (e) {
      // Non-critical — same logging stance as run_screen's overview
      // fetch. The card simply doesn't render; the rest of the
      // dashboard keeps working.
      debugPrint('dashboard plan-overview fetch failed: $e');
    }
  }

  void _openImport() {
    // From the welcome empty state. Routes into the existing
    // ImportScreen which handles Strava ZIP / Health Connect /
    // GPX-folder paths. The user might not be signed in (apiClient
    // null) — ImportScreen handles that internally by greying out
    // the cloud-push tile and still allowing local import.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportScreen(
          apiClient: widget.apiClient,
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  void _openTodayWorkout() {
    final svc = widget.training;
    final p = _planOverview;
    if (svc == null || p == null) return;
    // Dashboard's role is overview, not start-a-run. Tap routes into
    // plan_detail so the runner can see the full week + drill into
    // the workout. The Run tab already has the "start now" dialog
    // for runners who tap from there.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailScreen(
          training: svc,
          planId: p.plan.id,
        ),
      ),
    );
  }

  /// audit/accessibility — WCAG 4.1.3 (Status Messages). The goal grid
  /// updates via `setState` without moving focus, so a TalkBack user
  /// gets no feedback that a goal was created / removed.
  /// `SemanticsService.announce` pushes a one-shot live-region message
  /// (mirrors `run_screen._announceA11yState`). Best-effort.
  void _announceA11yState(String message) {
    try {
      SemanticsService.announce(message, TextDirection.ltr);
    } catch (e) {
      debugPrint('SemanticsService.announce failed: $e');
    }
  }

  Future<void> _newGoal() async {
    final msg = await showGoalEditorSheet(
      context,
      preferences: widget.preferences,
      settingsSync: widget.settingsSync,
    );
    if (msg != null) _announceA11yState(msg);
  }

  Future<void> _editGoal(RunGoal goal) async {
    final msg = await showGoalEditorSheet(
      context,
      preferences: widget.preferences,
      settingsSync: widget.settingsSync,
      existing: goal,
    );
    if (msg != null) _announceA11yState(msg);
  }

  String get _weekStartDay =>
      widget.settingsSync?.service?.effective<String>(SettingsKeys.weekStartDay) ??
      'monday';

  // Shared HR prefs for every training-load surface on this page so the
  // fitness card, readiness card, and chart all score on the same model.
  HrPrefs _hrPrefs() => HrPrefs(
        restingHrBpm: widget.settingsSync?.service
            ?.effective<num>(SettingsKeys.restingHrBpm),
        maxHrBpm: widget.settingsSync?.service
            ?.effective<num>(SettingsKeys.maxHrBpm),
      );

  /// Logged gym sessions reduced to the load-model input. Empty for a pure
  /// runner, so the curve is the unchanged run-only series; the gym store is
  /// hydrated on mount regardless of flag (mobile ships gym ungated, §63), so
  /// any logged lift feeds the same CTL/ATL/TSB trio runs do (multi_modal.md
  /// Tier-1 lift→load).
  List<LiftForLoad> _liftsForLoad() {
    final flat = <SetWithWorkoutDate>[];
    for (final w in widget.gymStore.workouts) {
      if (w.isTombstone) continue;
      final at = w.startedAt;
      if (at == null) continue;
      final iso = at.toUtc().toIso8601String();
      for (final s in w.sets) {
        flat.add(SetWithWorkoutDate(
          workoutId: w.id,
          startedAt: iso,
          reps: s['reps'] as num?,
          weightKg: s['weight_kg'] as num?,
          rpe: s['rpe'] as num?,
        ));
      }
    }
    return liftsFromSetHistory(flat);
  }

  Widget _buildTrainingLoadChart(List<Run> runs, DateTime now) {
    final hrPrefs = _hrPrefs();
    final lifts = _liftsForLoad();
    final series = computeTrainingLoadSeries(runs,
        prefs: hrPrefs, endDate: now, lifts: lifts);
    return TrainingLoadChart(
      points: series,
      hasHr: hasTrimpSignal(runs, hrPrefs),
      includesLifts: series.any((p) => p.liftStress > 0),
    );
  }

  void _openPeriodSummary(PeriodType period, [DateTime? anchor]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodSummaryScreen(
          initialPeriod: period,
          initialAnchor: anchor ?? DateTime.now(),
          runStore: widget.runStore,
          routeStore: widget.routeStore,
          preferences: widget.preferences,
          settingsSync: widget.settingsSync,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unit = widget.preferences.unit;
    final runs = widget.runStore.runs;
    final goals = widget.preferences.goals;

    final now = DateTime.now();
    final weekStart = weekStartLocal(now, weekStartDay: _weekStartDay);
    final monthStart = DateTime(now.year, now.month, 1);

    // One pass over the runs list collects everything every card needs —
    // week totals, month totals, all-time totals, and the PB candidates.
    // Replaces four separate `.where().fold()` chains. Matters at 10k+ runs.
    var weekRunCount = 0;
    var weekDistance = 0.0;
    var weekVert = 0.0;
    var monthRunCount = 0;
    var monthDistance = 0.0;
    var monthVert = 0.0;
    var allDistance = 0.0;
    var allVert = 0.0;
    Run? longest;
    const pbDistances = <String, double>{
      '5 km': 5000,
      '10 km': 10000,
      'Half Marathon': 21097,
      'Marathon': 42195,
    };
    final bestEfforts = <String, Duration>{};
    for (final r in runs) {
      allDistance += r.distanceMetres;
      final vert = _vertOf(r);
      allVert += vert;
      if (!r.startedAt.isBefore(weekStart)) {
        weekRunCount++;
        weekDistance += r.distanceMetres;
        weekVert += vert;
      }
      if (!r.startedAt.isBefore(monthStart)) {
        monthRunCount++;
        monthDistance += r.distanceMetres;
        monthVert += vert;
      }
      if (!_isRunActivity(r)) continue;
      if (longest == null || r.distanceMetres > longest.distanceMetres) {
        longest = r;
      }
      final runCache = _bestEffortCache.putIfAbsent(r.id, () => {});
      for (final e in pbDistances.entries) {
        if (r.distanceMetres < e.value) continue;
        final cached =
            runCache.putIfAbsent(e.value, () => fastestWindowOf(r.track, e.value));
        if (cached != null &&
            (!bestEfforts.containsKey(e.key) || cached < bestEfforts[e.key]!)) {
          bestEfforts[e.key] = cached;
        }
      }
    }
    final hasAnyPb = longest != null || bestEfforts.isNotEmpty;

    final api = widget.apiClient;
    final viewerId = api?.userId;

    // Inline action toolbar — replaces the previous AppBar so the
    // dashboard's content can sit flush with the top inset. Empty
    // when there's no signed-in api (the welcome state takes over).
    final actions = <Widget>[
      if (api != null) ...[
        if (widget.training != null)
          IconButton(
            tooltip: l10n.dashboardCoachTooltip,
            icon: const Icon(Icons.psychology_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CoachScreen(
                  api: api,
                  training: widget.training!,
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: l10n.dashboardFeedTooltip,
          icon: const Icon(Icons.dynamic_feed_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FeedScreen(api: api)),
          ),
        ),
        IconButton(
          tooltip: l10n.dashboardRecapTooltip,
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecapScreen(
                runStore: widget.runStore,
                preferences: widget.preferences,
              ),
            ),
          ),
        ),
        if (viewerId != null) NotificationBell(api: api),
        if (viewerId != null)
          IconButton(
            tooltip: l10n.dashboardProfileTooltip,
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(api: api, userId: viewerId),
              ),
            ),
          ),
      ],
    ];
    final actionToolbar = actions.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          );

    return Scaffold(
      // No AppBar — the bottom-nav already labels this tab "Home" and
      // the action buttons (Coach / Feed / Profile) hoist inline at
      // the top of the body. SafeArea keeps the first content row
      // clear of the system status bar (the AppBar was providing
      // that inset implicitly before).
      body: SafeArea(
        bottom: false,
        child: runs.isEmpty && goals.isEmpty
          ? Column(
              children: [
                if (actionToolbar != null) actionToolbar,
                Expanded(
                  child: _WelcomeEmpty(
                    theme: theme,
                    onAddGoal: _newGoal,
                    onImport: _openImport,
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (actionToolbar != null) actionToolbar,
                // Active-plan hero: surface the day's structured
                // workout above goals so a plan-runner sees what's
                // next before scrolling. Hidden when no active plan
                // or no workout today.
                if (_planOverview?.todayWorkout != null) ...[
                  TodaysWorkoutCard(
                    overview: _planOverview!,
                    onTap: _openTodayWorkout,
                  ),
                  _kSectionGap,
                ],
                // Today's logged non-run modalities (gym + nutrition).
                // Self-hiding: each card only renders when that modality was
                // logged today, so a pure runner sees nothing new here
                // (multi_modal.md § Home, anti-clutter checklist).
                ..._todayModalitySection(),
                _goalsSection(theme, unit, runs, goals, now),
                _kSectionGap,
                // Compact 3-column stat strip — replaced the previous
                // stacked "This Week" / "This Month" / "All Time"
                // cards (~480 px each + section headers). Same data,
                // same tap-through into PeriodSummary for week / month;
                // all-time has no period summary so it isn't tappable.
                Row(
                  children: [
                    Expanded(
                      child: _PeriodStatCard(
                        label: l10n.dashboardPeriodWeek,
                        distanceMetres: weekDistance,
                        runCount: weekRunCount,
                        vertMetres: weekVert,
                        unit: unit,
                        onTap: () => _openPeriodSummary(PeriodType.week),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PeriodStatCard(
                        label: l10n.dashboardPeriodMonth,
                        distanceMetres: monthDistance,
                        runCount: monthRunCount,
                        vertMetres: monthVert,
                        unit: unit,
                        onTap: () => _openPeriodSummary(PeriodType.month),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PeriodStatCard(
                        label: l10n.dashboardPeriodAllTime,
                        distanceMetres: allDistance,
                        runCount: runs.length,
                        vertMetres: allVert,
                        unit: unit,
                        onTap: () => _openPeriodSummary(PeriodType.all),
                      ),
                    ),
                  ],
                ),
                _kSectionGap,
                _SectionHeader(l10n.dashboardSectionStreak),
                Card(
                  child: Padding(
                    padding: _kCardPadding,
                    child: _StreakRow(runs: runs),
                  ),
                ),
                _kSectionGap,
                MileageTrendCard(runs: runs, unit: unit, now: now),
                _kSectionGap,
                _SectionHeader(l10n.dashboardSectionLast20Weeks),
                Card(
                  child: Padding(
                    padding: _kCardPadding,
                    child: _RunHeatmap(
                      runs: runs,
                      weeks: 20,
                      onWeekTap: (anchor) =>
                          _openPeriodSummary(PeriodType.week, anchor),
                    ),
                  ),
                ),
                _kSectionGap,
                if (hasAnyPb) ...[
                  _SectionHeader(l10n.dashboardSectionPersonalBests),
                  Card(
                    child: Padding(
                      padding: _kCardPadding,
                      child: Column(
                        children: [
                          if (longest != null)
                            _PbRow(
                              icon: Icons.straighten,
                              label: l10n.dashboardLongestRun,
                              value: UnitFormat.distance(
                                  longest.distanceMetres, unit),
                            ),
                          for (final e in bestEfforts.entries) ...[
                            const SizedBox(height: 12),
                            _PbRow(
                              icon: Icons.emoji_events,
                              label: l10n.dashboardFastestDistance(
                                  bestEffortDistanceLabel(l10n, e.key)),
                              value: _formatDuration(e.value),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _kSectionGap,
                ],
                FitnessCard(runs: runs, now: now, hrPrefs: _hrPrefs()),
                ReadinessCard(runs: runs, now: now, hrPrefs: _hrPrefs()),
                IntensityCard(
                  runs: runs,
                  hrZones: parseHrZones(widget.settingsSync?.service
                      ?.effective<Map>(SettingsKeys.hrZones)),
                  now: now,
                ),
                _buildTrainingLoadChart(runs, now),
              ],
            ),
      ),
    );
  }

  /// The "today's logged modalities" block — gym + nutrition cards, each
  /// self-hiding when that modality has no data today. Renders the two
  /// 2-up on phones wide enough (multi_modal.md § Home density rules) when
  /// both are present, full-width otherwise. Empty list when neither logged.
  List<Widget> _todayModalitySection() {
    final lift = _todaysLift;
    final food = _todaysFood;
    final hasFood = food.isNotEmpty;
    if (lift == null && !hasFood) return const [];

    final gymCard = lift == null
        ? null
        : GymSummaryCard(workout: lift, onTap: _openGym);
    final nutritionCard = !hasFood
        ? null
        : NutritionRingsCard(
            consumed: sumMacros(food),
            targets: _nutritionTargets,
            onTap: _openNutrition,
          );

    final wideEnough = MediaQuery.of(context).size.width >= 360;
    final Widget body;
    if (gymCard != null && nutritionCard != null && wideEnough) {
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: nutritionCard),
            const SizedBox(width: 8),
            Expanded(child: gymCard),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          if (nutritionCard != null) nutritionCard,
          if (nutritionCard != null && gymCard != null)
            const SizedBox(height: 8),
          if (gymCard != null) gymCard,
        ],
      );
    }
    return [body, _kSectionGap];
  }

  Widget _goalsSection(
    ThemeData theme,
    DistanceUnit unit,
    List<Run> runs,
    List<RunGoal> goals,
    DateTime now,
  ) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          l10n.dashboardGoals,
          trailing: goals.isNotEmpty
              ? TextButton.icon(
                  onPressed: _newGoal,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.dashboardAdd),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : null,
        ),
        if (goals.isEmpty)
          _EmptyGoalsCta(onAdd: _newGoal)
        else
          for (final goal in goals)
            _GoalCard(
              goal: goal,
              progress:
                  evaluateGoal(goal, runs, now, weekStartDay: _weekStartDay),
              unit: unit,
              onTap: () => _editGoal(goal),
            ),
      ],
    );
  }

  /// Personal-best cards are running-only. Cycles, walks, and hikes have
  /// their own pace/distance scales and would otherwise starve the run PBs
  /// (a 40 km ride as "longest run", a brisk walk as "fastest pace"). Legacy
  /// runs with no `activity_type` in metadata default to run.
  static bool _isRunActivity(Run r) {
    final raw = r.metadata?['activity_type'] as String?;
    return raw == null || raw == 'run';
  }

  /// Positive-only elevation gain (metres) for the period-stat
  /// aggregates. Mirrors web's `metadata.elevation_m` read on
  /// `/dashboard/+page.svelte`. Same canonical key the recap helper
  /// already uses (`lib/recap.dart#_elevationOf`).
  static double _vertOf(Run r) {
    final raw = r.metadata?['elevation_m'];
    if (raw is num) {
      final v = raw.toDouble();
      return v > 0 ? v : 0;
    }
    return 0;
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

class _WelcomeEmpty extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onAddGoal;
  final VoidCallback onImport;
  const _WelcomeEmpty({
    required this.theme,
    required this.onAddGoal,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_run,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(l10n.dashboardWelcomeTitle,
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              l10n.dashboardWelcomeBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            // Two side-by-side actions — primary "Set a goal" + the
            // discoverability handle to bulk-import a Strava / Garmin /
            // Health Connect history (the empty-state used to leave
            // import buried under Settings).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onAddGoal,
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l10n.dashboardSetGoal),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(l10n.dashboardImportRuns),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGoalsCta extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyGoalsCta({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // audit/accessibility (2026-05-25) High — WCAG 4.1.2. Tappable
    // `InkWell` carries no role for TalkBack; without Semantics it
    // reads as a generic tappable region. The label summarises the
    // CTA so a screen-reader user understands what activates.
    return Card(
      child: Semantics(
        button: true,
        label: l10n.dashboardSetWeeklyGoalA11y,
        child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primaryContainer,
                ),
                child: Icon(Icons.flag_outlined,
                    color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.dashboardSetFirstGoal,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      l10n.dashboardSetFirstGoalBody,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final RunGoal goal;
  final GoalProgress progress;
  final DistanceUnit unit;
  final VoidCallback onTap;
  const _GoalCard({
    required this.goal,
    required this.progress,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final completeColor = theme.brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade600;
    final accent =
        progress.complete ? completeColor : theme.colorScheme.primary;
    final periodLabel = goal.period == GoalPeriod.week
        ? l10n.dashboardGoalWeekly
        : l10n.dashboardGoalMonthly;
    final customTitle = goal.title;

    // Look up per-kind progress so the card can render every kind in order,
    // with unset targets shown as muted "-" rows. Keeps the layout stable
    // regardless of which targets the user has configured.
    final byKind = <GoalTargetKind, TargetProgress>{
      for (final t in progress.targets) t.kind: t,
    };

    final a11yLabel = l10n.dashboardGoalA11y(
      periodLabel,
      customTitle ?? l10n.dashboardGoalTapToEdit,
      progress.complete
          ? l10n.dashboardGoalComplete
          : l10n.dashboardGoalInProgress,
    );

    return Card(
      child: Semantics(
        button: true,
        label: a11yLabel,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customTitle ??
                              l10n.dashboardGoalTitleFallback(periodLabel),
                          style: (customTitle != null
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.labelMedium)
                              ?.copyWith(
                            color: customTitle != null
                                ? null
                                : theme.colorScheme.outline,
                            letterSpacing: customTitle != null ? 0 : 1.1,
                            fontWeight: customTitle != null
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customTitle != null)
                          Text(
                            periodLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              letterSpacing: 1.1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${(progress.overallPercent * 100).round()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_outlined,
                      size: 14, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 14),
              for (int i = 0; i < GoalTargetKind.values.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _TargetRow(
                  kind: GoalTargetKind.values[i],
                  target: byKind[GoalTargetKind.values[i]],
                  unit: unit,
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  final GoalTargetKind kind;
  final TargetProgress? target;
  final DistanceUnit unit;
  const _TargetRow({
    required this.kind,
    required this.target,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = target;

    if (t == null) {
      // Unset target — single muted line, no bar, no feedback.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                goalKindLabel(kind),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline.withValues(alpha: 0.6),
                ),
              ),
            ),
            Text(
              '—',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline.withValues(alpha: 0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final completeColor = theme.brightness == Brightness.dark
        ? Colors.green.shade300
        : Colors.green.shade600;
    final accent = t.complete ? completeColor : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                goalKindLabel(kind),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            Text(
              _valueText(t, unit),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: t.percent,
            minHeight: 6,
            color: accent,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(
              t.complete ? Icons.check_circle : Icons.trending_up,
              size: 12,
              color: accent,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                t.feedback,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _valueText(TargetProgress t, DistanceUnit unit) {
    switch (t.kind) {
      case GoalTargetKind.distance:
        final c = UnitFormat.distanceValue(t.current, unit);
        final tgt = UnitFormat.distanceValue(t.target, unit);
        return '$c / $tgt ${UnitFormat.distanceLabel(unit)}';
      case GoalTargetKind.time:
        return '${_coarseDuration(t.current)} / ${_coarseDuration(t.target)}';
      case GoalTargetKind.avgPace:
        final c =
            t.current > 0 ? UnitFormat.pace(t.current, unit) : '--:--';
        final tgt = UnitFormat.pace(t.target, unit);
        return '$c / $tgt ${UnitFormat.paceLabel(unit)}';
      case GoalTargetKind.runCount:
        return '${t.current.toInt()} / ${t.target.toInt()}';
    }
  }

  static String _coarseDuration(double seconds) {
    final totalMin = (seconds / 60).round();
    if (totalMin >= 60) {
      final h = totalMin ~/ 60;
      final m = totalMin % 60;
      return m > 0 ? '${h}h ${m}m' : '${h}h';
    }
    return '${totalMin}m';
  }
}

class _PbRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _PbRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Compact 3-column stat card used in the dashboard's activity
/// summary strip. Replaces the stacked "This Week" / "This Month" /
/// "All Time" surfaces — same data, tighter footprint. Tappable
/// when [onTap] is set (week + month tap into PeriodSummary; all
/// time has no period detail surface, so the card stays inert).
class _PeriodStatCard extends StatelessWidget {
  final String label;
  final double distanceMetres;
  final int runCount;
  final double vertMetres;
  final DistanceUnit unit;
  final VoidCallback? onTap;

  const _PeriodStatCard({
    required this.label,
    required this.distanceMetres,
    required this.runCount,
    required this.vertMetres,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final value = UnitFormat.distanceValue(distanceMetres, unit);
    final unitLabel = UnitFormat.distanceLabel(unit);
    final inner = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.06,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unitLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dashboardRunCount(runCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (vertMetres > 0) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terrain,
                  size: 12,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    l10n.dashboardVert(UnitFormat.elevation(vertMetres, unit)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
    final isTappable = onTap != null;
    final theme0 = Theme.of(context);
    // Subtle differentiation so users can tell which tiles drill in.
    // - Tappable: outlined border in the primary tint + trailing
    //   chevron in the value row + standard Card elevation.
    // - Non-tappable: zero elevation + no chevron + no outline — sits
    //   visually flatter so it reads as a read-only stat.
    // Was previously visually identical regardless of onTap — field
    // report: "clickable sections should be distinguishable from non-
    // clickable fields … Week / Month / All Time look the same but
    // only Week and Month are clickable."
    final body = Stack(
      children: [
        inner,
        if (isTappable)
          Positioned(
            right: 8,
            top: 8,
            child: Icon(
              Icons.chevron_right,
              size: 16,
              color: theme0.colorScheme.outline.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: isTappable ? null : 0,
      shape: isTappable
          ? RoundedRectangleBorder(
              side: BorderSide(
                color: theme0.colorScheme.primary.withValues(alpha: 0.25),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            )
          : RoundedRectangleBorder(
              side: BorderSide(
                color: theme0.colorScheme.outline.withValues(alpha: 0.18),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
      // audit/accessibility (2026-05-25) High — WCAG 4.1.2. The
      // tappable InkWell was bare; without Semantics TalkBack
      // announced only the raw stat numbers in reading order.
      // Wrapping with a button-roled label restores the semantics
      // for the period summary drill-in.
      child: isTappable
          ? Semantics(
              button: true,
              label: l10n.dashboardPeriodSummaryA11y(
                label,
                '${UnitFormat.distanceValue(distanceMetres, unit)} '
                    '${UnitFormat.distanceLabel(unit)}',
                l10n.dashboardRunCount(runCount),
                vertMetres > 0
                    ? l10n.dashboardElevationGainSuffix(
                        UnitFormat.elevation(vertMetres, unit))
                    : '',
              ),
              child: InkWell(onTap: onTap, child: body),
            )
          : body,
    );
  }
}

/// Current + best run-streak card. Strava-style daily grace — a
/// missing today doesn't break the streak if yesterday is intact.
/// Pure compute via `lib/streaks.dart` so the helper can be
/// unit-tested without a widget pump.
class _StreakRow extends StatelessWidget {
  final List<Run> runs;
  const _StreakRow({required this.runs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final streaks = computeRunStreaks(
      runs.map((r) => r.startedAt).toList(),
      DateTime.now(),
    );
    final crown = streaks.current > 0;
    final color = crown ? const Color(0xFFF5B30A) : theme.colorScheme.outline;
    final bestText = streaks.best > streaks.current
        ? l10n.dashboardStreakBest(streaks.best)
        : streaks.current > 0
            ? l10n.dashboardStreakAllTimeBest
            // Encourage rather than guilt a beginner with no current streak
            // (new persona #26).
            : streaks.best > 0
                ? l10n.dashboardStreakRestart
                : l10n.dashboardStreakStart;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Icon(Icons.local_fire_department, color: color, size: 28),
                const SizedBox(width: 6),
                Text(
                  '${streaks.current}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  streaks.current == 1
                      ? l10n.dashboardStreakDayUnit
                      : l10n.dashboardStreakDaysUnit,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.dashboardStreakCurrent,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        Column(
          children: [
            Text(
              bestText,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.dashboardStreakHistory,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// GitHub-style activity heatmap — a 7×[weeks] grid of squares, intensity
/// scaled to the day's run count. Rightmost column is the current week;
/// leftmost is `weeks - 1` weeks ago. Mirrors the web dashboard's
/// calendar-heatmap component so a runner switching between devices
/// sees the same shape.
/// Maps a horizontal tap offset on the run-heatmap grid to the start
/// date (week anchor) of the column it landed in. Columns are weeks;
/// the offset is clamped so a tap past either edge resolves to the
/// first or last visible week rather than off-grid.
DateTime heatmapWeekAnchor({
  required double localDx,
  required double cellSize,
  required double gap,
  required int weeks,
  required DateTime gridStart,
}) {
  final col = (localDx / (cellSize + gap)).floor().clamp(0, weeks - 1);
  return gridStart.add(Duration(days: 7 * col));
}

class _RunHeatmap extends StatelessWidget {
  final List<Run> runs;
  final int weeks;

  /// Tapping a week column opens that week's summary. Null leaves the
  /// heatmap a static read-only grid.
  final void Function(DateTime weekAnchor)? onWeekTap;
  const _RunHeatmap({required this.runs, this.weeks = 20, this.onWeekTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = weekStartLocal(now);
    final gridStart = weekStart.subtract(Duration(days: 7 * (weeks - 1)));

    final counts = <int, int>{};
    for (final r in runs) {
      final key = _epochDay(r.startedAt.toLocal());
      counts[key] = (counts[key] ?? 0) + 1;
    }

    final emptyColour = theme.colorScheme.surfaceContainerHighest;
    final l1Colour = theme.colorScheme.primary.withValues(alpha: 0.35);
    final l2Colour = theme.colorScheme.primary.withValues(alpha: 0.65);
    final l3Colour = theme.colorScheme.primary;

    Color legendColour(int c) {
      if (c <= 0) return emptyColour;
      if (c == 1) return l1Colour;
      if (c == 2) return l2Colour;
      return l3Colour;
    }

    return LayoutBuilder(builder: (context, constraints) {
      const gap = 2.0;
      final cellSize = ((constraints.maxWidth - gap * (weeks - 1)) / weeks)
          .clamp(8.0, 16.0);
      final gridWidth = cellSize * weeks + gap * (weeks - 1);
      final gridHeight = cellSize * 7 + gap * 6;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Single CustomPaint replaces the previous 7×20=140 Container +
          // Builder + EdgeInsets allocations per dashboard rebuild.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onWeekTap == null
                ? null
                : (details) => onWeekTap!(heatmapWeekAnchor(
                      localDx: details.localPosition.dx,
                      cellSize: cellSize,
                      gap: gap,
                      weeks: weeks,
                      gridStart: gridStart,
                    )),
            child: SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: CustomPaint(
                painter: _HeatmapPainter(
                  counts: counts,
                  gridStart: gridStart,
                  today: today,
                  weeks: weeks,
                  cellSize: cellSize,
                  gap: gap,
                  emptyColour: emptyColour,
                  l1: l1Colour,
                  l2: l2Colour,
                  l3: l3Colour,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(l10n.dashboardHeatmapLess,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline)),
              const SizedBox(width: 6),
              for (final c in [0, 1, 2, 3]) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: legendColour(c),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
              ],
              const SizedBox(width: 3),
              Text(l10n.dashboardHeatmapMore,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline)),
            ],
          ),
          if (onWeekTap != null) ...[
            const SizedBox(height: 6),
            Text(l10n.dashboardHeatmapTapHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ],
      );
    });
  }
}

int _epochDay(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  return local.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
}

class _HeatmapPainter extends CustomPainter {
  final Map<int, int> counts;
  final DateTime gridStart;
  final DateTime today;
  final int weeks;
  final double cellSize;
  final double gap;
  final Color emptyColour;
  final Color l1;
  final Color l2;
  final Color l3;

  _HeatmapPainter({
    required this.counts,
    required this.gridStart,
    required this.today,
    required this.weeks,
    required this.cellSize,
    required this.gap,
    required this.emptyColour,
    required this.l1,
    required this.l2,
    required this.l3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(2);
    final emptyP = Paint()..color = emptyColour;
    final l1P = Paint()..color = l1;
    final l2P = Paint()..color = l2;
    final l3P = Paint()..color = l3;

    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = gridStart.add(Duration(days: w * 7 + d));
        // Don't paint future days — they're outside the scale and look
        // weird with an "empty" tile shown.
        if (day.isAfter(today)) continue;
        final count = counts[_epochDay(day)] ?? 0;
        final paint = count <= 0
            ? emptyP
            : count == 1
                ? l1P
                : count == 2
                    ? l2P
                    : l3P;
        final x = w * (cellSize + gap);
        final y = d * (cellSize + gap);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cellSize, cellSize),
            radius,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      !identical(old.counts, counts) ||
      old.gridStart != gridStart ||
      old.today != today ||
      old.weeks != weeks ||
      old.cellSize != cellSize ||
      old.emptyColour != emptyColour ||
      old.l1 != l1 ||
      old.l2 != l2 ||
      old.l3 != l3;
}

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../l10n/number_format.dart';
import '../local_run_store.dart';
import '../training.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import 'plan_detail_screen.dart';
import 'plan_library_screen.dart';
import 'plan_new_screen.dart';

class PlansScreen extends StatefulWidget {
  final TrainingService training;
  final ApiClient? apiClient;

  /// Threaded down to `PlanDetailScreen` for the P2 adaptive-replan fitness
  /// gate (gated OFF by default). Null when no run store is in scope.
  final LocalRunStore? runStore;

  const PlansScreen(
      {super.key, required this.training, this.apiClient, this.runStore});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<TrainingPlanRow> _plans = const [];
  bool _loading = true;
  _PlansLoadError? _error;

  @override
  void initState() {
    super.initState();
    widget.training.addListener(_onChange);
    _load();
  }

  @override
  void dispose() {
    widget.training.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) _load();
  }

  /// Runs a plan mutation (abandon / delete), surfacing a failure as a
  /// banner instead of letting it vanish silently — the plan still
  /// exists, so a swallowed error would leave the list looking unchanged
  /// with no explanation. On success the list reloads.
  Future<void> _runPlanAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showTopBanner(context, AppLocalizations.of(context).plansActionFailed('$e'));
      }
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p =
          await widget.training.fetchMyPlans().timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _plans = p;
        _loading = false;
      });
    } on TimeoutException catch (e) {
      debugPrint('PlansScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _PlansLoadError.timeout;
        });
      }
    } catch (e, s) {
      debugPrint('PlansScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _PlansLoadError.generic;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = widget.apiClient?.userId != null;
    // Samsung devices with the 3-button nav bar report a bottom viewPadding
    // the Scaffold does NOT automatically pad FABs for (that auto-pad only
    // applies when a bottomNavigationBar is present). Apply it manually.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.plansTitle),
        actions: [
          if (signedIn)
            IconButton(
              icon: const Icon(Icons.public),
              tooltip: l10n.plansBrowseLibrary,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlanLibraryScreen(training: widget.training),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: signedIn
          ? Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: FloatingActionButton.extended(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlanNewScreen(training: widget.training),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.plansNewPlan),
              ),
            )
          : null,
      body: !signedIn
          ? const _SignInPrompt()
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(
                  message: _error == _PlansLoadError.timeout
                      ? l10n.plansTimeoutError
                      : l10n.plansLoadError,
                  onRetry: _load)
              : _plans.isEmpty
              ? _Empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    // Bottom padding = FAB clearance (80) + system nav
                    // inset so the last card isn't trapped behind either.
                    padding: EdgeInsets.fromLTRB(
                      16, 12, 16, 80 + bottomInset),
                    itemCount: _plans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final p = _plans[i];
                      return _PlanTile(
                        plan: p,
                        onTap: () async {
                          await Navigator.of(ctx).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PlanDetailScreen(
                                training: widget.training,
                                planId: p.id,
                                runStore: widget.runStore,
                              ),
                            ),
                          );
                          _load();
                        },
                        onAbandon: p.status == 'active'
                            ? () async {
                                final ok = await _confirm(
                                  context,
                                  l10n.plansAbandonTitle(p.name),
                                  l10n.plansAbandonBody,
                                  confirmLabel: l10n.plansAbandon,
                                );
                                if (ok) {
                                  await _runPlanAction(() =>
                                      widget.training
                                          .updateStatus(p.id, 'abandoned'));
                                }
                              }
                            : null,
                        onDelete: () async {
                          final ok = await _confirm(
                            context,
                            l10n.plansDeleteTitle(p.name),
                            l10n.plansDeleteBody,
                          );
                          if (ok) {
                            await _runPlanAction(
                                () => widget.training.deletePlan(p.id));
                          }
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body,
    {String? confirmLabel}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.plansCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? l10n.plansDelete),
          ),
        ],
      );
    },
  );
  return res == true;
}

class _PlanTile extends StatelessWidget {
  final TrainingPlanRow plan;
  final VoidCallback onTap;
  final VoidCallback? onAbandon;
  final VoidCallback onDelete;

  const _PlanTile({
    required this.plan,
    required this.onTap,
    required this.onDelete,
    this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: plan.status == 'active'
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    plan.status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: plan.status == 'active'
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _meta(theme, Icons.flag, goalEventLabel(
                    goalEventFromDb(plan.goalEvent))),
                if (plan.goalTimeSeconds != null)
                  _meta(theme, Icons.timer, fmtHms(plan.goalTimeSeconds)),
                if (plan.vdot != null)
                  _meta(theme, Icons.trending_up,
                      'VDOT ${formatFixed(plan.vdot!, 1, activeLocaleTag)}'),
                _meta(theme, Icons.calendar_today,
                    '${toIsoDate(plan.startDate)} → ${toIsoDate(plan.endDate)}'),
                _meta(theme, Icons.event_repeat,
                    l10n.plansDaysPerWeek(plan.daysPerWeek)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onAbandon != null)
                  TextButton(
                    onPressed: onAbandon,
                    child: Text(l10n.plansAbandon),
                  ),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: Text(l10n.plansDelete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(ThemeData theme, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.colorScheme.outline),
        const SizedBox(width: 3),
        Text(text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            )),
      ],
    );
  }
}

enum _PlansLoadError { timeout, generic }

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48,
                color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.plansSignInTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              l10n.plansSignInBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month, size: 48,
                color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              l10n.plansEmptyTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.plansEmptyBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

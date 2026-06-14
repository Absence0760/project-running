import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../training.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';
import 'plan_detail_screen.dart';

/// Public plan library — browse + search published plans any user can
/// clone. Mirrors web `/plans/library`. Tapping a plan opens a preview
/// (PlanLibraryPreviewScreen) with a clone-into-my-account action.
class PlanLibraryScreen extends StatefulWidget {
  final TrainingService training;

  const PlanLibraryScreen({super.key, required this.training});

  @override
  State<PlanLibraryScreen> createState() => _PlanLibraryScreenState();
}

class _PlanLibraryScreenState extends State<PlanLibraryScreen> {
  List<PublicPlanLibraryEntry> _plans = const [];
  bool _loading = true;
  bool _error = false;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final plans = await widget.training
          .fetchPublicPlanLibrary(query: _query)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _onSearch(String v) {
    _query = v;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.planLibraryTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.planLibrarySearchHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error
                    ? ErrorState(message: l10n.planLibraryLoadError, onRetry: _load)
                    : _plans.isEmpty
                        ? Center(
                            child: Text(
                              _query.trim().isEmpty
                                  ? l10n.planLibraryEmpty
                                  : l10n.planLibraryEmptySearch(_query),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _plans.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _LibraryCard(
                                entry: _plans[i],
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PlanLibraryPreviewScreen(
                                      training: widget.training,
                                      entry: _plans[i],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

int _weeksOf(TrainingPlanRow p) {
  final days = p.endDate.difference(p.startDate).inDays + 1;
  final w = (days / 7).ceil();
  return w < 1 ? 1 : w;
}

class _LibraryCard extends StatelessWidget {
  final PublicPlanLibraryEntry entry;
  final VoidCallback onTap;

  const _LibraryCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = entry.plan;
    final author = entry.authorHandle ?? l10n.planLibraryAnonymous;
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(p.name, style: theme.textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.planLibraryByAuthor(author)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _chip(theme, goalEventLabel(goalEventFromDb(p.goalEvent))),
                  _chip(theme, l10n.planLibraryWeeks(_weeksOf(p))),
                  _chip(theme, l10n.planLibraryDaysPerWeek(p.daysPerWeek)),
                ],
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: theme.textTheme.labelSmall),
      );
}

/// Preview of one public-library plan + a clone-into-my-account action.
class PlanLibraryPreviewScreen extends StatefulWidget {
  final TrainingService training;
  final PublicPlanLibraryEntry entry;

  const PlanLibraryPreviewScreen({
    super.key,
    required this.training,
    required this.entry,
  });

  @override
  State<PlanLibraryPreviewScreen> createState() => _PlanLibraryPreviewScreenState();
}

class _PlanLibraryPreviewScreenState extends State<PlanLibraryPreviewScreen> {
  DateTime _startDate = _nextMonday();
  bool _cloning = false;

  static DateTime _nextMonday() {
    final d = DateTime.now();
    final offset = (8 - d.weekday) % 7;
    return DateTime(d.year, d.month, d.day).add(Duration(days: offset == 0 ? 7 : offset));
  }

  Future<void> _clone() async {
    if (_cloning) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _cloning = true);
    try {
      final newId = await widget.training
          .clonePublicPlan(templateId: widget.entry.plan.id, startDate: _startDate)
          .timeout(kBackendLoadTimeout);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlanDetailScreen(training: widget.training, planId: newId),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _cloning = false);
        showTopBanner(context, l10n.planLibraryCloneFailed(e.toString()));
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = widget.entry.plan;
    final author = widget.entry.authorHandle ?? l10n.planLibraryAnonymous;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.planLibraryByAuthor(author), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(label: Text(goalEventLabel(goalEventFromDb(p.goalEvent)))),
              Chip(label: Text(l10n.planLibraryWeeks(_weeksOf(p)))),
              Chip(label: Text(l10n.planLibraryDaysPerWeek(p.daysPerWeek))),
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.planLibraryStartDate),
            subtitle: Text(toIsoDate(_startDate)),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _cloning ? null : _clone,
            icon: _cloning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.copy_all),
            label: Text(_cloning ? l10n.planLibraryCloning : l10n.planLibraryClone),
          ),
        ],
      ),
    );
  }
}

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../social_service.dart';
import 'top_banner.dart';

const List<String> kRouteConditionKinds = [
  'clear',
  'muddy',
  'flooded',
  'snow_ice',
  'overgrown',
  'closed',
  'hazard',
  'other',
];

const List<String> kRouteConditionSeverities = ['info', 'caution', 'impassable'];

/// Reports older than this fade — a month-old "muddy" is a weaker signal than
/// a fresh one. Reports are never auto-deleted (decisions §168 freshness
/// policy); the reporter or route owner can delete, and the UI fades by age.
const int kRouteConditionFadeAfterDays = 30;

String routeConditionKindLabel(AppLocalizations l10n, String kind) {
  switch (kind) {
    case 'clear':
      return l10n.routeConditionClear;
    case 'muddy':
      return l10n.routeConditionMuddy;
    case 'flooded':
      return l10n.routeConditionFlooded;
    case 'snow_ice':
      return l10n.routeConditionSnowIce;
    case 'overgrown':
      return l10n.routeConditionOvergrown;
    case 'closed':
      return l10n.routeConditionClosed;
    case 'hazard':
      return l10n.routeConditionHazard;
    default:
      return l10n.routeConditionOther;
  }
}

String routeConditionSeverityLabel(AppLocalizations l10n, String severity) {
  switch (severity) {
    case 'caution':
      return l10n.routeConditionSeverityCaution;
    case 'impassable':
      return l10n.routeConditionSeverityImpassable;
    default:
      return l10n.routeConditionSeverityInfo;
  }
}

Color routeConditionSeverityColor(ColorScheme cs, String severity) {
  switch (severity) {
    case 'caution':
      return const Color(0xFFB45309);
    case 'impassable':
      return cs.error;
    default:
      return cs.onSurfaceVariant;
  }
}

bool routeConditionIsStale(DateTime createdAt, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  return ref.difference(createdAt).inDays > kRouteConditionFadeAfterDays;
}

/// Mirrors the web `RouteConditions.svelte`: a panel listing community
/// condition reports for a route newest-first, with a report composer for a
/// signed-in viewer who can see the route. Reads through
/// `ApiClient.fetchRouteConditions` (the privacy-redacting RPC); failures
/// fall back to an empty state (L4).
class RouteConditions extends StatefulWidget {
  final ApiClient api;
  final String routeId;
  final String routeOwnerId;

  /// When false (a read-only / shared view) the report composer is hidden.
  final bool canReport;

  const RouteConditions({
    super.key,
    required this.api,
    required this.routeId,
    required this.routeOwnerId,
    this.canReport = true,
  });

  @override
  State<RouteConditions> createState() => _RouteConditionsState();
}

class _RouteConditionsState extends State<RouteConditions> {
  bool _loading = true;
  bool _submitting = false;
  bool _composerOpen = false;
  String _kind = 'muddy';
  String _severity = 'caution';
  final _noteCtrl = TextEditingController();
  List<RouteConditionRow> _conditions = const [];

  bool get _signedIn => widget.api.userId != null;
  bool get _showComposer => widget.canReport && _signedIn;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.api.fetchRouteConditions(widget.routeId);
    if (!mounted) return;
    setState(() {
      _conditions = rows;
      _loading = false;
    });
  }

  bool _canDelete(RouteConditionRow c) =>
      widget.api.userId == c.userId || widget.api.userId == widget.routeOwnerId;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final l10n = AppLocalizations.of(context);
    try {
      final created = await widget.api.addRouteCondition(
        routeId: widget.routeId,
        condition: _kind,
        severity: _severity,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _conditions = [created, ..._conditions];
        _noteCtrl.clear();
        _composerOpen = false;
        _submitting = false;
      });
      showTopBanner(context, l10n.routeConditionsReported);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showTopBanner(context, l10n.routeConditionsReportFailed);
    }
  }

  Future<void> _delete(RouteConditionRow c) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.routeConditionsDeleteTitle),
            content: Text(l10n.routeConditionsDeleteConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.routeConditionsCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.routeConditionsDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.api.deleteRouteCondition(c.id);
      if (!mounted) return;
      setState(() =>
          _conditions = _conditions.where((q) => q.id != c.id).toList());
    } catch (_) {
      if (!mounted) return;
      showTopBanner(context, l10n.routeConditionsDeleteFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.report_outlined,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(l10n.routeConditionsTitle,
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_showComposer && !_composerOpen)
                TextButton.icon(
                  onPressed: () => setState(() => _composerOpen = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.routeConditionsReport),
                ),
            ],
          ),
        ),
        if (_composerOpen) _buildComposer(theme, cs, l10n),
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.routeConditionsLoading,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          )
        else if (_conditions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.routeConditionsEmpty,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          )
        else
          ..._conditions.map((c) => _buildRow(c, theme, cs, l10n)),
      ],
    );
  }

  Widget _buildComposer(ThemeData theme, ColorScheme cs, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(10),
        color: cs.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _LabeledDropdown(
                  label: l10n.routeConditionsKindLabel,
                  value: _kind,
                  items: kRouteConditionKinds,
                  labelFor: (k) => routeConditionKindLabel(l10n, k),
                  onChanged: (v) => setState(() => _kind = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LabeledDropdown(
                  label: l10n.routeConditionsSeverityLabel,
                  value: _severity,
                  items: kRouteConditionSeverities,
                  labelFor: (s) => routeConditionSeverityLabel(l10n, s),
                  onChanged: (v) => setState(() => _severity = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLength: 500,
            maxLines: 2,
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: l10n.routeConditionsNoteLabel,
              hintText: l10n.routeConditionsNotePlaceholder,
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _composerOpen = false),
                child: Text(l10n.routeConditionsCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(_submitting
                    ? l10n.routeConditionsReporting
                    : l10n.routeConditionsReport),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    RouteConditionRow c,
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final stale = routeConditionIsStale(c.createdAt);
    final sevColor = routeConditionSeverityColor(cs, c.severity);
    return Opacity(
      opacity: stale ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    routeConditionKindLabel(l10n, c.condition),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: sevColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  routeConditionSeverityLabel(l10n, c.severity).toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: sevColor),
                ),
                if (c.positionM != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.routeConditionsAtDistance(
                          formatDistanceForPref(c.positionM!)),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  fmtRelative(c.createdAt, activeLocaleTag),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (_canDelete(c))
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.routeConditionsDelete,
                    onPressed: () => _delete(c),
                  ),
              ],
            ),
            if (c.note != null && c.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(c.note!, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final String Function(String) labelFor;
  final ValueChanged<String> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          decoration: const InputDecoration(isDense: true),
          items: items
              .map((i) =>
                  DropdownMenuItem(value: i, child: Text(labelFor(i))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

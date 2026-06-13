import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';
import 'event_detail_screen.dart';

/// Cross-club activity discovery — the Social hub's Discover tab. Mirrors
/// `apps/web/src/lib/components/SocialDiscover.svelte`: a search field plus
/// category / cadence / weekday / time-of-day / price filters over the
/// `search_public_events` RPC (public clubs only). Tapping a result opens
/// that club event's detail. Embedded mode (the SocialScreen TabBar host)
/// moves the search field inline; the standalone path keeps its own Scaffold.
class DiscoverScreen extends StatefulWidget {
  final ApiClient api;
  final SocialService social;
  final bool embedded;

  const DiscoverScreen({
    super.key,
    required this.api,
    required this.social,
    this.embedded = false,
  });

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

const _weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  int _searchGen = 0;

  String _query = '';
  String _category = '';
  String _cadence = '';
  String _byday = '';
  String _time = '';
  String _paid = '';

  bool _loading = true;
  List<PublicEventResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final gen = ++_searchGen;
    setState(() => _loading = true);
    try {
      final next = await widget.api.searchPublicEvents(
        query: _query.trim().isEmpty ? null : _query.trim(),
        category: _category.isEmpty ? null : _category,
        cadence: _cadence.isEmpty ? null : _cadence,
        byday: _byday.isEmpty ? null : _byday,
        time: _time.isEmpty ? null : _time,
        paid: _paid.isEmpty ? null : _paid,
      );
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _scheduleSearch();
  }

  void _openEvent(PublicEventResult e) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(
          social: widget.social,
          clubSlug: e.clubSlug,
          eventId: e.id,
        ),
      ),
    );
  }

  String _categoryLabel(AppLocalizations l10n, String c) {
    switch (c) {
      case 'run':
        return l10n.eventEditorCatRun;
      case 'cycle':
        return l10n.eventEditorCatCycle;
      case 'class':
        return l10n.eventEditorCatClass;
      case 'social':
        return l10n.eventEditorCatSocial;
      default:
        return c;
    }
  }

  String _weekdayLabel(AppLocalizations l10n, String code) {
    switch (code) {
      case 'MO':
        return l10n.discoverDayMon;
      case 'TU':
        return l10n.discoverDayTue;
      case 'WE':
        return l10n.discoverDayWed;
      case 'TH':
        return l10n.discoverDayThu;
      case 'FR':
        return l10n.discoverDayFri;
      case 'SA':
        return l10n.discoverDaySat;
      case 'SU':
        return l10n.discoverDaySun;
      default:
        return code;
    }
  }

  String _cadenceLabel(AppLocalizations l10n, PublicEventResult e) {
    if (e.recurrenceFreq == null) return l10n.discoverOneOff;
    final freq = switch (e.recurrenceFreq) {
      'weekly' => l10n.discoverWeekly,
      'biweekly' => l10n.discoverBiweekly,
      'monthly' => l10n.discoverMonthly,
      _ => l10n.discoverWeekly,
    };
    final days = (e.recurrenceByday ?? [])
        .map((d) => _weekdayLabel(l10n, d))
        .join(', ');
    return days.isEmpty ? freq : '$freq · $days';
  }

  String _priceLabel(AppLocalizations l10n, PublicEventResult e) {
    if (e.priceCents == null) return l10n.discoverFree;
    final amount = e.priceCents! / 100.0;
    final code = (e.currency ?? 'usd').toUpperCase();
    try {
      return NumberFormat.simpleCurrency(name: code).format(amount);
    } catch (_) {
      return '${amount.toStringAsFixed(2)} $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final filters = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l10n.discoverSearchPlaceholder,
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              isDense: true,
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtl.clear();
                        _onQueryChanged('');
                      },
                    )
                  : null,
            ),
            onChanged: _onQueryChanged,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final c in const ['', 'run', 'cycle', 'class', 'social'])
                ChoiceChip(
                  label: Text(c.isEmpty
                      ? l10n.discoverActivityAll
                      : _categoryLabel(l10n, c)),
                  selected: _category == c,
                  onSelected: (_) {
                    setState(() => _category = c);
                    _run();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _DropdownField<String>(
                label: l10n.discoverCadenceLabel,
                value: _cadence,
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.discoverCadenceAny)),
                  DropdownMenuItem(value: 'one_off', child: Text(l10n.discoverOneOff)),
                  DropdownMenuItem(value: 'weekly', child: Text(l10n.discoverWeekly)),
                  DropdownMenuItem(value: 'biweekly', child: Text(l10n.discoverBiweekly)),
                  DropdownMenuItem(value: 'monthly', child: Text(l10n.discoverMonthly)),
                ],
                onChanged: (v) {
                  setState(() => _cadence = v ?? '');
                  _run();
                },
              ),
              _DropdownField<String>(
                label: l10n.discoverDayLabel,
                value: _byday,
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.discoverDayAny)),
                  for (final d in _weekdays)
                    DropdownMenuItem(value: d, child: Text(_weekdayLabel(l10n, d))),
                ],
                onChanged: (v) {
                  setState(() => _byday = v ?? '');
                  _run();
                },
              ),
              _DropdownField<String>(
                label: l10n.discoverTimeLabel,
                value: _time,
                items: [
                  DropdownMenuItem(value: '', child: Text(l10n.discoverTimeAny)),
                  DropdownMenuItem(value: 'morning', child: Text(l10n.discoverMorning)),
                  DropdownMenuItem(value: 'afternoon', child: Text(l10n.discoverAfternoon)),
                  DropdownMenuItem(value: 'evening', child: Text(l10n.discoverEvening)),
                ],
                onChanged: (v) {
                  setState(() => _time = v ?? '');
                  _run();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(l10n.discoverPriceLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final p in const ['', 'free', 'paid'])
                ChoiceChip(
                  label: Text(switch (p) {
                    'free' => l10n.discoverFree,
                    'paid' => l10n.discoverPaid,
                    _ => l10n.discoverPriceAny,
                  }),
                  selected: _paid == p,
                  onSelected: (_) {
                    setState(() => _paid = p);
                    _run();
                  },
                ),
            ],
          ),
        ],
      ),
    );

    final Widget resultsArea;
    if (_loading) {
      resultsArea = Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: 12),
              Text(l10n.discoverLoading,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    } else if (_results.isEmpty) {
      resultsArea = Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
        child: Center(
          child: Text(
            l10n.discoverEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    } else {
      resultsArea = ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _ResultCard(
          event: _results[i],
          title: (_results[i].discipline?.isNotEmpty ?? false)
              ? _results[i].discipline!
              : _results[i].title,
          meta:
              '${_categoryLabel(l10n, _results[i].category)} · ${_cadenceLabel(l10n, _results[i])}',
          price: _priceLabel(l10n, _results[i]),
          free: _results[i].priceCents == null,
          onTap: () => _openEvent(_results[i]),
        ),
      );
    }

    final body = SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [filters, resultsArea],
        ),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialTabDiscover)),
      body: body,
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isDense: true,
          underline: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final PublicEventResult event;
  final String title;
  final String meta;
  final String price;
  final bool free;
  final VoidCallback onTap;

  const _ResultCard({
    required this.event,
    required this.title,
    required this.meta,
    required this.price,
    required this.free,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(event.clubName, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: free
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  price,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: free
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

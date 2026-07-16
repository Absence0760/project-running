import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../local_gym_store.dart';
import '../widgets/error_state.dart';
import 'session_detail_screen.dart';

/// Read-only list of the user's session plans (session_planner.md P1). Tapping a
/// row opens the expanded read view. Building/editing lives on web first; the
/// detail screen's follow-along runner logs a gym_workout into [gymStore].
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, required this.api, required this.gymStore});

  final ApiClient api;
  final LocalGymStore gymStore;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  bool _loading = true;
  bool _error = false;
  List<SessionPlanRow> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final plans = await widget.api.fetchSessionPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      debugPrint('SessionsScreen._load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sessionTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? ErrorState(message: l10n.sessionLoadError, onRetry: _load)
              : _plans.isEmpty
                  ? _EmptyState(l10n: l10n)
                  : ListView.builder(
                      itemCount: _plans.length,
                      itemBuilder: (context, i) {
                        final p = _plans[i];
                        final subtitleParts = <String>[
                          if (p.discipline != null) p.discipline!,
                          if (p.estDurationMin != null)
                            l10n.sessionEstDuration(p.estDurationMin!),
                        ];
                        return ListTile(
                          title: Text(p.title.isEmpty ? l10n.sessionUntitled : p.title),
                          subtitle: subtitleParts.isEmpty
                              ? null
                              : Text(subtitleParts.join(' · ')),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SessionDetailScreen(
                                api: widget.api,
                                gymStore: widget.gymStore,
                                planId: p.id,
                                titleHint: p.title,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.sessionEmpty,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.sessionEmptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

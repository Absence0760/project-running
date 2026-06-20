import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';
import 'challenge_detail_screen.dart';

String challengeMetricLabel(AppLocalizations l10n, String metric) {
  switch (metric) {
    case 'duration':
      return l10n.challengesMetricDuration;
    case 'activity_count':
      return l10n.challengesMetricActivityCount;
    case 'streak_days':
      return l10n.challengesMetricStreak;
    case 'distance':
    default:
      return l10n.challengesMetricDistance;
  }
}

/// The Social hub's Challenges sub-tab. Browse public challenges + the user's
/// joined ones. `embedded: true` returns the body only (no Scaffold) so the
/// SocialScreen host owns the chrome.
class ChallengesScreen extends StatefulWidget {
  final SocialService social;
  final bool embedded;
  const ChallengesScreen({super.key, required this.social, this.embedded = false});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<ChallengeView>? _all;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.social.fetchChallenges();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _all = const [];
        _failed = true;
      });
    }
  }

  Future<void> _open(ChallengeView c) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChallengeDetailScreen(social: widget.social, challengeId: c.id),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = _all;
    final body = all == null
        ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(l10n.challengesLoadFailed,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                _section(
                  context,
                  l10n.challengesMyChallenges,
                  all.where((c) => c.joined).toList(),
                  l10n.challengesEmpty,
                ),
                const SizedBox(height: 20),
                _section(
                  context,
                  l10n.challengesBrowse,
                  all.where((c) => !c.joined && c.isPublic).toList(),
                  l10n.challengesBrowseEmpty,
                ),
              ],
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.challengesTitle)),
      body: body,
    );
  }

  Widget _section(BuildContext context, String title, List<ChallengeView> rows, String emptyMsg) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text(emptyMsg, style: TextStyle(color: Theme.of(context).hintColor))
        else
          ...rows.map((c) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(c.title),
                  subtitle: Text(
                    '${challengeMetricLabel(l10n, c.metric)} · ${l10n.challengesParticipants(c.participantCount)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(c),
                ),
              )),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../challenge_list.dart';
import '../fab_clearance.dart';
import '../l10n/gen/app_localizations.dart';
import '../social_service.dart';
import '../widgets/challenge_form_sheet.dart';
import '../widgets/challenge_progress_bar.dart';
import '../widgets/error_state.dart';
import 'challenge_detail_screen.dart';

/// The Social hub's Challenges sub-tab. Browse public challenges + the user's
/// joined ones, and author a new one. `embedded: true` returns the body only
/// (no Scaffold) so the SocialScreen host owns the chrome — including the
/// create FAB, which it hoists off [ChallengesScreenState] the same way it
/// hoists Clubs'.
class ChallengesScreen extends StatefulWidget {
  final SocialService social;
  final bool embedded;
  const ChallengesScreen({super.key, required this.social, this.embedded = false});

  @override
  State<ChallengesScreen> createState() => ChallengesScreenState();
}

class ChallengesScreenState extends State<ChallengesScreen> {
  List<ChallengeView>? _all;
  bool _failed = false;

  /// Stamped when the list lands so every row grades its window against one
  /// instant, instead of each rebuild sampling a slightly different clock.
  DateTime _loadedAt = DateTime.now();

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
        _loadedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _all = const [];
        _failed = true;
      });
    }
  }

  Future<void> _open(ChallengeView c) => _openById(c.id);

  Future<void> _openById(String id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChallengeDetailScreen(social: widget.social, challengeId: id),
    ));
    if (!mounted) return;
    _load();
  }

  /// The create FAB. Public so the embedded host (SocialScreen) can hoist it
  /// onto its own Scaffold, matching `ClubsScreenState.buildCreateClubFab`.
  Widget buildCreateChallengeFab(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'challenges_create_fab',
      onPressed: () async {
        final id = await showChallengeFormSheet(context, social: widget.social);
        if (id == null || !mounted) return;
        await _openById(id);
      },
      icon: const Icon(Icons.add),
      label: Text(AppLocalizations.of(context).challengesCreate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = _all;
    final Widget body;
    if (all == null) {
      body = const Center(
          child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    } else if (_failed) {
      body = ErrorState(message: l10n.challengesLoadFailed, onRetry: _load);
    } else {
      body = RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, fabScrollClearance(context)),
              children: [
                _section(
                  context,
                  l10n.challengesMyChallenges,
                  all.where((c) => c.joined).toList(),
                  l10n.challengesEmpty,
                  showProgress: true,
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
    }
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.challengesTitle)),
      body: body,
      floatingActionButton: buildCreateChallengeFab(context),
    );
  }

  Widget _section(BuildContext context, String title, List<ChallengeView> rows, String emptyMsg,
      {bool showProgress = false}) {
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
                child: showProgress
                    ? _progressRow(context, c)
                    : ListTile(
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

  /// A joined row, carrying the caller's own progress. The value is whatever
  /// `my_active_challenges` reported; a challenge outside that RPC's
  /// live-plus-7-day window has no value at all, and says so — drawing an empty
  /// bar there would state a zero nobody measured.
  Widget _progressRow(BuildContext context, ChallengeView c) {
    final l10n = AppLocalizations.of(context);
    final hint = TextStyle(color: Theme.of(context).hintColor);
    final progress = myProgressView(
      myValue: c.myValue,
      startsAt: c.startsAt,
      now: _loadedAt,
    );
    return InkWell(
      onTap: () => _open(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            Text(
              '${challengeMetricLabel(l10n, c.metric)} · ${l10n.challengesParticipants(c.participantCount)}',
              style: hint,
            ),
            const SizedBox(height: 10),
            if (progress.state == MyProgressState.unknown)
              Text(l10n.challengesProgressUnavailable, style: hint)
            else
              ChallengeProgressBar(
                metric: c.metric,
                value: progress.value,
                goal: c.goalValue,
                startsAt: c.startsAt,
                endsAt: c.endsAt,
              ),
            if (c.myRank != null || c.completedAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (c.myRank != null)
                    Text(l10n.challengesLeaderboardRank(c.myRank!),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  if (c.myRank != null && c.completedAt != null)
                    const SizedBox(width: 12),
                  if (c.completedAt != null)
                    Text(l10n.challengesBadgeEarned,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

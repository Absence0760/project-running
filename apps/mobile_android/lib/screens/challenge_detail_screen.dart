import 'package:flutter/material.dart';

import '../challenge_progress.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../widgets/top_banner.dart';

String challengeValueLabel(AppLocalizations l10n, String metric, num value) {
  switch (metric) {
    case 'duration':
      final total = value.round();
      final h = total ~/ 3600;
      final m = (total % 3600) ~/ 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    case 'vert':
      return formatElevationForPref(value.toDouble());
    case 'streak_days':
      return l10n.challengesUnitDays(value.round());
    case 'activity_count':
      return l10n.challengesUnitActivities(value.round());
    case 'distance':
    default:
      return formatDistanceForPref(value.toDouble());
  }
}

class ChallengeDetailScreen extends StatefulWidget {
  final SocialService social;
  final String challengeId;
  const ChallengeDetailScreen({super.key, required this.social, required this.challengeId});

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  ChallengeView? _challenge;
  List<ChallengeLeaderboardEntry> _board = const [];
  bool _loaded = false;
  bool _notFound = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.social.fetchChallengeById(widget.challengeId);
      if (c == null) {
        if (!mounted) return;
        setState(() {
          _notFound = true;
          _loaded = true;
        });
        return;
      }
      final board = await widget.social
          .fetchChallengeLeaderboard(widget.challengeId, byTeam: c.scope == 'club_vs_club');
      if (!mounted) return;
      setState(() {
        _challenge = c;
        _board = board;
        _loaded = true;
        _notFound = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notFound = true;
        _loaded = true;
      });
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.social.joinChallenge(widget.challengeId);
      await _load();
    } catch (_) {
      if (mounted) showTopBanner(context, AppLocalizations.of(context).challengesJoinFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.challengesLeaveConfirmTitle),
        content: Text(l10n.challengesLeaveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.checkpointCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.challengesLeave)),
        ],
      ),
    );
    if (ok != true || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.social.leaveChallenge(widget.challengeId);
      await _load();
    } catch (_) {
      if (mounted) showTopBanner(context, l10n.challengesLeaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.challengesDeleteConfirmTitle),
        content: Text(l10n.challengesDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.checkpointCancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.challengesDelete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.social.deleteChallenge(widget.challengeId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showTopBanner(context, l10n.challengesLoadFailed);
    }
  }

  String _windowLabel(AppLocalizations l10n, ChallengeView c) {
    final now = DateTime.now();
    if (now.isAfter(c.endsAt)) return l10n.challengesEnded;
    final days = c.endsAt.difference(now).inDays;
    return days <= 1 ? l10n.challengesEndsToday : l10n.challengesEndsIn(days);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _challenge;
    final isCreator = c != null && c.creatorId != null && c.creatorId == widget.social.currentUserId;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.title ?? l10n.challengesTitle),
        actions: [
          if (isCreator)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _notFound || c == null
              ? Center(child: Text(l10n.challengesNotFound))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(_windowLabel(l10n, c), style: TextStyle(color: Theme.of(context).hintColor)),
                    if ((c.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(c.description!),
                    ],
                    const SizedBox(height: 16),
                    if (c.joined && c.scope != 'club_vs_club') _progress(context, c),
                    const SizedBox(height: 12),
                    if (c.joined)
                      OutlinedButton(onPressed: _busy ? null : _leave, child: Text(l10n.challengesLeave))
                    else
                      FilledButton(onPressed: _busy ? null : _join, child: Text(l10n.challengesJoin)),
                    const SizedBox(height: 24),
                    Text(l10n.challengesLeaderboard, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _leaderboard(context, c),
                  ],
                ),
    );
  }

  Widget _progress(BuildContext context, ChallengeView c) {
    final l10n = AppLocalizations.of(context);
    final value = c.myValue ?? 0;
    final frac = progressFraction(value, c.goalValue);
    final complete = isComplete(value, c.goalValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              c.goalValue == null
                  ? challengeValueLabel(l10n, c.metric, value)
                  : l10n.challengesGoalProgress(
                      challengeValueLabel(l10n, c.metric, value),
                      challengeValueLabel(l10n, c.metric, c.goalValue!),
                    ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (complete)
              Text(l10n.challengesProgressComplete,
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        if (frac != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: frac, minHeight: 8),
          ),
        ],
        if (!complete) _paceHint(context, c, value),
        if (c.completedAt != null) ...[
          const SizedBox(height: 8),
          Text(l10n.challengesBadgeEarned,
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
      ],
    );
  }

  Widget _paceHint(BuildContext context, ChallengeView c, num value) {
    if (c.goalValue == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final p = challengePace(
      value,
      c.goalValue,
      c.startsAt.millisecondsSinceEpoch,
      c.endsAt.millisecondsSinceEpoch,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (p.status != ChallengePaceStatus.active || p.verdict == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (p.verdict!) {
      PaceVerdict.ahead => (l10n.challengesPaceAhead, scheme.tertiary),
      PaceVerdict.behind => (l10n.challengesPaceBehind, scheme.error),
      PaceVerdict.onTrack => (l10n.challengesPaceOnTrack, scheme.primary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          if (p.verdict == PaceVerdict.behind && p.requiredPerDay != null) ...[
            const SizedBox(width: 8),
            Text(
              l10n.challengesPaceNeedPerDay(
                challengeValueLabel(l10n, c.metric, p.requiredPerDay!),
              ),
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leaderboard(BuildContext context, ChallengeView c) {
    final l10n = AppLocalizations.of(context);
    if (_board.isEmpty) {
      return Text(l10n.challengesLeaderboardEmpty, style: TextStyle(color: Theme.of(context).hintColor));
    }
    final byTeam = c.scope == 'club_vs_club';
    final meId = widget.social.currentUserId;
    return Column(
      children: _board.map((e) {
        final me = !byTeam && meId != null && e.userId == meId;
        final name = byTeam
            ? (e.teamClubId ?? '—')
            : (e.displayName ?? '—');
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: me
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(l10n.challengesLeaderboardRank(e.rank),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
              Text(challengeValueLabel(l10n, c.metric, e.value),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

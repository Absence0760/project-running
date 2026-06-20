import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';

import '../coach_load.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/date_format.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../widgets/top_banner.dart';
import 'coaching_athlete_screen.dart';

/// Coach-athlete roster hub — mobile mirror of web `/coaching`
/// (`apps/web/src/routes/coaching/+page.svelte`). A coach mints/copies
/// shareable invite links + manages their athlete roster; an athlete sees the
/// coaches they're linked to. Reads/writes through [ApiClient]'s coaching
/// methods. DISTINCT from `coach_screen.dart`, which is the AI-chat coach.
class CoachingScreen extends StatefulWidget {
  final ApiClient api;
  final Preferences preferences;

  const CoachingScreen({
    super.key,
    required this.api,
    required this.preferences,
  });

  @override
  State<CoachingScreen> createState() => _CoachingScreenState();
}

/// Build the public invite-share link. Mirrors web's
/// `${location.origin}/coaching/accept/<token>` — on mobile the origin comes
/// from `WEB_BASE_URL` (set at build time, e.g. the preview host) and falls
/// back to the production host. Pure so it can be unit-tested.
String coachInviteLink(String token, {String? webBase}) {
  var base = (webBase ??
          (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
          '')
      .trim();
  if (base.isEmpty) base = 'https://threkir.com';
  if (base.endsWith('/')) base = base.substring(0, base.length - 1);
  return '$base/coaching/accept/$token';
}

class _CoachingScreenState extends State<CoachingScreen> {
  bool _loading = true;
  bool _minting = false;
  List<CoachAthleteLink> _athletes = const [];
  List<PendingCoachInvite> _pending = const [];
  List<CoachAthleteLink> _coaches = const [];
  List<CoachRosterRow> _roster = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.api.fetchMyAthletes(),
        widget.api.fetchPendingCoachInvites(),
        widget.api.fetchMyCoaches(),
        // Roster failure is non-fatal — the rest of the screen still loads, the
        // roster card just stays hidden (mirrors the web fail-soft section).
        widget.api.fetchCoachRosterSummary().catchError(
            (_) => const <CoachRosterRow>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _athletes = results[0] as List<CoachAthleteLink>;
        _pending = results[1] as List<PendingCoachInvite>;
        _coaches = results[2] as List<CoachAthleteLink>;
        _roster = results[3] as List<CoachRosterRow>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopBanner(
          context, AppLocalizations.of(context).coachingLoadError('$e'));
    }
  }

  Future<void> _copyLink(String token) async {
    final l10n = AppLocalizations.of(context);
    final link = coachInviteLink(token);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    showTopBanner(context, l10n.coachingInviteLinkCopied);
  }

  Future<void> _shareLink(String token) async {
    final link = coachInviteLink(token);
    await Share.share(link);
  }

  Future<void> _mintInvite() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _minting = true);
    try {
      final token = await widget.api.createCoachInvite();
      await _copyLink(token);
      final pending = await widget.api.fetchPendingCoachInvites();
      if (!mounted) return;
      setState(() => _pending = pending);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.coachingCreateInviteError('$e'));
    } finally {
      if (mounted) setState(() => _minting = false);
    }
  }

  Future<void> _revoke(PendingCoachInvite inv) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirm(l10n.coachingRevokeTitle, l10n.coachingRevokeBody,
        l10n.coachingRevoke);
    if (ok != true) return;
    try {
      await widget.api.revokeCoachInvite(inv.id);
      if (!mounted) return;
      setState(() => _pending = _pending.where((p) => p.id != inv.id).toList());
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.coachingRevokeInviteError('$e'));
    }
  }

  Future<void> _removeAthlete(CoachAthleteLink link) async {
    final l10n = AppLocalizations.of(context);
    final name = link.displayName ?? l10n.coachingThisAthlete;
    final ok = await _confirm(l10n.coachingRemoveAthleteTitle,
        l10n.coachingRemoveAthleteBody(name), l10n.coachingRemove);
    if (ok != true) return;
    try {
      await widget.api.endCoachLink(link.id);
      if (!mounted) return;
      setState(
          () => _athletes = _athletes.where((a) => a.id != link.id).toList());
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.coachingRemoveAthleteError('$e'));
    }
  }

  Future<void> _leaveCoach(CoachAthleteLink link) async {
    final l10n = AppLocalizations.of(context);
    final name = link.displayName ?? l10n.coachingThisCoach;
    final ok = await _confirm(l10n.coachingLeaveCoachTitle,
        l10n.coachingLeaveCoachBody(name), l10n.coachingLeave);
    if (ok != true) return;
    try {
      await widget.api.endCoachLink(link.id);
      if (!mounted) return;
      setState(() => _coaches = _coaches.where((c) => c.id != link.id).toList());
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.coachingEndLinkError('$e'));
    }
  }

  Future<bool?> _confirm(String title, String body, String confirmLabel) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.coachingCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  String _sinceLabel(DateTime? dt) {
    if (dt == null) return '—';
    return formatDateMed(dt, activeLocaleTag);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.coachingTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(l10n.coachingLede,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                  const SizedBox(height: 20),
                  if (_roster.isNotEmpty) ...[
                    _rosterCard(l10n),
                    const SizedBox(height: 16),
                  ],
                  _athletesCard(l10n),
                  const SizedBox(height: 16),
                  _coachesCard(l10n),
                ],
              ),
            ),
    );
  }

  Widget _rosterCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    // Risk-first, then most-stale last-run first, so the athletes who need
    // attention float to the top (mirrors the web roster sort default).
    const rank = {
      InjuryRiskBand.high: 4,
      InjuryRiskBand.elevated: 3,
      InjuryRiskBand.optimal: 2,
      InjuryRiskBand.low: 1,
      InjuryRiskBand.insufficient: 0,
    };
    final rows = [..._roster];
    rows.sort((a, b) {
      final byRisk = (rank[injuryRiskBand(b.loadAcute, b.loadChronic)] ?? 0) -
          (rank[injuryRiskBand(a.loadAcute, a.loadChronic)] ?? 0);
      if (byRisk != 0) return byRisk;
      final aMs = a.lastRunAt?.millisecondsSinceEpoch ?? 0;
      final bMs = b.lastRunAt?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachingRosterTitle,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(l10n.coachingRosterSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 8),
            for (final r in rows) _rosterRow(r, unit, l10n),
          ],
        ),
      ),
    );
  }

  Widget _rosterRow(CoachRosterRow r, DistanceUnit unit, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final band = injuryRiskBand(r.loadAcute, r.loadChronic);
    final lastRun = r.lastRunAt == null
        ? l10n.coachingRosterNeverRun
        : formatDateShort(r.lastRunAt!, activeLocaleTag);
    final plan = r.activePlanId == null
        ? l10n.coachingRosterNoPlan
        : '${r.planCompletionPct}%';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(child: Text(_initial(r.displayName))),
      title: Text(r.displayName ?? l10n.coachingRunner,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$lastRun · ${UnitFormat.distance(r.distance7dM, unit)} · $plan',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: _riskChip(band, l10n),
      onTap: () => _openAthleteById(r.athleteId, r.displayName),
    );
  }

  Widget _riskChip(InjuryRiskBand band, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, String label) = switch (band) {
      InjuryRiskBand.high => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          l10n.coachingRosterRiskHigh
        ),
      InjuryRiskBand.elevated => (
          const Color(0xFFFDE9C8),
          const Color(0xFFB45309),
          l10n.coachingRosterRiskElevated
        ),
      InjuryRiskBand.optimal => (
          const Color(0xFFD9F2E0),
          const Color(0xFF15803D),
          l10n.coachingRosterRiskOptimal
        ),
      InjuryRiskBand.low => (
          const Color(0xFFDCE8FB),
          const Color(0xFF1D4ED8),
          l10n.coachingRosterRiskLow
        ),
      InjuryRiskBand.insufficient => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          l10n.coachingRosterRiskInsufficient
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  void _openAthleteById(String athleteId, String? displayName) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachingAthleteScreen(
          api: widget.api,
          preferences: widget.preferences,
          athleteId: athleteId,
          displayName: displayName,
          acceptedAt: null,
        ),
      ),
    );
  }

  Widget _athletesCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      Text(l10n.coachingMyAthletes,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(l10n.coachingMyAthletesSub,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _minting ? null : _mintInvite,
                  child: Text(_minting
                      ? l10n.coachingCreating
                      : l10n.coachingInviteAnAthlete),
                ),
              ],
            ),
            if (_pending.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final inv in _pending) _pendingRow(inv, l10n),
            ],
            const SizedBox(height: 8),
            if (_athletes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.coachingNoAthletes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              )
            else
              for (final a in _athletes) _athleteRow(a, l10n),
          ],
        ),
      ),
    );
  }

  Widget _pendingRow(PendingCoachInvite inv, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
        ),
        leading: const Icon(Icons.link),
        title: Text(l10n.coachingPendingInvite),
        subtitle: Text(l10n.coachingPendingInviteSub(_sinceLabel(inv.createdAt))),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.coachingCopyLink,
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => _copyLink(inv.inviteToken),
            ),
            IconButton(
              tooltip: l10n.coachingShareLink,
              icon: const Icon(Icons.ios_share),
              onPressed: () => _shareLink(inv.inviteToken),
            ),
            IconButton(
              tooltip: l10n.coachingRevoke,
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: () => _revoke(inv),
            ),
          ],
        ),
      ),
    );
  }

  Widget _athleteRow(CoachAthleteLink a, AppLocalizations l10n) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(child: Text(_initial(a.displayName))),
      title: Text(a.displayName ?? l10n.coachingRunner,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.coachingCoachingSince(_sinceLabel(a.acceptedAt))),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'review') {
            _openAthlete(a);
          } else if (v == 'remove') {
            _removeAthlete(a);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'review', child: Text(l10n.coachingReview)),
          PopupMenuItem(value: 'remove', child: Text(l10n.coachingRemove)),
        ],
      ),
      onTap: () => _openAthlete(a),
    );
  }

  void _openAthlete(CoachAthleteLink a) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachingAthleteScreen(
          api: widget.api,
          preferences: widget.preferences,
          athleteId: a.userId,
          displayName: a.displayName,
          acceptedAt: a.acceptedAt,
        ),
      ),
    );
  }

  Widget _coachesCard(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.coachingMyCoaches,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(l10n.coachingMyCoachesSub,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 8),
            if (_coaches.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(l10n.coachingNoCoaches,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              )
            else
              for (final c in _coaches)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(child: Text(_initial(c.displayName))),
                  title: Text(c.displayName ?? l10n.coachingCoach,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text(l10n.coachingLinkedSince(_sinceLabel(c.acceptedAt))),
                  trailing: OutlinedButton(
                    onPressed: () => _leaveCoach(c),
                    child: Text(l10n.coachingLeave),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static String _initial(String? name) {
    final n = name?.trim() ?? '';
    return n.isEmpty ? '?' : n.substring(0, 1).toUpperCase();
  }
}

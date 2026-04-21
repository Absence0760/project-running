import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../recurrence.dart';
import '../social_service.dart';
import '../widgets/error_state.dart';

class EventDetailScreen extends StatefulWidget {
  final SocialService social;
  final String clubSlug;
  final String eventId;
  const EventDetailScreen({
    super.key,
    required this.social,
    required this.clubSlug,
    required this.eventId,
  });

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  EventView? _event;
  ClubView? _club;
  List<AttendeeView> _attendees = const [];
  List<EventResultView> _results = const [];
  DateTime? _activeInstance;
  List<DateTime> _instances = const [];
  bool _loading = true;
  bool _busy = false;
  bool _submittingResult = false;
  String? _loadError;

  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final clubFut =
          widget.social.fetchClubBySlug(widget.clubSlug);
      final eventFut = widget.social.fetchEventById(widget.eventId);
      final headResults = await Future.wait([clubFut, eventFut])
          .timeout(kBackendLoadTimeout);
      final club = headResults[0] as ClubView?;
      final event = headResults[1] as EventView?;
      if (event == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _activeInstance ??= event.nextInstanceStart;
      final now = DateTime.now();
      final horizon = now.add(const Duration(days: 120));
      final instances = expandInstances(
        event.toRecurrence(), now, horizon, max: 6,
      );
      final bodyResults = await Future.wait([
        widget.social.fetchAttendees(event.row.id, _activeInstance!),
        widget.social.fetchEventResults(event.row.id, _activeInstance!),
      ]).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _event = event;
        _club = club;
        _attendees = bodyResults[0] as List<AttendeeView>;
        _results = bodyResults[1] as List<EventResultView>;
        _instances = instances;
        _loading = false;
      });
      if (_channel == null && club != null) {
        _channel = widget.social.subscribeToEvent(
          event.row.id,
          club.row.id,
          _onRealtimeChange,
        );
      }
    } on TimeoutException catch (e) {
      debugPrint('EventDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Connection timed out. Check your network and try again.';
        });
      }
    } catch (e, s) {
      debugPrint('EventDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Couldn\'t load this event. Tap retry to try again.';
        });
      }
    }
  }

  void _onRealtimeChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      widget.social.unsubscribe(channel);
    }
    super.dispose();
  }

  Future<void> _pickInstance(DateTime dt) async {
    setState(() => _activeInstance = dt);
    final e = _event;
    if (e == null) return;
    final attendees = await widget.social.fetchAttendees(e.row.id, dt);
    final results = await widget.social.fetchEventResults(e.row.id, dt);
    if (mounted) {
      setState(() {
        _attendees = attendees;
        _results = results;
      });
    }
  }

  Future<void> _submitMyTime() async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _submittingResult) return;
    setState(() => _submittingResult = true);
    try {
      final picked = await showModalBottomSheet<_SubmitResultChoice>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _SubmitTimeSheet(social: widget.social),
      );
      if (picked == null) return;
      await widget.social.submitEventResult(
        eventId: e.row.id,
        instance: inst,
        durationS: picked.durationS,
        distanceM: picked.distanceM,
        runId: picked.runId,
        finisherStatus: picked.finisherStatus,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Result submitted.')),
        );
      }
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submit failed: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingResult = false);
    }
  }

  Future<void> _removeMyResult() async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null) return;
    await widget.social.removeEventResult(e.row.id, inst);
    await _load();
  }

  Future<void> _rsvp(String status) async {
    final e = _event;
    final inst = _activeInstance;
    if (e == null || inst == null || _busy) return;
    setState(() => _busy = true);
    try {
      // If user taps the same status they already have for the NEXT instance,
      // clear it. Otherwise (or for non-next instances) write the RSVP.
      final isSameNext = inst == e.nextInstanceStart && e.viewerRsvp == status;
      if (isSameNext) {
        await widget.social.clearRsvp(e.row.id, inst);
      } else {
        await widget.social.rsvpEvent(e.row.id, status, inst);
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorState(message: _loadError!, onRetry: _load),
      );
    }
    final e = _event;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Event not found.')),
      );
    }
    final desc = describeRecurrence(e.freq, e.byday);
    final active = _activeInstance!;
    final isMember = _club?.isMember == true;

    return Scaffold(
      appBar: AppBar(title: Text(e.row.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (e.freq != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.autorenew, size: 14,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    desc.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16,
                  color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text(
                fmtEventDate(active),
                style: theme.textTheme.titleMedium,
              ),
              if (e.row.durationMin != null) ...[
                const SizedBox(width: 6),
                Text(
                  '· ${e.row.durationMin} min',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
          if (e.row.meetLabel != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.place, size: 16,
                    color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(child: Text(e.row.meetLabel!)),
              ],
            ),
          ],
          if (e.row.description != null && e.row.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(e.row.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          if (_instances.length > 1) ...[
            Text(
              'PICK AN OCCURRENCE',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final dt in _instances)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(_shortDate(dt)),
                    selected: dt == _activeInstance,
                    onSelected: (_) => _pickInstance(dt),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          _buildRsvpRow(theme, e),
          if (e.row.distanceM != null || e.row.paceTargetSec != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (e.row.distanceM != null) ...[
                  _metric(theme, 'Distance',
                      '${fmtKm(e.row.distanceM!)} km'),
                  const SizedBox(width: 24),
                ],
                if (e.row.paceTargetSec != null)
                  _metric(theme, 'Target pace',
                      fmtPace(e.row.paceTargetSec!)),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'ATTENDEES (${_attendees.length})',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          if (_attendees.isEmpty)
            Text(
              'No RSVPs yet — be the first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in _attendees)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: HSLColor.fromAHSL(
                              1, hashHue(a.userId).toDouble(), 0.5, 0.55,
                            ).toColor(),
                          ),
                          child: Text(
                            initialFor(a.displayName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(a.displayName ?? 'Member',
                            style: theme.textTheme.bodySmall),
                        if (a.status != 'going') ...[
                          const SizedBox(width: 4),
                          Text(
                            '(${a.status})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
          _ResultsSection(
            results: _results,
            myUserId: Supabase.instance.client.auth.currentUser?.id,
            submitting: _submittingResult,
            onSubmit: _submitMyTime,
            onRemove: _removeMyResult,
          ),
          if (isMember) ...[
            const SizedBox(height: 24),
            _AdminUpdateComposer(
              onSubmit: (body) async {
                await widget.social.createPost(
                  clubId: _club!.row.id,
                  eventId: e.row.id,
                  eventInstanceStart: e.freq != null ? active : null,
                  body: body,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Update posted to the club feed.')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRsvpRow(ThemeData theme, EventView e) {
    final active = _activeInstance!;
    final isNext = active == e.nextInstanceStart;
    final current = isNext ? e.viewerRsvp : null;

    Widget chip(String value, String label) {
      final selected = current == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: selected
            ? FilledButton(
                onPressed: _busy ? null : () => _rsvp(value),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: _busy ? null : () => _rsvp(value),
                child: Text(label),
              ),
      );
    }

    return Row(
      children: [
        chip('going', "I'm in"),
        chip('maybe', 'Maybe'),
        chip('declined', "Can't make it"),
      ],
    );
  }

  Widget _metric(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 0.6,
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _AdminUpdateComposer extends StatefulWidget {
  final Future<void> Function(String body) onSubmit;
  const _AdminUpdateComposer({required this.onSubmit});

  @override
  State<_AdminUpdateComposer> createState() => _AdminUpdateComposerState();
}

class _AdminUpdateComposerState extends State<_AdminUpdateComposer> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(body);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POST AN UPDATE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            maxLength: 1200,
            decoration: const InputDecoration(
              hintText: "Weather call? Meeting at a different spot?",
              border: InputBorder.none,
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Post update'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A choice returned from the submit-time bottom sheet. Captures both the
/// "pick an existing run" path (with [runId]) and the "record a DNF/DNS"
/// path (no run, manual finisher_status).
class _SubmitResultChoice {
  final String? runId;
  final int durationS;
  final double distanceM;
  final String finisherStatus;
  const _SubmitResultChoice({
    required this.runId,
    required this.durationS,
    required this.distanceM,
    required this.finisherStatus,
  });
}

class _ResultsSection extends StatelessWidget {
  final List<EventResultView> results;
  final String? myUserId;
  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onRemove;
  const _ResultsSection({
    required this.results,
    required this.myUserId,
    required this.submitting,
    required this.onSubmit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMine = myUserId != null && results.any((r) => r.userId == myUserId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text('Results', style: theme.textTheme.titleSmall),
            const Spacer(),
            if (hasMine)
              TextButton(
                onPressed: onRemove,
                child: const Text('Remove mine'),
              )
            else
              FilledButton.tonalIcon(
                onPressed: submitting ? null : onSubmit,
                icon: const Icon(Icons.timer_outlined, size: 16),
                label: Text(submitting ? 'Submitting…' : 'Submit my time'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          Text(
            'No results yet. Submit your time after the event and others will see it here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        else
          ...results.map((r) => _ResultRow(row: r, isMe: r.userId == myUserId)),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final EventResultView row;
  final bool isMe;
  const _ResultRow({required this.row, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rank = row.rank?.toString() ?? '—';
    final time = _formatDuration(row.durationS);
    final distKm = (row.distanceM / 1000).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              rank,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: row.finisherStatus == 'finished'
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    row.displayName ?? 'Runner',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isMe ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Text('(you)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      )),
                ],
                if (row.finisherStatus != 'finished') ...[
                  const SizedBox(width: 6),
                  Text(
                    row.finisherStatus.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (row.finisherStatus == 'finished') ...[
            Text(time,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
            const SizedBox(width: 10),
            Text('$distKm km',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                )),
          ],
        ],
      ),
    );
  }

  static String _formatDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

/// Bottom sheet that lets a user attach one of their recent runs, or
/// record a DNF/DNS without a run.
class _SubmitTimeSheet extends StatefulWidget {
  final SocialService social;
  const _SubmitTimeSheet({required this.social});

  @override
  State<_SubmitTimeSheet> createState() => _SubmitTimeSheetState();
}

class _SubmitTimeSheetState extends State<_SubmitTimeSheet> {
  List<RecentRunRow> _runs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final runs = await widget.social.fetchRecentRuns(limit: 20);
    if (mounted) setState(() { _runs = runs; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit your time', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Pick a run to attach, or record a DNF / DNS.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_runs.isEmpty)
              Text(
                'No recent runs found. Record a run first, then come back.',
                style: theme.textTheme.bodySmall,
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _runs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _runs[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${_dateLabel(r.startedAt)} · ${(r.distanceM / 1000).toStringAsFixed(2)} km',
                      ),
                      subtitle: Text(
                        '${_ResultRow._formatDuration(r.durationS)} · ${r.activityType}',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => Navigator.of(context).pop(
                        _SubmitResultChoice(
                          runId: r.id,
                          durationS: r.durationS,
                          distanceM: r.distanceM,
                          finisherStatus: 'finished',
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const _SubmitResultChoice(
                      runId: null,
                      durationS: 0,
                      distanceM: 0,
                      finisherStatus: 'dnf',
                    ),
                  ),
                  child: const Text('Record DNF'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const _SubmitResultChoice(
                      runId: null,
                      durationS: 0,
                      distanceM: 0,
                      finisherStatus: 'dns',
                    ),
                  ),
                  child: const Text('Record DNS'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime dt) {
    final local = dt.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }
}

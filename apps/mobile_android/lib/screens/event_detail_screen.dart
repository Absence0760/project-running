import 'package:flutter/material.dart';

import '../recurrence.dart';
import '../social_service.dart';

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
  DateTime? _activeInstance;
  List<DateTime> _instances = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final club = await widget.social.fetchClubBySlug(widget.clubSlug);
    final event = await widget.social.fetchEventById(widget.eventId);
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
    final attendees = await widget.social.fetchAttendees(
      event.row.id, _activeInstance!,
    );
    if (!mounted) return;
    setState(() {
      _event = event;
      _club = club;
      _attendees = attendees;
      _instances = instances;
      _loading = false;
    });
  }

  Future<void> _pickInstance(DateTime dt) async {
    setState(() => _activeInstance = dt);
    final e = _event;
    if (e == null) return;
    final attendees = await widget.social.fetchAttendees(e.row.id, dt);
    if (mounted) setState(() => _attendees = attendees);
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
    final e = _event;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Event not found.')),
      );
    }
    final desc = describeRecurrence(e.freq, e.byday);
    final active = _activeInstance!;
    final isAdmin = _club?.isAdmin == true;

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
          if (isAdmin) ...[
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

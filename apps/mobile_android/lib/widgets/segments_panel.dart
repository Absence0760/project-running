import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import 'top_banner.dart';

/// Route-detail segments panel: lists every segment on the parent
/// route, expands each row to a leaderboard on tap, and (for the
/// route owner) hosts a "New segment" form. Mirrors the web
/// `SegmentsPanel.svelte` component (decisions §37).
class SegmentsPanel extends StatefulWidget {
  final ApiClient api;
  final String routeId;
  final double routeDistanceM;
  final bool canCreate;

  const SegmentsPanel({
    super.key,
    required this.api,
    required this.routeId,
    required this.routeDistanceM,
    required this.canCreate,
  });

  @override
  State<SegmentsPanel> createState() => _SegmentsPanelState();
}

class _SegmentsPanelState extends State<SegmentsPanel> {
  bool _loading = true;
  List<SegmentRow> _segments = const [];
  final Map<String, List<SegmentLeaderboardEntry>?> _leaderboards = {};
  String? _openSegmentId;
  bool _showCreate = false;
  bool _creating = false;

  late final TextEditingController _nameCtrl = TextEditingController();
  late final TextEditingController _startCtrl = TextEditingController(text: '0');
  late final TextEditingController _endCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _endCtrl.text = (widget.routeDistanceM > 1000
            ? 1000
            : widget.routeDistanceM.round())
        .toString();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final segs = await widget.api.fetchSegmentsForRoute(widget.routeId);
      if (!mounted) return;
      setState(() {
        _segments = segs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleLeaderboard(SegmentRow seg) async {
    if (_openSegmentId == seg.id) {
      setState(() => _openSegmentId = null);
      return;
    }
    setState(() => _openSegmentId = seg.id);
    if (_leaderboards.containsKey(seg.id)) return;
    setState(() => _leaderboards[seg.id] = null);
    try {
      final entries =
          await widget.api.fetchSegmentLeaderboardWithAthletes(seg.id);
      if (!mounted) return;
      setState(() => _leaderboards[seg.id] = entries);
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaderboards[seg.id] = const []);
    }
  }

  Future<void> _submitCreate() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final start = double.tryParse(_startCtrl.text) ?? 0;
    final end = double.tryParse(_endCtrl.text) ?? 0;
    if (end <= start) {
      _toast('End must be greater than start');
      return;
    }
    if (end - start < 100) {
      _toast('Segment must be at least 100 m');
      return;
    }
    setState(() => _creating = true);
    try {
      final seg = await widget.api.createSegment(
        routeId: widget.routeId,
        name: name,
        startDistanceM: start,
        endDistanceM: end,
      );
      if (!mounted) return;
      final next = [..._segments, seg]
        ..sort((a, b) => a.startDistanceM.compareTo(b.startDistanceM));
      setState(() {
        _segments = next;
        _showCreate = false;
        _creating = false;
        _nameCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      _toast('Could not create segment: $e');
    }
  }

  Future<void> _confirmDelete(SegmentRow seg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete segment?'),
        content: Text('“${seg.name}” will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteSegment(seg.id);
      if (!mounted) return;
      setState(() {
        _segments = _segments.where((s) => s.id != seg.id).toList();
        _leaderboards.remove(seg.id);
        if (_openSegmentId == seg.id) _openSegmentId = null;
      });
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    showTopBanner(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Segments', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (widget.canCreate)
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showCreate = !_showCreate),
                  icon: Icon(_showCreate ? Icons.close : Icons.add, size: 18),
                  label: Text(_showCreate ? 'Cancel' : 'New segment'),
                ),
            ],
          ),
          if (_showCreate) ...[
            const SizedBox(height: 8),
            _CreateForm(
              nameCtrl: _nameCtrl,
              startCtrl: _startCtrl,
              endCtrl: _endCtrl,
              creating: _creating,
              routeDistanceM: widget.routeDistanceM,
              onSubmit: _submitCreate,
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Loading segments…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else if (_segments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No segments on this route yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final seg in _segments)
              _SegmentTile(
                seg: seg,
                expanded: _openSegmentId == seg.id,
                leaderboard: _leaderboards[seg.id],
                viewerId: widget.api.userId,
                canDelete: widget.canCreate,
                onTap: () => _toggleLeaderboard(seg),
                onDelete: () => _confirmDelete(seg),
              ),
        ],
      ),
    );
  }
}

class _CreateForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController startCtrl;
  final TextEditingController endCtrl;
  final bool creating;
  final double routeDistanceM;
  final VoidCallback onSubmit;

  const _CreateForm({
    required this.nameCtrl,
    required this.startCtrl,
    required this.endCtrl,
    required this.creating,
    required this.routeDistanceM,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final hint = 'route is ${routeDistanceM.round()} m';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameCtrl,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Climb of doom',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Start (m)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: endCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'End (m)',
                      helperText: hint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: creating ? null : onSubmit,
                child: creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  final SegmentRow seg;
  final bool expanded;
  final List<SegmentLeaderboardEntry>? leaderboard;
  final String? viewerId;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SegmentTile({
    required this.seg,
    required this.expanded,
    required this.leaderboard,
    required this.viewerId,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final length =
        seg.lengthM ?? (seg.endDistanceM - seg.startDistanceM);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(seg.name, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmt(length)}  ·  ${_fmt(seg.startDistanceM)}–${_fmt(seg.endDistanceM)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'Delete segment',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: onDelete,
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _Leaderboard(
                entries: leaderboard,
                viewerId: viewerId,
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(2)} km';
    return '${m.round()} m';
  }
}

class _Leaderboard extends StatelessWidget {
  final List<SegmentLeaderboardEntry>? entries;
  final String? viewerId;

  const _Leaderboard({required this.entries, required this.viewerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (entries == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Loading…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (entries!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No efforts yet — be the first to run this segment.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in entries!) _LeaderboardRow(entry: e, viewerId: viewerId),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final SegmentLeaderboardEntry entry;
  final String? viewerId;
  const _LeaderboardRow({required this.entry, required this.viewerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isViewer = viewerId != null && entry.effort.userId == viewerId;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isViewer
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#${entry.rank}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _MiniAvatar(
            displayName: entry.athlete.displayName,
            avatarUrl: entry.athlete.avatarUrl,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.athlete.displayName ?? 'Runner',
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            _fmtTime(entry.effort.timeSeconds),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(double seconds) {
    final total = seconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _MiniAvatar extends StatelessWidget {
  final String? displayName;
  final String? avatarUrl;
  const _MiniAvatar({this.displayName, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letter = (displayName?.isNotEmpty ?? false)
        ? displayName![0].toUpperCase()
        : '?';
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary,
        image: avatarUrl != null && avatarUrl!.isNotEmpty
            ? DecorationImage(
                // Avatar renders at 24 dp; decode at ~3× to keep
                // memory bounded in segment leaderboards.
                image: ResizeImage(
                  NetworkImage(avatarUrl!),
                  width: 72,
                  height: 72,
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              letter,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

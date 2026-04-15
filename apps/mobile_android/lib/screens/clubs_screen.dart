import 'package:flutter/material.dart';

import '../social_service.dart';
import 'club_detail_screen.dart';

class ClubsScreen extends StatefulWidget {
  final SocialService social;
  const ClubsScreen({super.key, required this.social});

  @override
  State<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends State<ClubsScreen> {
  // Default to "My clubs" — returning users want to see the clubs they're
  // already in first. Fresh users with no memberships get an empty state
  // that points them at Browse.
  int _tab = 1; // 0 = Browse, 1 = My clubs
  bool _loading = true;
  List<ClubView> _browse = const [];
  List<ClubView> _mine = const [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.social.addListener(_onChange);
    _load();
  }

  void _onChange() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.social.browseClubs(query: _searchCtrl.text),
        widget.social.fetchMyClubs(),
      ]);
      if (!mounted) return;
      setState(() {
        _browse = results[0];
        _mine = results[1];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    widget.social.removeListener(_onChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _tab == 0 ? _browse : _mine;

    // Height budget: segmented button (~48) + 8px below. Plus the search
    // field (~48) when we're on the Browse tab. Sizing this conditionally
    // avoids both an empty band on "My clubs" and a 12px overflow stripe
    // on "Browse" that otherwise show up as a visible glitch when tabbing.
    final bottomHeight = _tab == 0 ? 108.0 : 56.0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clubs'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(bottomHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Browse')),
                    ButtonSegment(value: 1, label: Text('My clubs')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              if (_tab == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'Search by name or location',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? _Empty(tab: _tab)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _ClubTile(
                      view: list[i],
                      onTap: () async {
                        await Navigator.of(ctx).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubDetailScreen(
                              social: widget.social,
                              slug: list[i].row.slug,
                            ),
                          ),
                        );
                        _load();
                      },
                    ),
                  ),
                ),
    );
  }
}

class _ClubTile extends StatelessWidget {
  final ClubView view;
  final VoidCallback onTap;
  const _ClubTile({required this.view, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = view.row;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            _Avatar(seed: c.id, label: initialFor(c.name), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!(c.isPublic ?? true))
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: Text(
                            'PRIVATE',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              letterSpacing: 0.8,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (c.locationLabel != null && c.locationLabel!.isNotEmpty)
                    Row(
                      children: [
                        Icon(Icons.place, size: 13,
                            color: theme.colorScheme.outline),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            c.locationLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.group, size: 14,
                          color: theme.colorScheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        '${view.memberCount} member${view.memberCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      if (view.viewerRole != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            view.viewerRole!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final int tab;
  const _Empty({required this.tab});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab == 0 ? Icons.groups : Icons.person_add_alt_1,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              tab == 0
                  ? 'No clubs match that search.'
                  : "You haven't joined a club yet.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              tab == 0
                  ? 'Try a different name or location.'
                  : 'Head to Browse to find one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String seed;
  final String label;
  final double size;
  const _Avatar({required this.seed, required this.label, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final hue = hashHue(seed);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HSLColor.fromAHSL(1, hue.toDouble(), 0.5, 0.55).toColor(),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

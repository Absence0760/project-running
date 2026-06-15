import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';
import 'profile_screen.dart';

/// People discovery — name search + "suggested" people pulled from the
/// viewer's clubs. Mirrors `apps/web/src/lib/components/SocialPeople.svelte`
/// + the People tab on web's `/social` hub. Reached from the Clubs and
/// Feed AppBars on mobile (mobile has no top-level "Social" tab — the
/// bottom-nav Clubs entry hosts the social discovery entry point).
class PeopleScreen extends StatefulWidget {
  final ApiClient api;
  /// Embedded mode skips the Scaffold/AppBar wrapping — the search
  /// field that's normally hosted in the AppBar moves inline at the
  /// top of the body. Used by SocialScreen for the People tab.
  final bool embedded;

  const PeopleScreen({super.key, required this.api, this.embedded = false});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;
  int _searchGen = 0;

  bool _loadingSuggestions = true;
  bool _searching = false;
  List<PeopleSuggestion> _suggestions = const [];
  List<PeopleSuggestion> _results = const [];
  String _query = '';

  final Set<String> _rowBusy = <String>{};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final s = await widget.api.fetchSuggestedPeople(limit: 12);
      if (!mounted) return;
      setState(() {
        _suggestions = s;
        _loadingSuggestions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSuggestions = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() => _query = trimmed);
    if (trimmed.isEmpty) {
      _searchGen++;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final term = _query;
    final gen = ++_searchGen;
    if (term.isEmpty) return;
    setState(() => _searching = true);
    try {
      final next = await widget.api.searchPeople(term, limit: 20);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = next;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen) return;
      setState(() => _searching = false);
    }
  }

  void _clearSearch() {
    _searchCtl.clear();
    _onSearchChanged('');
  }

  Future<void> _toggleFollow(PeopleSuggestion target) async {
    if (_rowBusy.contains(target.id)) return;
    final wasFollowing = target.viewerFollows;
    setState(() {
      _rowBusy.add(target.id);
      _flipFollow(target.id, !wasFollowing);
    });
    try {
      if (wasFollowing) {
        await widget.api.unfollowUser(target.id);
      } else {
        await widget.api.followUser(target.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _flipFollow(target.id, wasFollowing));
      showTopBanner(
        context, AppLocalizations.of(context).peopleFollowFailedBanner(e));
    } finally {
      if (mounted) setState(() => _rowBusy.remove(target.id));
    }
  }

  void _flipFollow(String id, bool viewerFollows) {
    _results = _results
        .map((p) => p.id == id ? _withFollow(p, viewerFollows) : p)
        .toList();
    _suggestions = _suggestions
        .map((p) => p.id == id ? _withFollow(p, viewerFollows) : p)
        .toList();
  }

  static PeopleSuggestion _withFollow(PeopleSuggestion p, bool follows) =>
      PeopleSuggestion(
        id: p.id,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        publicRunsCount: p.publicRunsCount,
        sharedClubs: p.sharedClubs,
        viewerFollows: follows,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasQuery = _query.isNotEmpty;
    final visible = hasQuery ? _results : _suggestions;
    final searchField = Semantics(
      textField: true,
      label: l10n.peopleSearchHint,
      child: TextField(
      controller: _searchCtl,
      autofocus: !widget.embedded,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.titleMedium,
      decoration: InputDecoration(
        hintText: l10n.peopleSearchHint,
        prefixIcon: widget.embedded
            ? const Icon(Icons.search, size: 20)
            : null,
        border: widget.embedded
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(12))
            : InputBorder.none,
        isDense: widget.embedded,
        suffixIcon: hasQuery
            ? IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l10n.peopleClearSearchTooltip,
                onPressed: _clearSearch,
              )
            : null,
      ),
      onChanged: _onSearchChanged,
    ),
    );
    final body = SafeArea(
      top: false,
      child: CustomScrollView(
        slivers: [
          if (widget.embedded)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: searchField,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                hasQuery
                    ? l10n.peopleSearchResultsHeader
                    : l10n.peopleSuggestedHeader,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          if (hasQuery && _searching)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (hasQuery && _results.isEmpty)
            SliverToBoxAdapter(
              child: _Empty(
                icon: Icons.search_off,
                title: l10n.peopleEmptySearchTitle(_query),
                body: l10n.peopleEmptySearchBody,
              ),
            )
          else if (!hasQuery && _loadingSuggestions)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!hasQuery && _suggestions.isEmpty)
            SliverToBoxAdapter(
              child: _Empty(
                icon: Icons.groups_outlined,
                title: l10n.peopleEmptySuggestionsTitle,
                body: l10n.peopleEmptySuggestionsBody,
              ),
            )
          else
            SliverList.separated(
              itemBuilder: (_, i) => _PersonRow(
                person: visible[i],
                busy: _rowBusy.contains(visible[i].id),
                onToggleFollow: () => _toggleFollow(visible[i]),
                onOpenProfile: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileScreen(
                        api: widget.api,
                        userId: visible[i].id,
                      ),
                    ),
                  );
                },
              ),
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: visible.length,
            ),
        ],
      ),
    );
    if (widget.embedded) {
      return body;
    }
    return Scaffold(
      appBar: AppBar(
        title: searchField,
        actions: [
          if (hasQuery)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l10n.peopleClearSearchTooltip,
              onPressed: _clearSearch,
            ),
        ],
      ),
      body: body,
    );
  }
}

class _PersonRow extends StatelessWidget {
  final PeopleSuggestion person;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpenProfile;

  const _PersonRow({
    required this.person,
    required this.busy,
    required this.onToggleFollow,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final initial = (person.displayName?.isNotEmpty ?? false)
        ? person.displayName![0].toUpperCase()
        : '?';
    final metaParts = <String>[
      l10n.peoplePublicRunCount(person.publicRunsCount),
      if (person.sharedClubs > 0) l10n.peopleSharedClubsCount(person.sharedClubs),
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary,
        foregroundImage: (person.avatarUrl != null && person.avatarUrl!.isNotEmpty)
            ? NetworkImage(person.avatarUrl!)
            : null,
        child: Text(
          initial,
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(person.displayName ?? l10n.peopleFallbackDisplayName),
      subtitle: Text(metaParts.join(' · ')),
      trailing: FilledButton.tonal(
        onPressed: busy ? null : onToggleFollow,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
        ),
        child: Text(person.viewerFollows
            ? l10n.peopleFollowingButton
            : l10n.peopleFollowButton),
      ),
      onTap: onOpenProfile,
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

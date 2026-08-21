import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar;

import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';
import '../nearby.dart';
import '../nearby_flag.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../widgets/error_state.dart';
import '../widgets/sign_in_required_state.dart';
import '../widgets/top_banner.dart';
import 'profile_screen.dart';

/// People discovery — name search + "suggested" people pulled from the
/// viewer's clubs. Mirrors `apps/web/src/lib/components/SocialPeople.svelte`
/// + the People tab on web's `/social` hub. Mounted as the **People**
/// sub-tab of `social_screen.dart` (the Social bottom-nav destination); the
/// standalone Scaffold path is kept for any direct caller.
///
/// Also hosts the opt-in coarse-location "runners nearby" list (issue #466),
/// which renders only while the default-off `ENABLE_NEARBY_RUNNERS` deploy gate
/// is on. With the gate off the surface is wholly inert: no heading, no empty
/// state, and no `discoverable_runners_near` call.
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
  bool _searchError = false;
  bool _suggestionsError = false;
  bool _signedOut = false;
  List<PeopleSuggestion> _suggestions = const [];
  List<PeopleSuggestion> _results = const [];
  List<NearbyRunner> _nearby = const [];
  bool _loadingNearby = false;
  bool _nearbyError = false;
  String _query = '';

  /// Read once per mount rather than per build so a mid-session env mutation
  /// can't leave the surface half-rendered against a half-loaded list.
  final bool _nearbyGate = nearbyRunnersGate;

  final Set<String> _rowBusy = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.api.userId != null) {
      _loadSuggestions();
      if (_nearbyGate) _loadNearby();
    }
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
        _suggestionsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isSignedOutError(e)) {
          _signedOut = true;
        } else {
          _suggestionsError = true;
        }
        _loadingSuggestions = false;
      });
    }
  }

  void _retrySuggestions() {
    setState(() {
      _loadingSuggestions = true;
      _suggestionsError = false;
    });
    _loadSuggestions();
  }

  /// Only ever called behind [_nearbyGate] — the RPC must not be reached at
  /// all while the sign-off gate is off.
  Future<void> _loadNearby() async {
    setState(() {
      _loadingNearby = true;
      _nearbyError = false;
    });
    try {
      final rows = await widget.api.fetchNearbyRunners();
      if (!mounted) return;
      setState(() {
        _nearby = rows;
        _loadingNearby = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isSignedOutError(e)) {
          _signedOut = true;
        } else {
          _nearbyError = true;
        }
        _loadingNearby = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() {
      _query = trimmed;
      _searchError = false;
    });
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
    setState(() {
      _searching = true;
      _searchError = false;
    });
    try {
      final next = await widget.api.searchPeople(term, limit: 20);
      if (!mounted || gen != _searchGen) return;
      setState(() {
        _results = next;
        _searching = false;
      });
    } catch (e) {
      // Surface the failure with a retry affordance instead of silently
      // falling through to the "no matches" empty state — a failed search
      // is not the same as an empty result. Mirrors the sibling Discover
      // tab's ErrorState pattern (and web's search-failed toast). An auth
      // rejection is different again: search_user_profiles is revoked from
      // anon by design, so a retry can never succeed — route it into the
      // sign-in state instead (issue #224).
      if (!mounted || gen != _searchGen) return;
      setState(() {
        if (isSignedOutError(e)) {
          _signedOut = true;
        } else {
          _searchError = true;
        }
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    _searchCtl.clear();
    _onSearchChanged('');
  }

  Future<void> _toggleFollow(String id, bool wasFollowing) async {
    if (_rowBusy.contains(id)) return;
    setState(() {
      _rowBusy.add(id);
      _flipFollow(id, !wasFollowing);
    });
    try {
      if (wasFollowing) {
        await widget.api.unfollowUser(id);
      } else {
        await widget.api.followUser(id);
      }
    } catch (e) {
      if (!mounted) return;
      final signedOut = isSignedOutError(e);
      setState(() {
        _flipFollow(id, wasFollowing);
        if (signedOut) _signedOut = true;
      });
      if (!signedOut) {
        showTopBanner(
          context, AppLocalizations.of(context).peopleFollowFailedBanner(e));
      }
    } finally {
      if (mounted) setState(() => _rowBusy.remove(id));
    }
  }

  void _flipFollow(String id, bool viewerFollows) {
    _results = _results
        .map((p) => p.id == id ? _withFollow(p, viewerFollows) : p)
        .toList();
    _suggestions = _suggestions
        .map((p) => p.id == id ? _withFollow(p, viewerFollows) : p)
        .toList();
    _nearby = _nearby
        .map((p) => p.id == id ? _withFollowNearby(p, viewerFollows) : p)
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

  static NearbyRunner _withFollowNearby(NearbyRunner p, bool follows) =>
      NearbyRunner(
        id: p.id,
        displayName: p.displayName,
        avatarUrl: p.avatarUrl,
        bucket: p.bucket,
        viewerFollows: follows,
      );

  /// The coarse bucket as a label. Only ever the bucket's upper BOUND, formatted
  /// in the runner's own unit — never the exact distance, which the RPC
  /// deliberately never sends.
  static String _bucketLabel(AppLocalizations l10n, int bucket) {
    final bound = nearbyBucketUpperBoundM(bucket);
    return bound == null
        ? l10n.peopleNearbyBeyond(
            formatDistanceForPref(kNearbyBucketBoundsM.last.toDouble()))
        : l10n.peopleNearbyWithin(formatDistanceForPref(bound.toDouble()));
  }

  void _handleSignedIn() {
    if (!mounted) return;
    setState(() {
      _signedOut = false;
      _loadingSuggestions = true;
      _suggestionsError = false;
      _searchError = false;
    });
    _loadSuggestions();
    if (_nearbyGate) _loadNearby();
    if (_query.isNotEmpty) _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // search_user_profiles is granted to authenticated only (privacy
    // opt-out lives in owner-only user_settings), so a signed-out search
    // can only fail — render the sign-in state instead of a search field
    // whose every query dead-ends in a retry loop (issue #224).
    if (widget.api.userId == null || _signedOut) {
      final signedOutBody = SignInRequiredState(
        api: widget.api,
        message: l10n.peopleSignedOutMessage,
        onSignedIn: _handleSignedIn,
      );
      if (widget.embedded) return signedOutBody;
      return Scaffold(
        appBar: AppBar(title: Text(l10n.socialTabPeople)),
        body: signedOutBody,
      );
    }
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
          else if (hasQuery && _searchError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ErrorState(
                  message: l10n.exploreRoutesSearchFailed,
                  onRetry: _runSearch,
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
          else if (!hasQuery && _suggestionsError)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: ErrorState(
                  message: l10n.peopleSuggestionsLoadFailed,
                  onRetry: _retrySuggestions,
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
                onToggleFollow: () =>
                    _toggleFollow(visible[i].id, visible[i].viewerFollows),
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
          // Opt-in coarse-location discovery. Suppressed while a search is
          // active (mirrors SocialPeople.svelte) and entirely absent while the
          // deploy gate is off.
          if (_nearbyGate && !hasQuery) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.peopleNearbyHeader,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.peopleNearbySubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loadingNearby)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_nearbyError)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: ErrorState(
                    message: l10n.peopleNearbyLoadFailed,
                    onRetry: _loadNearby,
                  ),
                ),
              )
            else if (_nearby.isEmpty)
              SliverToBoxAdapter(
                child: _Empty(
                  icon: Icons.near_me_outlined,
                  title: l10n.peopleNearbyEmptyTitle,
                  body: l10n.peopleNearbyEmptyBody,
                ),
              )
            else
              SliverList.separated(
                itemBuilder: (_, i) => _NearbyRow(
                  person: _nearby[i],
                  bucketLabel: _bucketLabel(l10n, _nearby[i].bucket),
                  busy: _rowBusy.contains(_nearby[i].id),
                  onToggleFollow: () => _toggleFollow(
                      _nearby[i].id, _nearby[i].viewerFollows),
                  onOpenProfile: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ProfileScreen(
                          api: widget.api,
                          userId: _nearby[i].id,
                        ),
                      ),
                    );
                  },
                ),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _nearby.length,
              ),
          ],
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
    final metaParts = <String>[
      l10n.peoplePublicRunCount(person.publicRunsCount),
      if (person.sharedClubs > 0) l10n.peopleSharedClubsCount(person.sharedClubs),
    ];
    final handle = person.handle;
    final hasHandle = handle != null && handle.isNotEmpty;
    final subtitle = hasHandle
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '@$handle',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(metaParts.join(' · ')),
            ],
          )
        : Text(metaParts.join(' · '));
    return ListTile(
      isThreeLine: hasHandle,
      leading: IdentityAvatar(
        seed: person.id,
        name: person.displayName,
        size: 40,
        imageUrl: person.avatarUrl,
      ),
      title: Text(person.displayName ?? l10n.peopleFallbackDisplayName),
      subtitle: subtitle,
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

/// A nearby runner's row. Deliberately NOT the same widget as [_PersonRow]:
/// the only thing known about this person's location is a coarse bucket, so the
/// row has no place to put a run count, a shared-club count, or anything a map
/// could pin.
class _NearbyRow extends StatelessWidget {
  final NearbyRunner person;
  final String bucketLabel;
  final bool busy;
  final VoidCallback onToggleFollow;
  final VoidCallback onOpenProfile;

  const _NearbyRow({
    required this.person,
    required this.bucketLabel,
    required this.busy,
    required this.onToggleFollow,
    required this.onOpenProfile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      leading: IdentityAvatar(
        seed: person.id,
        name: person.displayName,
        size: 40,
        imageUrl: person.avatarUrl,
      ),
      title: Text(person.displayName ?? l10n.peopleFallbackDisplayName),
      subtitle: Text(bucketLabel),
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

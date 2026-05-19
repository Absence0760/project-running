import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' hide Route;

import 'package:api_client/api_client.dart';

import '../preferences.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/route_track_preview.dart';
import 'event_detail_screen.dart';
import 'plan_detail_screen.dart';
import 'public_route_screen.dart';
import '../widgets/top_banner.dart';

class ClubDetailScreen extends StatefulWidget {
  final SocialService social;
  final TrainingService training;
  final String slug;
  const ClubDetailScreen({
    super.key,
    required this.social,
    required this.training,
    required this.slug,
  });

  @override
  State<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends State<ClubDetailScreen>
    with SingleTickerProviderStateMixin {
  ClubView? _club;
  List<EventView> _upcoming = const [];
  List<ClubPostView> _posts = const [];
  List<ClubMemberRow> _pending = const [];
  List<TrainingPlanRow> _templates = const [];
  List<cm.Route> _routes = const [];
  bool _loading = true;
  bool _busy = false;
  bool _templatesLoaded = false;
  bool _routesLoaded = false;
  String? _error;
  late final TabController _tabs;
  final _postCtrl = TextEditingController();
  final Map<String, List<ClubPostView>> _threads = {};
  final Map<String, TextEditingController> _replyCtrls = {};

  RealtimeChannel? _channel;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _tabs.addListener(_onTabChanged);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final club = await widget.social
          .fetchClubBySlug(widget.slug)
          .timeout(kBackendLoadTimeout);
      if (club == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final results = await Future.wait<dynamic>([
        widget.social.fetchUpcomingEvents(club.row.id),
        widget.social.fetchClubPosts(club.row.id),
        // Pending requests only meaningful when the viewer is admin.
        // RLS will return [] for non-admins; keep the call simple.
        club.isAdmin
            ? widget.social.fetchPendingRequests(club.row.id)
            : Future.value(const <ClubMemberRow>[]),
      ]).timeout(kBackendLoadTimeout);
      if (!mounted) return;
      setState(() {
        _club = club;
        _upcoming = results[0] as List<EventView>;
        _posts = results[1] as List<ClubPostView>;
        _pending = results[2] as List<ClubMemberRow>;
        _loading = false;
      });
      if (_channel == null) {
        _channel = widget.social.subscribeToClub(club.row.id, _onRealtimeChange);
      }
    } on TimeoutException catch (e) {
      debugPrint('ClubDetailScreen._load timed out: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connection timed out. Check your network and try again.';
        });
      }
    } catch (e, s) {
      debugPrint('ClubDetailScreen._load failed: $e\n$s');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _join() async {
    final c = _club;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final status = await widget.social.joinClub(c.row.id, c.joinPolicy);
      if (status == 'pending' && mounted) {
        showTopBanner(context, 'Request sent to admins.');
      }
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final c = _club;
    if (c == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${c.row.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.social.leaveClub(c.row.id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPost() async {
    final c = _club;
    if (c == null) return;
    final body = _postCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.social.createPost(clubId: c.row.id, body: body);
      _postCtrl.clear();
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleReplies(String postId) async {
    if (_threads[postId] != null) {
      setState(() => _threads.remove(postId));
      return;
    }
    final replies = await widget.social.fetchPostReplies(postId);
    if (!mounted) return;
    setState(() {
      _threads[postId] = replies;
      _replyCtrls.putIfAbsent(postId, () => TextEditingController());
    });
  }

  Future<void> _sendReply(String postId) async {
    final c = _club;
    if (c == null) return;
    final ctrl = _replyCtrls[postId];
    final body = ctrl?.text.trim();
    if (body == null || body.isEmpty) return;
    await widget.social.createPost(
      clubId: c.row.id,
      parentPostId: postId,
      body: body,
    );
    ctrl?.clear();
    final replies = await widget.social.fetchPostReplies(postId);
    if (!mounted) return;
    setState(() => _threads[postId] = replies);
    _load();
  }

  void _onRealtimeChange() {
    // Coalesce bursts so a multi-row change (e.g. cascading delete) triggers
    // one reload, not several.
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
    _tabs.dispose();
    _postCtrl.dispose();
    for (final c in _replyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = _club;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.help_outline, size: 48,
                    color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                const Text(
                  "Couldn't load this club.",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _error != null
                      ? _error!
                      : 'It may have been removed, or your session might need to be refreshed. Try pulling to retry, or sign out and back in from Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(c.row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Report club',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => showReportSheet(
              context,
              api: ApiClient(),
              targetKind: 'club',
              targetId: c.row.id,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Events'),
            Tab(text: 'Members'),
            Tab(text: 'Routes'),
            Tab(text: 'Templates'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildHero(theme, c),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildFeedTab(theme, c),
                _buildEventsTab(theme, c),
                _buildMembersTab(theme, c),
                _buildRoutesTab(theme, c),
                _buildTemplatesTab(theme, c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(ThemeData theme, ClubView c) {
    final cta = _ctaFor(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HSLColor.fromAHSL(
                1, hashHue(c.row.id).toDouble(), 0.55, 0.55).toColor(),
            ),
            child: Text(
              initialFor(c.row.name),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.row.locationLabel != null &&
                    c.row.locationLabel!.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.place, size: 14,
                          color: theme.colorScheme.outline),
                      const SizedBox(width: 3),
                      Text(
                        c.row.locationLabel!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                Text(
                  '${c.memberCount} member${c.memberCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (c.row.description != null && c.row.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      c.row.description!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          cta,
        ],
      ),
    );
  }

  Widget _ctaFor(ClubView c) {
    if (c.viewerStatus == 'pending') {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Request pending'),
      );
    }
    if (!c.isMember && c.joinPolicy == 'invite') {
      return const OutlinedButton(
        onPressed: null,
        child: Text('Invite only'),
      );
    }
    if (!c.isMember) {
      return FilledButton(
        onPressed: _busy ? null : _join,
        child: Text(c.joinPolicy == 'request' ? 'Request' : 'Join'),
      );
    }
    if (c.viewerRole == 'owner') {
      return OutlinedButton(
        onPressed: () {},
        child: const Text('Owner'),
      );
    }
    return OutlinedButton(
      onPressed: _busy ? null : _leave,
      child: const Text('Leave'),
    );
  }

  Widget _buildFeedTab(ThemeData theme, ClubView c) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (_upcoming.isNotEmpty) _buildNextEventCard(theme, c, _upcoming.first),
          if (c.isMember)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPostComposer(theme),
            ),
          if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  c.isMember
                      ? 'No posts yet. Share an update with members.'
                      : 'No updates yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          for (final p in _posts) _buildPostCard(theme, c, p),
        ],
      ),
    );
  }

  Widget _buildNextEventCard(ThemeData theme, ClubView c, EventView e) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailScreen(
              social: widget.social,
              clubSlug: c.row.slug,
              eventId: e.row.id,
            ),
          ),
        );
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NEXT EVENT',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              e.row.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14,
                    color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  fmtEventDate(e.nextInstanceStart),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                Icon(Icons.group, size: 14,
                    color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  '${e.attendeeCount} going',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostComposer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          TextField(
            controller: _postCtrl,
            maxLines: 3,
            maxLength: 1200,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Share an update…',
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _submitPost,
              child: const Text('Post'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(ThemeData theme, ClubView c, ClubPostView p) {
    final replies = _threads[p.row.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HSLColor.fromAHSL(
                    1, hashHue(p.row.authorId).toDouble(), 0.5, 0.55).toColor(),
                ),
                child: Text(
                  initialFor(p.authorName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.authorName ?? 'Member',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      fmtRelative(p.row.createdAt ?? DateTime.now()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(p.row.body, style: theme.textTheme.bodyMedium),
          if (c.isMember) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _toggleReplies(p.row.id),
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: Text(
                p.replyCount == 0
                    ? 'Reply'
                    : replies != null
                        ? 'Hide ${p.replyCount} repl${p.replyCount == 1 ? 'y' : 'ies'}'
                        : '${p.replyCount} repl${p.replyCount == 1 ? 'y' : 'ies'}',
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 32),
              ),
            ),
            if (replies != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: theme.dividerColor, width: 2),
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in replies)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r.authorName ?? 'Member'} · ${fmtRelative(r.row.createdAt ?? DateTime.now())}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              Text(r.row.body, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyCtrls.putIfAbsent(
                                p.row.id, () => TextEditingController()),
                              decoration: InputDecoration(
                                hintText: 'Write a reply…',
                                isDense: true,
                                filled: true,
                                fillColor: theme.colorScheme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            onPressed: () => _sendReply(p.row.id),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('Send'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _createEvent(ClubView c) async {
    final ok = await showEventFormSheet(
      context,
      social: widget.social,
      clubId: c.row.id,
    );
    if (ok != null) _load();
  }

  Widget _buildEventsTab(ThemeData theme, ClubView c) {
    final showCreate = c.isAdmin;
    if (_upcoming.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                showCreate
                    ? 'No upcoming events. Tap Create to add one.'
                    : 'No upcoming events.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              if (showCreate) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _createEvent(c),
                  icon: const Icon(Icons.add),
                  label: const Text('Create event'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _upcoming.length + (showCreate ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          if (showCreate && i == 0) {
            return Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _createEvent(c),
                icon: const Icon(Icons.add),
                label: const Text('Create event'),
              ),
            );
          }
          final e = _upcoming[showCreate ? i - 1 : i];
          return InkWell(
            onTap: () async {
              await Navigator.of(ctx).push(
                MaterialPageRoute<void>(
                  builder: (_) => EventDetailScreen(
                    social: widget.social,
                    clubSlug: c.row.slug,
                    eventId: e.row.id,
                  ),
                ),
              );
              _load();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Column(
                      children: [
                        Text(
                          fmtEventDate(e.nextInstanceStart).split(',').first,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          fmtEventDate(e.nextInstanceStart).split(', ').last,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.row.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (e.row.meetLabel != null) ...[
                              Icon(Icons.place, size: 13,
                                  color: theme.colorScheme.outline),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  e.row.meetLabel!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                            ] else
                              Icon(Icons.event, size: 13,
                                  color: theme.colorScheme.outline),
                            Text(
                              '${e.attendeeCount} going',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (e.viewerRsvp == 'going')
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Going',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _approve(String userId) async {
    final c = _club;
    if (c == null) return;
    try {
      await widget.social.approveJoinRequest(
        clubId: c.row.id,
        userId: userId,
      );
      if (mounted) {
        setState(() => _pending =
            _pending.where((m) => m.userId != userId).toList());
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Approve failed: $e');
    }
  }

  Future<void> _deny(String userId) async {
    final c = _club;
    if (c == null) return;
    try {
      await widget.social.denyJoinRequest(
        clubId: c.row.id,
        userId: userId,
      );
      if (mounted) {
        setState(() => _pending =
            _pending.where((m) => m.userId != userId).toList());
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Deny failed: $e');
    }
  }

  Widget _buildMembersTab(ThemeData theme, ClubView c) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.isAdmin && _pending.isNotEmpty) ...[
            Text(
              'Pending requests (${_pending.length})',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final m in _pending)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'User ${m.userId.substring(0, 8)}…',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _deny(m.userId),
                        child: const Text('Deny'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => _approve(m.userId),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '${c.memberCount} member${c.memberCount == 1 ? '' : 's'}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 3 && !_routesLoaded) {
      _loadRoutes();
    }
    if (_tabs.index == 4 && !_templatesLoaded) {
      _loadTemplates();
    }
  }

  Future<void> _loadRoutes() async {
    final c = _club;
    if (c == null) return;
    try {
      final list = await widget.social.fetchClubRoutes(c.row.id);
      if (!mounted) return;
      setState(() {
        _routes = list;
        _routesLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _routesLoaded = true);
    }
  }

  Future<void> _loadTemplates() async {
    final c = _club;
    if (c == null) return;
    try {
      final list = await widget.training.fetchClubTemplates(c.row.id);
      if (!mounted) return;
      setState(() {
        _templates = list;
        _templatesLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _templatesLoaded = true);
    }
  }

  Future<void> _adoptTemplate(TrainingPlanRow t) async {
    try {
      final newId = await widget.training.clonePlanTemplate(templateId: t.id);
      if (!mounted) return;
      showTopBanner(context, 'Template added to your plans.');
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => PlanDetailScreen(
            training: widget.training,
            planId: newId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Adopt failed: $e');
    }
  }

  Widget _buildRoutesTab(ThemeData theme, ClubView c) {
    if (!_routesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            c.isAdmin
                ? 'No routes yet. Admins can transfer one of their personal routes from the route detail screen.'
                : 'No routes shared with this club yet.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRoutes,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _routes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = _routes[i];
          return Card(
            child: ListTile(
              leading: r.waypoints.length >= 2
                  ? SizedBox(
                      width: 72,
                      height: 40,
                      // Club routes are owned by other admins / members.
                      // Non-owner thumbnails route through
                      // clip_route_for_viewer (decisions §33).
                      child: RouteTrackPreview(
                        routeId: r.id,
                        waypoints: r.waypoints,
                        ownerUserId: r.userId,
                        api: ApiClient(),
                      ),
                    )
                  : SizedBox(
                      width: 56,
                      height: 40,
                      child: CircleAvatar(
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        child: Icon(Icons.route,
                            color: theme.colorScheme.secondary),
                      ),
                    ),
              title: Text(r.name),
              subtitle: Text(
                '${formatDistanceForPref(r.distanceMetres)}'
                '  •  ${r.elevationGainMetres.round()}m gain',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => PublicRouteScreen(
                    api: ApiClient(),
                    routeId: r.id,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTemplatesTab(ThemeData theme, ClubView c) {
    if (!_templatesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            c.isAdmin
                ? 'No templates yet. Publish one of your plans from its detail page.'
                : 'No plan templates yet for this club.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTemplates,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _templates.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final t = _templates[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, style: theme.textTheme.titleSmall),
                        if (t.notes != null && t.notes!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            t.notes!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _adoptTemplate(t),
                    child: const Text('Adopt'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' hide Route;

import 'package:api_client/api_client.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../local_gym_store.dart';
import '../local_route_store.dart';
import '../local_routine_store.dart';
import '../preferences.dart';
import '../social_service.dart';
import '../training_service.dart';
import '../backend_timeout.dart';
import '../widgets/event_form_sheet.dart';
import '../widgets/report_sheet.dart';
import '../widgets/route_track_preview.dart';
import '../widgets/verified_badge.dart';
import 'event_detail_screen.dart';
import 'plan_detail_screen.dart';
import 'routine_detail_screen.dart';
import 'session_detail_screen.dart';
import 'public_route_screen.dart';
import 'route_builder_screen.dart';
import '../widgets/top_banner.dart';

class ClubDetailScreen extends StatefulWidget {
  final SocialService social;
  final TrainingService training;
  /// Optional — when both are supplied, the Routes tab grows an admin-
  /// only "Build route" CTA that pushes `RouteBuilderScreen` pre-bound
  /// to this club. Mirrors web's `/routes/new?club=<id>` deep link.
  /// Old callers (e.g. `ClubInviteScreen`) can omit them; the CTA
  /// simply doesn't render in that case.
  final ApiClient? apiClient;
  final LocalRouteStore? routeStore;
  final String slug;
  const ClubDetailScreen({
    super.key,
    required this.social,
    required this.training,
    this.apiClient,
    this.routeStore,
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
  final Set<String> _pendingBusy = {};
  final Set<String> _replyBusy = {};
  List<TrainingPlanRow> _templates = const [];
  List<SessionPlanRow> _sessionTemplates = const [];
  String? _adoptingSessionId;
  String? _adoptingPlanId;
  List<GymRoutineRow> _gymRoutineTemplates = const [];
  String? _adoptingRoutineId;
  List<cm.Route> _routes = const [];
  bool _loading = true;
  bool _busy = false;
  bool _templatesLoaded = false;
  bool _routesLoaded = false;
  String? _error;
  bool _timedOut = false;
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
      _timedOut = false;
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
          _timedOut = true;
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
        showTopBanner(
            context, AppLocalizations.of(context).clubDetailRequestSent);
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
        title: Text(
            AppLocalizations.of(context).clubDetailLeaveTitle(c.row.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).clubDetailCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context).clubDetailLeave),
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
    if (c == null || _replyBusy.contains(postId)) return;
    final ctrl = _replyCtrls[postId];
    final body = ctrl?.text.trim();
    if (body == null || body.isEmpty) return;
    setState(() => _replyBusy.add(postId));
    try {
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
    } catch (e) {
      // Without this catch, a network error / RLS rejection on
      // reply post would propagate as an uncaught Future error —
      // Flutter logs it to console but the user sees no feedback
      // and the reply text just sits in the box. Surface a banner
      // so the user knows to retry; the controller text stays
      // because the `ctrl?.clear()` above only fires on success.
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailReplyFailed('$e'));
    } finally {
      if (mounted) setState(() => _replyBusy.remove(postId));
    }
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
                Text(
                  AppLocalizations.of(context).clubDetailLoadFailedTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _timedOut
                      ? AppLocalizations.of(context).clubDetailTimeoutError
                      : _error != null
                          ? _error!
                          : AppLocalizations.of(context)
                              .clubDetailLoadFailedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _load,
                  child: Text(AppLocalizations.of(context).clubDetailRetry),
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
        // Verified-official badge inline with the title for owner-
        // authenticated clubs. Disambiguates the authentic operator
        // from squatter / fan clubs holding the same name.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                c.row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (c.row.isVerified)
              const VerifiedBadge(size: 18),
          ],
        ),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).clubDetailReportClub,
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
          tabs: [
            Tab(text: AppLocalizations.of(context).clubDetailTabFeed),
            Tab(text: AppLocalizations.of(context).clubDetailTabEvents),
            Tab(text: AppLocalizations.of(context).clubDetailTabMembers),
            Tab(text: AppLocalizations.of(context).clubDetailTabRoutes),
            Tab(text: AppLocalizations.of(context).clubDetailTabTemplates),
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
    final cta = _ctaFor(context, c);
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
                  AppLocalizations.of(context)
                      .clubsMemberCount(c.memberCount),
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

  Widget _ctaFor(BuildContext context, ClubView c) {
    final l10n = AppLocalizations.of(context);
    if (c.viewerStatus == 'pending') {
      return OutlinedButton(
        onPressed: null,
        child: Text(l10n.clubDetailRequestPending),
      );
    }
    if (!c.isMember && c.joinPolicy == 'invite') {
      return OutlinedButton(
        onPressed: null,
        child: Text(l10n.clubDetailInviteOnly),
      );
    }
    if (!c.isMember) {
      return FilledButton(
        onPressed: _busy ? null : _join,
        child: Text(c.joinPolicy == 'request'
            ? l10n.clubDetailRequest
            : l10n.clubDetailJoin),
      );
    }
    if (c.viewerRole == 'owner') {
      return OutlinedButton(
        onPressed: () {},
        child: Text(l10n.clubDetailOwner),
      );
    }
    return OutlinedButton(
      onPressed: _busy ? null : _leave,
      child: Text(l10n.clubDetailLeave),
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
                      ? AppLocalizations.of(context).clubDetailNoPostsMember
                      : AppLocalizations.of(context).clubDetailNoPosts,
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
              AppLocalizations.of(context).clubDetailNextEvent,
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
                  fmtEventDate(e.nextInstanceStart,
                      localeToTag(Localizations.localeOf(context))),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                Icon(Icons.group, size: 14,
                    color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context)
                      .clubDetailGoingCount(e.attendeeCount),
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
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: AppLocalizations.of(context).clubDetailShareUpdateHint,
              counterText: '',
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _submitPost,
              child: Text(AppLocalizations.of(context).clubDetailPost),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(ThemeData theme, ClubView c, ClubPostView p) {
    final l10n = AppLocalizations.of(context);
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
                      p.authorName ?? l10n.clubDetailMemberFallback,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      fmtRelative(p.row.createdAt ?? DateTime.now(),
                          localeToTag(Localizations.localeOf(context))),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (Supabase.instance.client.auth.currentUser != null &&
                  Supabase.instance.client.auth.currentUser!.id !=
                      p.row.authorId)
                IconButton(
                  tooltip: l10n.clubDetailReportPost,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => showReportSheet(
                    context,
                    api: ApiClient(),
                    targetKind: 'club_post',
                    targetId: p.row.id,
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
                    ? l10n.clubDetailReply
                    : replies != null
                        ? l10n.clubDetailHideReplies(p.replyCount)
                        : l10n.clubDetailShowReplies(p.replyCount),
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
                                l10n.clubDetailReplyAuthorLine(
                                    r.authorName ?? l10n.clubDetailMemberFallback,
                                    fmtRelative(
                                        r.row.createdAt ?? DateTime.now(),
                                        localeToTag(Localizations.localeOf(context)))),
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
                                hintText: l10n.clubDetailWriteReplyHint,
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
                            onPressed: _replyBusy.contains(p.row.id)
                                ? null
                                : () => _sendReply(p.row.id),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Text(l10n.clubDetailSend),
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
      clubIsPublic: c.row.isPublic ?? true,
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
                    ? AppLocalizations.of(context).clubDetailNoEventsAdmin
                    : AppLocalizations.of(context).clubDetailNoEvents,
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
                  label: Text(AppLocalizations.of(context).clubDetailCreateEvent),
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
                label: Text(AppLocalizations.of(context).clubDetailCreateEvent),
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
                          formatMonthDayShort(e.nextInstanceStart,
                              localeToTag(Localizations.localeOf(context))),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          formatTime(e.nextInstanceStart,
                              localeToTag(Localizations.localeOf(context))),
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
                              AppLocalizations.of(context)
                                  .clubDetailGoingCount(e.attendeeCount),
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
                        AppLocalizations.of(context).clubDetailGoing,
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
    if (c == null || _pendingBusy.contains(userId)) return;
    setState(() => _pendingBusy.add(userId));
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
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailApproveFailed('$e'));
    } finally {
      if (mounted) setState(() => _pendingBusy.remove(userId));
    }
  }

  Future<void> _deny(String userId) async {
    final c = _club;
    if (c == null || _pendingBusy.contains(userId)) return;
    setState(() => _pendingBusy.add(userId));
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
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailDenyFailed('$e'));
    } finally {
      if (mounted) setState(() => _pendingBusy.remove(userId));
    }
  }

  Widget _buildMembersTab(ThemeData theme, ClubView c) {
    final l10n = AppLocalizations.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.isAdmin && _pending.isNotEmpty) ...[
            Text(
              l10n.clubDetailPendingRequests(_pending.length),
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
                          l10n.clubDetailUserShort(m.userId.substring(0, 8)),
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: _pendingBusy.contains(m.userId)
                            ? null
                            : () => _deny(m.userId),
                        child: Text(l10n.clubDetailDeny),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: _pendingBusy.contains(m.userId)
                            ? null
                            : () => _approve(m.userId),
                        child: Text(l10n.clubDetailApprove),
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
                l10n.clubDetailMemberCountLine(c.memberCount),
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

  Future<void> _buildClubRoute(ClubView c) async {
    // Admin-only entry point. Pushes the route builder with the club
    // pre-bound — `SaveRouteDialog`'s "Save to" picker opens with this
    // club already selected. The user can still flip to Personal in
    // the picker if they change their mind mid-save (matches web's
    // `?club=<id>` deep link, which lets the user pick `null` to
    // unbind).
    final api = widget.apiClient;
    final routeStore = widget.routeStore;
    if (api == null || routeStore == null) return;
    final created = await Navigator.of(context).push<cm.Route>(
      MaterialPageRoute<cm.Route>(
        builder: (_) => RouteBuilderScreen(
          apiClient: api,
          routeStore: routeStore,
          social: widget.social,
          initialClubId: c.row.id,
        ),
      ),
    );
    if (created == null || !mounted) return;
    showTopBanner(
        context, AppLocalizations.of(context).clubDetailRouteSaved(created.name));
    // Reload the club's routes so the new one appears immediately
    // (the realtime channel doesn't subscribe to `routes`).
    await _loadRoutes();
  }

  Future<void> _loadTemplates() async {
    final c = _club;
    if (c == null) return;
    try {
      final list = await widget.training.fetchClubTemplates(c.row.id);
      final sessions = await widget.apiClient?.fetchClubSessionTemplates(c.row.id) ??
          const <SessionPlanRow>[];
      final routines =
          await widget.apiClient?.fetchClubGymRoutineTemplates(c.row.id) ??
              const <GymRoutineRow>[];
      if (!mounted) return;
      setState(() {
        _templates = list;
        _sessionTemplates = sessions;
        _gymRoutineTemplates = routines;
        _templatesLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _templatesLoaded = true);
    }
  }

  Future<void> _adoptGymRoutineTemplate(GymRoutineRow g) async {
    final api = widget.apiClient;
    if (api == null || _adoptingRoutineId != null) return;
    setState(() => _adoptingRoutineId = g.id);
    try {
      final newId = await api.cloneGymRoutineTemplate(g.id);
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailGymRoutineAdopted);
      // The clone lands as a personal routine server-side; a throwaway
      // store hydrates the user's routines (including the new one) so the
      // detail screen renders it offline-first, mirroring how the gym
      // screen owns its own LocalRoutineStore.
      final store = LocalRoutineStore();
      await store.init();
      await store.syncWithServer(api);
      final detail = await api.fetchGymRoutineDetail(newId);
      if (detail != null) {
        await store.replaceFromServer([
          (
            routine: detail.routine.toJson(),
            exercises: [
              for (final e in detail.exercises)
                StoredRoutineExercise(
                  exerciseName: e.exercise.exerciseName,
                  exerciseKey: e.exercise.exerciseKey,
                  supersetGroup: e.exercise.supersetGroup,
                  supersetOrder: e.exercise.supersetOrder,
                  modality: e.exercise.modality,
                  progression: e.exercise.progression,
                  progressionParams: e.exercise.progressionParams is Map
                      ? Map<String, dynamic>.from(
                          e.exercise.progressionParams as Map)
                      : const <String, dynamic>{},
                  sets: [
                    for (final s in e.sets)
                      StoredRoutineSet(
                        setType: s.setType,
                        targetRepsMin: s.targetRepsMin,
                        targetRepsMax: s.targetRepsMax,
                        targetWeightKg: s.targetWeightKg,
                        targetRpe: s.targetRpe,
                        restS: s.restS,
                        targetDurationS: s.targetDurationS,
                        targetDistanceM: s.targetDistanceM,
                      ),
                  ],
                ),
            ],
          ),
        ]);
      }
      if (!mounted) return;
      final gymStore = LocalGymStore();
      await gymStore.init();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RoutineDetailScreen(
            api: api,
            store: store,
            gymStore: gymStore,
            routineId: newId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailAdoptFailed('$e'));
    } finally {
      if (mounted) setState(() => _adoptingRoutineId = null);
    }
  }

  Future<void> _adoptSessionTemplate(SessionPlanRow s) async {
    final api = widget.apiClient;
    if (api == null || _adoptingSessionId != null) return;
    setState(() => _adoptingSessionId = s.id);
    try {
      final newId = await api.cloneSessionTemplate(s.id);
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).clubDetailSessionAdopted);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailScreen(
            api: api,
            planId: newId,
            titleHint: s.title,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailAdoptFailed('$e'));
    } finally {
      if (mounted) setState(() => _adoptingSessionId = null);
    }
  }

  Future<void> _adoptTemplate(TrainingPlanRow t) async {
    if (_adoptingPlanId != null) return;
    setState(() => _adoptingPlanId = t.id);
    try {
      final newId = await widget.training.clonePlanTemplate(templateId: t.id);
      if (!mounted) return;
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailTemplateAdded);
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
      showTopBanner(
          context, AppLocalizations.of(context).clubDetailAdoptFailed('$e'));
    } finally {
      if (mounted) setState(() => _adoptingPlanId = null);
    }
  }

  Widget _buildRoutesTab(ThemeData theme, ClubView c) {
    if (!_routesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    // Admin-only CTA — mirrors web's `Routes` tab "New route" + "Transfer
    // from My routes" actions strip on `/clubs/[slug]`. We only render
    // "Build route" today because the mobile transfer flow lives on
    // `route_detail_screen` (per the empty-state copy below); the new
    // CTA covers the create path that the old empty-state pointed
    // users to. Only visible when `apiClient` + `routeStore` were
    // threaded in — the `ClubInviteScreen` redemption path omits both,
    // so the CTA disappears there but the rest of the tab still works.
    final canBuild = c.isAdmin &&
        widget.apiClient != null &&
        widget.routeStore != null;
    final buildCta = canBuild
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('club-detail-build-route'),
                onPressed: () => _buildClubRoute(c),
                icon: const Icon(Icons.add_road),
                label: Text(AppLocalizations.of(context).clubDetailBuildRoute),
              ),
            ),
          )
        : null;
    if (_routes.isEmpty) {
      return Column(
        children: [
          if (buildCta != null) buildCta,
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  canBuild
                      ? AppLocalizations.of(context).clubDetailRoutesEmptyBuild
                      : c.isAdmin
                          ? AppLocalizations.of(context)
                              .clubDetailRoutesEmptyAdmin
                          : AppLocalizations.of(context).clubDetailRoutesEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        if (buildCta != null) buildCta,
        Expanded(
          child: RefreshIndicator(
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
            ),  // ListView.separated
          ),    // RefreshIndicator
        ),      // Expanded
      ],
    );          // Column
  }

  Widget _buildTemplatesTab(ThemeData theme, ClubView c) {
    if (!_templatesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final l10n = AppLocalizations.of(context);
    if (_templates.isEmpty &&
        _sessionTemplates.isEmpty &&
        _gymRoutineTemplates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            c.isAdmin ? l10n.clubDetailNoTemplatesAdmin : l10n.clubDetailNoTemplates,
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final t in _templates) ...[
            Card(
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
                      onPressed: _adoptingPlanId == t.id
                          ? null
                          : () => _adoptTemplate(t),
                      child: Text(l10n.clubDetailAdopt),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_sessionTemplates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(l10n.clubDetailSessionTemplatesTitle,
                  style: theme.textTheme.titleMedium),
            ),
            for (final s in _sessionTemplates) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.title, style: theme.textTheme.titleSmall),
                            if (s.discipline != null && s.discipline!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                s.discipline!,
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
                        onPressed: _adoptingSessionId == s.id
                            ? null
                            : () => _adoptSessionTemplate(s),
                        child: Text(l10n.clubDetailAdopt),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_gymRoutineTemplates.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(l10n.clubDetailGymRoutineTemplatesTitle,
                  style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.clubDetailGymRoutineTemplatesHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            for (final g in _gymRoutineTemplates) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.title, style: theme.textTheme.titleSmall),
                            const SizedBox(height: 4),
                            Text(
                              l10n.clubDetailRoutineExerciseCount(
                                  g.exerciseCount),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (c.isMember)
                        FilledButton(
                          onPressed: _adoptingRoutineId == g.id
                              ? null
                              : () => _adoptGymRoutineTemplate(g),
                          child: Text(l10n.clubDetailAdopt),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

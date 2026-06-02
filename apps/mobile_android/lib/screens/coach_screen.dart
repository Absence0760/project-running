import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend_timeout.dart';
import '../training_service.dart';
import '../widgets/top_banner.dart';

/// Truncate a coach message to a sidebar-thread title. Strips repeated
/// whitespace so multi-line user prompts collapse to a single line, then
/// caps at 48 chars with an ellipsis. Pure helper — used by the active
/// thread row and exposed for unit tests.
String coachTitleFromMessage(String content) {
  final trimmed = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.length <= 48) return trimmed;
  return '${trimmed.substring(0, 47).trimRight()}…';
}

/// Render a relative archive label ("Today", "Yesterday", "3 days ago",
/// or YYYY-MM-DD beyond a week). The optional [now] is for tests; in
/// production the call site uses `DateTime.now()` implicitly.
String coachArchiveLabel(DateTime t, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(t);
  if (diff.inDays <= 0) return 'Today';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// One parsed Server-Sent-Events block from the `/api/coach` stream.
/// `event` is the event type (`meta`, `token`, `done`, `error`, or
/// `message` if no `event:` line was present); `data` is the JSON-decoded
/// payload from the `data:` line. Returns null if the block had no
/// `data:` payload or the JSON failed to decode.
class CoachSseEvent {
  final String event;
  final Map<String, dynamic> data;
  const CoachSseEvent({required this.event, required this.data});
}

/// Parse a single SSE block from the Coach stream. SSE blocks are
/// `\n\n`-delimited; the upstream `_readSse` splits on that, this helper
/// turns one block into a typed event. Pure — no side effects.
CoachSseEvent? parseCoachSseEvent(String block) {
  String event = 'message';
  String dataStr = '';
  for (final line in block.split('\n')) {
    if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      dataStr += line.substring(5).trim();
    }
  }
  if (dataStr.isEmpty) return null;
  try {
    final decoded = jsonDecode(dataStr);
    if (decoded is! Map) return null;
    return CoachSseEvent(
      event: event,
      data: Map<String, dynamic>.from(decoded),
    );
  } catch (_) {
    return null;
  }
}

/// AI Coach chat. Mirrors `apps/web/src/lib/components/CoachChat.svelte`
/// + `/coach/+page.svelte`. One screen file by design — see backlog.
class CoachScreen extends StatefulWidget {
  final ApiClient api;
  final TrainingService training;
  final String? initialPlanId;

  const CoachScreen({
    super.key,
    required this.api,
    required this.training,
    this.initialPlanId,
  });

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _Msg {
  String? id;
  final String role;
  // Content is a ValueNotifier so the SSE token-stream path can append
  // characters at the engine's pace without setStating CoachScreen
  // (which would rebuild the AppBar, drawer, every prior message, and
  // the composer per token). Bubble widgets subscribe via
  // ValueListenableBuilder so only the active assistant bubble rebuilds.
  final ValueNotifier<String> content;
  String? reaction;
  _Msg({this.id, required this.role, required String content, this.reaction})
      : content = ValueNotifier<String>(content);
}

class _ContextSummary {
  final String? planName;
  final int? planWeeks;
  final int runCount;
  final bool hrZonesLoaded;
  final int? weeklyGoalMetres;
  const _ContextSummary({
    required this.planName,
    required this.planWeeks,
    required this.runCount,
    required this.hrZonesLoaded,
    required this.weeklyGoalMetres,
  });
}

class _CoachScreenState extends State<CoachScreen> {
  static const _runLimitOptions = [10, 20, 50, 100];
  // Pre-handshake placeholders. Real values land on the SSE `meta`
  // event from the server (TIER_LIMITS in apps/web/src/lib/coach/types.ts).
  // Seed conservatively with the free cap so the banner can't flash
  // "10 of 10" for a free user's first paint.
  static const _freeDailyLimit = 2;
  static const _proDailyLimit = 10;
  static const _planSuggestions = [
    "Should I run tomorrow or take a rest day?",
    "Am I on track for my goal time?",
    "Why does this week's long run matter?",
    "What should I focus on for today's workout?",
  ];
  static const _noPlanSuggestions = [
    "How was my last run?",
    "What pace should my easy runs be?",
    "I haven't run in a week — what should I do?",
    "What is a tempo run?",
  ];

  final _scrollCtrl = ScrollController();
  final _draftCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  // Generation counter for _loadContext. A plan switch refires the
  // load while a previous one may still be in flight; a stale response
  // landing after the user moved on shouldn't clobber the fresh result.
  int _ctxGen = 0;

  List<TrainingPlanRow> _plans = const [];
  String? _planId;

  List<_Msg> _messages = [];
  bool _threadLoaded = false;
  bool _busy = false;
  String? _error;

  List<DateTime> _archives = const [];
  DateTime? _viewingArchiveAt;
  String? _editingId;
  int _runsLimit = 20;

  String _tier = 'free';
  int _dailyLimit = _freeDailyLimit;
  int _usedToday = 0;
  bool get _limitReached => _usedToday >= _dailyLimit;
  int get _remaining => (_dailyLimit - _usedToday).clamp(0, _dailyLimit);

  _ContextSummary? _ctx;
  RealtimeChannel? _realtimeChannel;
  StreamSubscription<dynamic>? _streamSub;

  /// GDPR Art 6(1)(a) first-use consent state. `_consentChecked` is
  /// false until the bootstrap fetch returns; `_consentAt` is null when
  /// the user has not yet accepted the disclosure. Until both are set
  /// the chat surface is not rendered — no SSE request can fire. See
  /// audit/gdpr (2026-05-25).
  bool _consentChecked = false;
  DateTime? _consentAt;
  bool _consentSaving = false;
  String? _consentError;

  @override
  void initState() {
    super.initState();
    _planId = widget.initialPlanId;
    _bootstrap();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _realtimeChannel?.unsubscribe();
    _scrollCtrl.dispose();
    _draftCtrl.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Resolve the consent state BEFORE anything that could fan out to
    // /api/coach (which forwards health-adjacent data to Anthropic).
    // _reloadAll + _subscribeRealtime can run regardless — they hit
    // Supabase directly and do not transmit data to the AI provider.
    try {
      _consentAt = await widget.api.fetchCoachConsentAt();
    } catch (e) {
      // Fail closed — a lookup error means the disclosure stays up.
      debugPrint('coach_screen: consent lookup failed: $e');
      _consentAt = null;
    }
    if (mounted) setState(() => _consentChecked = true);
    try {
      _plans = await widget.training.fetchMyPlans();
      if (_planId != null && !_plans.any((p) => p.id == _planId)) {
        _planId = null;
      }
      if (_planId == null) {
        for (final p in _plans) {
          if (p.status == 'active') {
            _planId = p.id;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('coach_screen: initial plans load failed: $e');
    }
    await _reloadAll();
    _subscribeRealtime();
  }

  Future<void> _acceptCoachConsent() async {
    if (_consentSaving) return;
    setState(() {
      _consentSaving = true;
      _consentError = null;
    });
    try {
      final at = await widget.api.recordCoachConsent();
      if (!mounted) return;
      setState(() {
        _consentAt = at;
        _consentSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _consentError = e.toString();
        _consentSaving = false;
      });
    }
  }

  Future<void> _reloadAll() async {
    setState(() {
      _threadLoaded = false;
      _viewingArchiveAt = null;
    });
    final results = await Future.wait<dynamic>([
      widget.api.fetchCoachMessages(planId: _planId).catchError((_) => <CoachMessageRow>[]),
      widget.api.listCoachArchives(planId: _planId).catchError((_) => <DateTime>[]),
      widget.api.getCoachUsage().catchError((_) => 0),
      widget.api.isPro().catchError((_) => false),
    ]);
    final rows = results[0] as List<CoachMessageRow>;
    final archives = results[1] as List<DateTime>;
    final used = results[2] as int;
    final pro = results[3] as bool;
    if (!mounted) return;
    setState(() {
      _messages = rows
          .map((r) =>
              _Msg(id: r.id, role: r.role, content: r.content, reaction: r.reaction))
          .toList();
      _archives = archives;
      _usedToday = used;
      _tier = pro ? 'pro' : 'free';
      _dailyLimit = pro ? _proDailyLimit : _freeDailyLimit;
      _threadLoaded = true;
    });
    await _loadContext();
    _scrollToBottom();
  }

  Future<void> _loadContext() async {
    final api = widget.api;
    final viewerId = api.userId;
    if (viewerId == null) return;
    final gen = ++_ctxGen;
    String? planName;
    int? planWeeks;
    int runCount = 0;
    bool hrZonesLoaded = false;
    int? weeklyGoalMetres;
    try {
      if (_planId != null) {
        final p = _plans.firstWhere(
          (x) => x.id == _planId,
          orElse: () => _plans.isNotEmpty
              ? _plans.first
              : TrainingPlanRow(
                  id: '',
                  userId: '',
                  name: '',
                  goalEvent: '',
                  goalDistanceM: 0,
                  startDate: DateTime.now(),
                  endDate: DateTime.now(),
                  daysPerWeek: 0,
                  status: 'draft',
                  source: 'manual',
                  createdAt: DateTime.now(),
                  isTemplate: false,
                ),
        );
        if (p.id == _planId) {
          planName = p.name;
          final detail = await widget.training
              .fetchPlan(_planId!)
              .timeout(kBackendLoadTimeout);
          if (gen != _ctxGen) return;
          planWeeks = detail.weeks.length;
        }
      }
      runCount = await api
          .countRunsForUser(viewerId, limit: _runsLimit)
          .timeout(kBackendLoadTimeout);
      if (gen != _ctxGen) return;
      final prefs = await api
              .fetchUserSettingsPrefs(viewerId)
              .timeout(kBackendLoadTimeout) ??
          const <String, dynamic>{};
      if (gen != _ctxGen) return;
      final zones = prefs['hr_zones'] as Map?;
      if (zones != null) {
        final ks = ['z1', 'z2', 'z3', 'z4', 'z5'];
        hrZonesLoaded =
            ks.every((k) => zones[k] is num && (zones[k] as num) > 0);
      }
      final goal = prefs['weekly_mileage_goal_m'];
      if (goal is num && goal > 0) weeklyGoalMetres = goal.toInt();
    } catch (_) {
      // Fall through with whatever we managed to gather. Hitting the
      // timeout (or any error) leaves the caught fields at their defaults.
    }
    if (!mounted || gen != _ctxGen) return;
    setState(() {
      _ctx = _ContextSummary(
        planName: planName,
        planWeeks: planWeeks,
        runCount: runCount,
        hrZonesLoaded: hrZonesLoaded,
        weeklyGoalMetres: weeklyGoalMetres,
      );
    });
  }

  void _subscribeRealtime() {
    final viewerId = widget.api.userId;
    if (viewerId == null) return;
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = Supabase.instance.client
        .channel('coach_messages:$viewerId:${_planId ?? "no_plan"}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'coach_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: viewerId,
          ),
          callback: (payload) {
            // Realtime callback can fire in the gap between user-pop
            // and channel.unsubscribe (the latter is async). Without
            // the mounted guard, setState here throws "called after
            // dispose" and the unhandled error is reported to Sentry.
            if (!mounted) return;
            final row = payload.newRecord;
            if (row['archived_at'] != null) return;
            final rowPlan = row['plan_id'];
            if ((rowPlan ?? null) != (_planId ?? null)) return;
            final id = row['id'] as String?;
            if (id == null) return;
            if (_messages.any((m) => m.id == id)) return;
            setState(() {
              _messages.add(_Msg(
                id: id,
                role: (row['role'] as String?) ?? 'assistant',
                content: (row['content'] as String?) ?? '',
                reaction: row['reaction'] as String?,
              ));
            });
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final t = _draftCtrl.text.trim();
    if (t.isEmpty || _busy) return;
    _draftCtrl.clear();
    await _runTurn(mode: 'send', userText: t);
  }

  Future<void> _regenerate(String assistantId) async {
    if (_busy) return;
    final idx = _messages.indexWhere((m) => m.id == assistantId);
    if (idx == -1) return;
    setState(() => _messages = _messages.sublist(0, idx));
    await _runTurn(mode: 'regenerate', anchorId: assistantId);
  }

  Future<void> _commitEdit() async {
    final newText = _editCtrl.text.trim();
    final id = _editingId;
    if (newText.isEmpty || id == null || _busy) return;
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    setState(() {
      _messages = _messages.sublist(0, idx);
      _editingId = null;
    });
    await _runTurn(mode: 'edit', userText: newText, anchorId: id);
  }

  Future<void> _runTurn({
    required String mode,
    String? userText,
    String? anchorId,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (userText != null) {
      _messages.add(_Msg(role: 'user', content: userText));
    }
    _messages.add(_Msg(role: 'assistant', content: ''));
    final assistantIdx = _messages.length - 1;
    setState(() {});
    _scrollToBottom();

    try {
      String? token =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) {
        setState(() => _error = 'Please sign in first.');
        _rollback(assistantIdx, userText != null);
        return;
      }
      final payloadMessages = _messages
          .sublist(0, assistantIdx)
          .map((m) => {'role': m.role, 'content': m.content.value})
          .toList();
      final body = jsonEncode({
        'messages': payloadMessages,
        'plan_id': _planId,
        'recent_runs_limit': _runsLimit,
        'mode': mode,
        'anchor_message_id': anchorId,
      });

      final base = (dotenv.env['WEB_BASE_URL'] ?? 'https://threkir.com')
          .replaceAll(RegExp(r'/$'), '');
      final uri = Uri.parse('$base/api/coach');

      // Inline helper so we can retry once after a 401 (stale JWT).
      // Each call uses a fresh HttpClient so a redirect / error
      // leaves no half-open connection. Audit/coach May 2026 Medium #10.
      Future<HttpClientResponse> postWith(String t) async {
        final c = HttpClient();
        try {
          final r = await c.postUrl(uri);
          r.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
          // Production Lambda reads `x-supabase-authorization` only —
          // CloudFront's Lambda OAC sigv4-signs every origin request in
          // the `Authorization` header, so forwarding the viewer's
          // bearer token in that slot would collide with IAM auth on the
          // Function URL. The SvelteKit dev wrapper accepts the same
          // header for parity. See apps/web/lambda/coach/src/index.ts.
          r.headers.set('x-supabase-authorization', 'Bearer $t');
          r.add(utf8.encode(body));
          return await r.close();
        } catch (_) {
          c.close(force: true);
          rethrow;
        }
      }

      var res = await postWith(token);
      if (res.statusCode == 401) {
        // Stale JWT — refresh once + replay. The supabase-flutter
        // refreshSession() drains its own retry budget; if it returns
        // null we fall through to the 401 surface below.
        try {
          final refreshed =
              await Supabase.instance.client.auth.refreshSession();
          final newToken = refreshed.session?.accessToken;
          if (newToken != null) {
            token = newToken;
            res = await postWith(newToken);
          }
        } catch (e) {
          debugPrint('coach_screen: refreshSession failed: $e');
        }
      }

      final ct = res.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (res.statusCode != 200 || !ct.contains('event-stream')) {
        final raw = await res.transform(utf8.decoder).join();
        Map<String, dynamic> j = const {};
        try {
          j = jsonDecode(raw) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('coach_screen: non-JSON error body: $e');
        }
        if (res.statusCode == 401) {
          if (mounted) {
            setState(() => _error = 'Your session expired. Please sign in again.');
          }
        } else if (res.statusCode == 429) {
          final used = (j['used'] as num?)?.toInt() ?? _dailyLimit;
          if (mounted) {
            setState(() {
              _usedToday = used;
              if (j['tier'] is String) {
                _tier = j['tier'] as String;
              }
              if (j['limit'] is num) {
                _dailyLimit = (j['limit'] as num).toInt();
              }
              _error = (j['message'] as String?) ??
                  'Daily limit reached ($_dailyLimit messages). '
                      'Come back tomorrow!';
            });
          }
        } else {
          if (mounted) {
            setState(() => _error = (j['error'] as String?) ??
                'Coach error (${res.statusCode})');
          }
        }
        _rollback(assistantIdx, userText != null);
        return;
      }
      if (mounted) setState(() => _usedToday++);
      await _readSse(res, assistantIdx);
    } catch (e) {
      // Transport-layer failure (DNS, TLS, abort, timeout). Map to a
      // user-actionable string; full detail to debugPrint for triage.
      // Audit/coach May 2026 Low #16.
      debugPrint('coach_screen: transport error: $e');
      if (mounted) {
        setState(() => _error =
            'Could not reach the Coach. Check your connection and try again.');
      }
      _rollback(assistantIdx, userText != null);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      try {
        final archives =
            await widget.api.listCoachArchives(planId: _planId);
        if (mounted) setState(() => _archives = archives);
      } catch (e) {
        debugPrint('coach_screen: archive refresh failed: $e');
      }
    }
  }

  void _rollback(int assistantIdx, bool hadUser) {
    final cut = hadUser ? assistantIdx - 1 : assistantIdx;
    if (cut < 0) return;
    setState(() => _messages = _messages.sublist(0, cut));
  }

  Future<void> _readSse(HttpClientResponse res, int assistantIdx) async {
    final completer = Completer<void>();
    String buffer = '';
    _streamSub = res.transform(utf8.decoder).listen(
      (chunk) {
        buffer += chunk;
        while (true) {
          final i = buffer.indexOf('\n\n');
          if (i == -1) break;
          final block = buffer.substring(0, i);
          buffer = buffer.substring(i + 2);
          _handleSseEvent(block, assistantIdx);
        }
      },
      onDone: () => completer.complete(),
      onError: (e) {
        if (mounted) setState(() => _error = e.toString());
        completer.complete();
      },
      cancelOnError: true,
    );
    await completer.future;
  }

  void _handleSseEvent(String block, int assistantIdx) {
    // SSE events can land after the user pops the screen — the HTTP
    // client is closed in the catch/finally but stream blocks may still
    // be in-flight. Guarding once at the top is enough; every setState
    // below is gated by this early return.
    if (!mounted) return;
    final parsed = parseCoachSseEvent(block);
    if (parsed == null) return;
    final event = parsed.event;
    final data = parsed.data;
    if (event == 'meta') {
      final userMessageId = data['user_message_id'] as String?;
      // _messages may have been mutated by _rollback / _archiveCurrent
      // in a parallel code path; bracket-guard every index access so we
      // never crash with RangeError on a stale assistantIdx.
      if (userMessageId != null &&
          assistantIdx - 1 >= 0 &&
          assistantIdx - 1 < _messages.length) {
        final m = _messages[assistantIdx - 1];
        if (m.role == 'user' && m.id == null) {
          setState(() => m.id = userMessageId);
        }
      }
      if (data['tier'] is String) {
        setState(() => _tier = data['tier'] as String);
      }
      final limits = data['limits'];
      if (limits is Map && limits['daily_limit'] is num) {
        setState(() => _dailyLimit = (limits['daily_limit'] as num).toInt());
      }
    } else if (event == 'token') {
      final text = (data['text'] as String?) ?? '';
      if (assistantIdx >= 0 && assistantIdx < _messages.length) {
        // No setState — the bubble subscribes via ValueListenableBuilder.
        _messages[assistantIdx].content.value += text;
      }
      _scrollToBottom();
    } else if (event == 'done') {
      final id = data['assistant_message_id'] as String?;
      if (id != null &&
          assistantIdx >= 0 &&
          assistantIdx < _messages.length) {
        setState(() => _messages[assistantIdx].id = id);
      }
    } else if (event == 'error') {
      setState(() => _error = (data['message'] as String?) ?? 'stream failed');
    }
  }

  Future<void> _archiveCurrent() async {
    if (_messages.isEmpty || _viewingArchiveAt != null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Start a new conversation?'),
            content: const Text(
                'The current chat moves to history. You can revisit it from the sidebar.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('New chat'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.api.archiveCoachThread(planId: _planId);
      if (!mounted) return;
      setState(() {
        _messages = [];
        _viewingArchiveAt = null;
      });
      final archives = await widget.api.listCoachArchives(planId: _planId);
      if (mounted) setState(() => _archives = archives);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not start a new conversation: $e');
    }
  }

  Future<void> _viewArchive(DateTime t) async {
    try {
      final rows =
          await widget.api.fetchCoachArchive(archivedAt: t, planId: _planId);
      if (!mounted) return;
      setState(() {
        _viewingArchiveAt = t;
        _messages = rows
            .map((r) => _Msg(
                id: r.id,
                role: r.role,
                content: r.content,
                reaction: r.reaction))
            .toList();
      });
      Navigator.maybePop(context);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, 'Could not open archive: $e');
    }
  }

  Future<void> _backToActive() async {
    setState(() => _viewingArchiveAt = null);
    await _reloadAll();
  }

  Future<void> _deleteArchive(DateTime t) async {
    final wasViewing = _viewingArchiveAt == t;
    try {
      await widget.api.deleteCoachArchive(archivedAt: t, planId: _planId);
      if (!mounted) return;
      setState(() {
        _archives = _archives.where((x) => x != t).toList();
        if (wasViewing) _viewingArchiveAt = null;
      });
      if (wasViewing) await _reloadAll();
    } catch (e) {
      debugPrint('coach_screen: archive unarchive failed: $e');
    }
  }

  Future<void> _react(String messageId, String reaction) async {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final cur = _messages[idx];
    final next = cur.reaction == reaction ? null : reaction;
    setState(() => cur.reaction = next);
    try {
      await widget.api.setCoachReaction(messageId: messageId, reaction: next);
    } catch (_) {
      setState(() => cur.reaction = cur.reaction == next ? reaction : null);
    }
  }

  Future<void> _copy(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    showTopBanner(context, 'Copied to clipboard', duration: Duration(seconds: 1));
  }

  /// flutter_markdown's default `onTapLink` calls `url_launcher` on every
  /// scheme it parses, including `javascript:`, `file:`, and `data:` —
  /// vectors a model-authored response can carry through. The web path
  /// goes through DOMPurify which strips them; mobile does not. Whitelist
  /// http(s) and mailto schemes only; everything else is silently dropped
  /// (the markdown still renders the link's TEXT, the user just can't
  /// tap it).
  Future<void> _onCoachLinkTap(String text, String? href, String title) async {
    if (href == null || href.isEmpty) return;
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) return;
    final scheme = uri.scheme.toLowerCase();
    const allowedSchemes = {'http', 'https', 'mailto'};
    if (!allowedSchemes.contains(scheme) && scheme.isNotEmpty) {
      // Relative URLs (no scheme) are inline run / route links like
      // /runs/{id}; treat them as in-app navigation candidates rather
      // than launching externally.
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('coach link tap failed: $e');
    }
  }

  void _onPlanChanged(String? next) {
    setState(() => _planId = (next ?? '').isEmpty ? null : next);
    _streamSub?.cancel();
    _reloadAll();
    _subscribeRealtime();
  }

  String _archiveLabel(DateTime t) => coachArchiveLabel(t);

  String _activeThreadTitle() {
    for (final m in _messages) {
      if (m.role == 'user') return coachTitleFromMessage(m.content.value);
    }
    return 'New conversation';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasPlan = _planId != null;

    // GDPR Art 6(1)(a) gate. _consentChecked stays false until the
    // bootstrap fetch settles so we never flash the chat surface
    // before the lookup completes. _consentAt being null means the
    // user must accept the disclosure before any chat fans out.
    if (!_consentChecked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coach')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_consentAt == null) {
      return _buildCoachConsentScaffold(theme);
    }

    return Scaffold(
      appBar: AppBar(
        // A left `drawer` makes AppBar auto-imply a hamburger in the
        // leading slot, which swallowed the back button on this pushed
        // route. Force the back arrow and open the archive drawer from an
        // explicit action instead.
        leading: const BackButton(),
        title: Row(
          children: [
            const Text('Coach'),
            if (_plans.length > 1) ...[
              const SizedBox(width: 12),
              Flexible(
                child: DropdownButton<String>(
                  value: _planId ?? '',
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No plan (recent runs only)'),
                    ),
                    ..._plans.map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.status == 'active'
                                ? '${p.name} · active'
                                : (p.status == 'completed'
                                    ? '${p.name} · done'
                                    : p.name),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: _busy ? null : _onPlanChanged,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_messages.isNotEmpty && _viewingArchiveAt == null)
            IconButton(
              tooltip: 'New chat',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _busy ? null : _archiveCurrent,
            ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Chat history',
              icon: const Icon(Icons.history),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
        ],
      ),
      drawer: _buildArchivesDrawer(theme),
      body: Column(
        children: [
          if (_ctx != null) _buildContextStrip(theme),
          if (_viewingArchiveAt != null) _buildArchiveBanner(theme),
          if (_remaining <= 3) _buildLimitBanner(theme, cs),
          if (_error != null) _buildErrorBanner(theme, cs),
          Expanded(
            child: _threadLoaded
                ? _buildScroll(theme, hasPlan)
                : const Center(child: CircularProgressIndicator()),
          ),
          if (_viewingArchiveAt == null) _buildComposer(theme, cs),
        ],
      ),
    );
  }

  Widget _buildCoachConsentScaffold(ThemeData theme) {
    // GDPR Art 6(1)(a) first-use disclosure. Renders instead of the
    // chat surface until the user clicks "I consent". Mirrors the
    // /coach disclosure modal on web. See audit/gdpr (2026-05-25).
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Coach')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Before you chat with Coach',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'To give you grounded advice, Coach forwards a slice of your '
                'training data to Anthropic, our AI model provider in the '
                'United States. That slice includes:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('• Your date of birth, gender, and HR zones if set.'),
                    SizedBox(height: 4),
                    Text('• A window of your most recent runs.'),
                    SizedBox(height: 4),
                    Text('• The active training plan you have selected.'),
                    SizedBox(height: 4),
                    Text('• The chat messages you type in the screen below.'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Anthropic processes the data on Threkir\'s behalf under '
                'their data-processing terms; they do not train their '
                'models on Threkir customer data by default. Full details '
                '— including transfer mechanism, retention, and your '
                'withdrawal rights — are in our privacy policy.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                'Tap "I consent" to continue. Tap cancel to leave the page '
                'with no data sent.',
                style: theme.textTheme.bodyMedium,
              ),
              if (_consentError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _consentError!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _consentSaving ? null : () => Navigator.maybePop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _consentSaving ? null : _acceptCoachConsent,
                    child: Text(_consentSaving
                        ? 'Recording consent…'
                        : 'I consent — start Coach'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArchivesDrawer(ThemeData theme) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New chat'),
                onPressed: (_messages.isEmpty && _viewingArchiveAt == null) ||
                        _busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        if (_viewingArchiveAt != null) {
                          _backToActive();
                        } else {
                          _archiveCurrent();
                        }
                      },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: Text(_activeThreadTitle()),
                    subtitle: Text(
                        'Active${_messages.isNotEmpty ? " · ${_messages.length}" : ""}'),
                    selected: _viewingArchiveAt == null,
                    onTap: () {
                      if (_viewingArchiveAt != null) {
                        Navigator.pop(context);
                        _backToActive();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  for (final t in _archives)
                    Dismissible(
                      key: ValueKey(t.toIso8601String()),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => _deleteArchive(t),
                      child: ListTile(
                        title: Text(_archiveLabel(t)),
                        subtitle: const Text('Tap to view · swipe to delete'),
                        selected: _viewingArchiveAt == t,
                        onTap: () => _viewArchive(t),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextStrip(ThemeData theme) {
    final c = _ctx!;
    final cs = theme.colorScheme;
    final chips = <Widget>[];
    if (c.planName != null) {
      chips.add(_chip(
        cs,
        icon: Icons.calendar_month,
        label: c.planWeeks != null ? '${c.planName} · ${c.planWeeks}w' : c.planName!,
      ));
    } else {
      chips.add(_chip(cs, icon: Icons.calendar_month, label: 'No plan', muted: true));
    }
    chips.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_run, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(c.runCount == 0 ? 'No runs' : 'Last',
                  style: theme.textTheme.bodySmall),
              if (c.runCount > 0) ...[
                const SizedBox(width: 4),
                DropdownButton<int>(
                  value: _runsLimit,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  style: theme.textTheme.bodySmall,
                  items: _runLimitOptions
                      .map((n) =>
                          DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) {
                            setState(() => _runsLimit = v);
                            _loadContext();
                          }
                        },
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (c.hrZonesLoaded) {
      chips.add(_chip(cs, icon: Icons.monitor_heart, label: 'HR'));
    }
    if (c.weeklyGoalMetres != null) {
      final km = (c.weeklyGoalMetres! / 1000).toStringAsFixed(0);
      chips.add(_chip(cs, icon: Icons.flag, label: '$km km/wk'));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: chips),
      ),
    );
  }

  Widget _chip(ColorScheme cs,
      {required IconData icon, required String label, bool muted = false}) {
    final color = muted ? cs.onSurfaceVariant : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveBanner(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Viewing archive · ${_archiveLabel(_viewingArchiveAt!)} · read-only',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton.icon(
            onPressed: _backToActive,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to active'),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitBanner(ThemeData theme, ColorScheme cs) {
    final String text;
    if (_limitReached) {
      text = _tier == 'pro'
          ? 'Daily limit reached. Come back tomorrow.'
          : 'Daily limit reached. Pro gets a higher cap — upgrade in Settings.';
    } else {
      text = '$_remaining message${_remaining == 1 ? "" : "s"} left today';
    }
    return Container(
      width: double.infinity,
      color: cs.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onTertiaryContainer),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, ColorScheme cs) {
    return Container(
      width: double.infinity,
      color: cs.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            iconSize: 18,
            onPressed: () => setState(() => _error = null),
            icon: Icon(Icons.close, color: cs.onErrorContainer),
          ),
        ],
      ),
    );
  }

  Widget _buildScroll(ThemeData theme, bool hasPlan) {
    if (_messages.isEmpty && _viewingArchiveAt == null) {
      final suggestions = hasPlan ? _planSuggestions : _noPlanSuggestions;
      return ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              hasPlan
                  ? "Ask about today's workout, your pace, or how recent runs compare to plan."
                  : 'Ask about your recent runs, easy-run pacing, or training basics.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in suggestions)
                ActionChip(
                  label: Text(s),
                  onPressed: _busy
                      ? null
                      : () {
                          _draftCtrl.text = s;
                        },
                ),
            ],
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _buildBubble(theme, _messages[i]),
    );
  }

  Widget _buildBubble(ThemeData theme, _Msg m) {
    final cs = theme.colorScheme;
    final isUser = m.role == 'user';
    final bg = isUser ? cs.primaryContainer : cs.surfaceContainerHigh;
    final fg = isUser ? cs.onPrimaryContainer : cs.onSurface;
    final isEditing = _editingId == m.id && m.id != null && isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: isEditing
                      ? _buildEditForm()
                      : ValueListenableBuilder<String>(
                          valueListenable: m.content,
                          builder: (context, content, _) => isUser
                              ? Text(content, style: TextStyle(color: fg))
                              : (content.isEmpty && _busy
                                  ? _buildTyping(theme)
                                  : MarkdownBody(
                                      data: content,
                                      selectable: true,
                                      onTapLink: _onCoachLinkTap,
                                      // imageBuilder: deny everything.
                                      // flutter_markdown's default
                                      // builder happily decodes
                                      // `data:image/...` URIs and
                                      // even fetches `http://` URLs
                                      // — both vectors a model can
                                      // carry. Web's DOMPurify strips
                                      // <img> via ALLOWED_TAGS; mirror
                                      // that posture here.
                                      // /audit/all xss Medium.
                                      imageBuilder:
                                          (uri, title, alt) =>
                                              const SizedBox.shrink(),
                                      styleSheet:
                                          MarkdownStyleSheet.fromTheme(theme)
                                              .copyWith(
                                        p: TextStyle(
                                            color: fg, height: 1.45),
                                        listBullet: TextStyle(color: fg),
                                      ),
                                    )),
                        ),
                ),
                if (m.id != null && _viewingArchiveAt == null)
                  _buildBubbleActions(theme, m, isUser),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _editCtrl,
          minLines: 2,
          maxLines: 6,
          autofocus: true,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() => _editingId = null),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _busy ? null : _commitEdit,
              child: const Text('Save & resend'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTyping(ThemeData theme) {
    return SizedBox(
      width: 36,
      height: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: _Dot(delayMs: i * 160),
          );
        }),
      ),
    );
  }

  Widget _buildBubbleActions(ThemeData theme, _Msg m, bool isUser) {
    final cs = theme.colorScheme;
    final iconColor = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Copy',
            icon: Icon(Icons.copy_all_outlined, size: 16, color: iconColor),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _copy(m.content.value),
          ),
          if (isUser)
            IconButton(
              tooltip: 'Edit',
              icon: Icon(Icons.edit_outlined, size: 16, color: iconColor),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: _busy
                  ? null
                  : () {
                      _editCtrl.text = m.content.value;
                      setState(() => _editingId = m.id);
                    },
            )
          else ...[
            IconButton(
              tooltip: 'Regenerate',
              icon: Icon(Icons.refresh, size: 16, color: iconColor),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: _busy ? null : () => _regenerate(m.id!),
            ),
            IconButton(
              tooltip: 'Helpful',
              icon: Icon(
                m.reaction == 'up'
                    ? Icons.thumb_up
                    : Icons.thumb_up_outlined,
                size: 16,
                color: m.reaction == 'up' ? cs.primary : iconColor,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _react(m.id!, 'up'),
            ),
            IconButton(
              tooltip: 'Not helpful',
              icon: Icon(
                m.reaction == 'down'
                    ? Icons.thumb_down
                    : Icons.thumb_down_outlined,
                size: 16,
                color: m.reaction == 'down' ? cs.error : iconColor,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => _react(m.id!, 'down'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComposer(ThemeData theme, ColorScheme cs) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _draftCtrl,
                enabled: !_busy && !_limitReached,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: _limitReached
                      ? 'Daily limit reached'
                      : 'Ask Coach…',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy || _limitReached ? null : _send,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(14),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int delayMs;
  const _Dot({required this.delayMs});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // WCAG 2.3.3 (Animation from Interactions) — honour the OS
    // "reduce motion" setting: render a static dot instead of the
    // repeating fade so a vestibular-sensitive user isn't subjected
    // to the looping typing indicator.
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_c.isAnimating) _c.stop();
      return _dot(cs.onSurfaceVariant);
    }
    if (!_started) {
      _started = true;
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (!mounted) return;
        if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
        _c.repeat(reverse: true);
      });
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: _dot(cs.onSurfaceVariant),
    );
  }
}

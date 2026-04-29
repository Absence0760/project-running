import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

/// Run-detail kudos pill + one-level comment thread + composer. Mirrors
/// the web `RunSocial.svelte` component.
class RunSocialSection extends StatefulWidget {
  final ApiClient api;
  final String runId;

  /// Owner gates the "delete any comment" affordance.
  final String? runOwnerId;

  const RunSocialSection({
    super.key,
    required this.api,
    required this.runId,
    this.runOwnerId,
  });

  @override
  State<RunSocialSection> createState() => _RunSocialSectionState();
}

class _RunSocialSectionState extends State<RunSocialSection> {
  bool _loading = true;
  bool _kudosBusy = false;
  bool _posting = false;

  EngagementSummary _eng = const EngagementSummary(
    kudosCount: 0,
    viewerHasKudos: false,
    commentCount: 0,
  );
  List<RunCommentWithAuthor> _comments = const [];

  String? _replyTo;

  final _draftCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();

  String? get _viewerId => widget.api.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draftCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        widget.api.fetchEngagementSummaries([widget.runId]),
        widget.api.fetchRunCommentsWithAuthors(widget.runId),
      ]);
      final engMap = results[0]
          as Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>;
      final cs = results[1] as List<RunCommentWithAuthor>;
      final entry = engMap[widget.runId];
      if (!mounted) return;
      setState(() {
        _eng = entry == null
            ? const EngagementSummary(
                kudosCount: 0,
                viewerHasKudos: false,
                commentCount: 0,
              )
            : EngagementSummary(
                kudosCount: entry.kudosCount,
                viewerHasKudos: entry.viewerHasKudos,
                commentCount: entry.commentCount,
              );
        _comments = cs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleKudos() async {
    if (_kudosBusy || _viewerId == null) return;
    // RLS would reject self-kudos anyway; skip the round-trip.
    if (widget.runOwnerId != null && widget.runOwnerId == _viewerId) return;
    final before = _eng;
    setState(() {
      _kudosBusy = true;
      _eng = EngagementSummary(
        kudosCount: before.viewerHasKudos
            ? (before.kudosCount - 1).clamp(0, 1 << 30)
            : before.kudosCount + 1,
        viewerHasKudos: !before.viewerHasKudos,
        commentCount: before.commentCount,
      );
    });
    try {
      if (before.viewerHasKudos) {
        await widget.api.rescindKudos(widget.runId);
      } else {
        await widget.api.giveKudos(widget.runId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _eng = before);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update kudos: $e')),
      );
    } finally {
      if (mounted) setState(() => _kudosBusy = false);
    }
  }

  Future<void> _postComment({String? parentId}) async {
    final ctrl = parentId == null ? _draftCtrl : _replyCtrl;
    final body = ctrl.text.trim();
    if (body.isEmpty || _viewerId == null) return;
    setState(() => _posting = true);
    try {
      await widget.api.addRunComment(
        runId: widget.runId,
        body: body,
        parentCommentId: parentId,
      );
      ctrl.clear();
      if (!mounted) return;
      if (parentId != null) {
        setState(() => _replyTo = null);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await widget.api.deleteRunComment(commentId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  bool _canDelete(RunCommentRow c) {
    if (_viewerId == null) return false;
    if (c.authorId == _viewerId) return true;
    if (widget.runOwnerId != null && widget.runOwnerId == _viewerId) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final topLevel = <RunCommentWithAuthor>[];
    final repliesByParent = <String, List<RunCommentWithAuthor>>{};
    for (final c in _comments) {
      final parent = c.comment.parentCommentId;
      if (parent == null) {
        topLevel.add(c);
      } else {
        repliesByParent.putIfAbsent(parent, () => []).add(c);
      }
    }

    final isOwn = widget.runOwnerId != null &&
        widget.runOwnerId == _viewerId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header + kudos pill
          Row(
            children: [
              Text('Activity', style: theme.textTheme.titleMedium),
              const Spacer(),
              _KudosPill(
                count: _eng.kudosCount,
                viewerHas: _eng.viewerHasKudos,
                disabled: _kudosBusy || _viewerId == null || isOwn,
                onTap: _toggleKudos,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Comments list
          if (topLevel.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No comments yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final c in topLevel) ...[
              _CommentTile(
                entry: c,
                canDelete: _canDelete(c.comment),
                onReply: _viewerId == null
                    ? null
                    : () => setState(() {
                          _replyTo = c.comment.id;
                          _replyCtrl.clear();
                        }),
                onDelete: () => _deleteComment(c.comment.id),
              ),
              for (final r in (repliesByParent[c.comment.id] ?? const []))
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: _CommentTile(
                    entry: r,
                    canDelete: _canDelete(r.comment),
                    onReply: null,
                    onDelete: () => _deleteComment(r.comment.id),
                    isReply: true,
                  ),
                ),
              if (_replyTo == c.comment.id)
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 4, 0, 8),
                  child: _Composer(
                    controller: _replyCtrl,
                    hint: 'Write a reply…',
                    posting: _posting,
                    onPost: () => _postComment(parentId: c.comment.id),
                    onCancel: () => setState(() => _replyTo = null),
                  ),
                ),
            ],

          if (_viewerId != null) ...[
            const SizedBox(height: 12),
            _Composer(
              controller: _draftCtrl,
              hint: 'Add a comment…',
              posting: _posting,
              onPost: () => _postComment(),
            ),
          ],
        ],
      ),
    );
  }
}

class _KudosPill extends StatelessWidget {
  final int count;
  final bool viewerHas;
  final bool disabled;
  final VoidCallback onTap;

  const _KudosPill({
    required this.count,
    required this.viewerHas,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = viewerHas
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: disabled ? null : onTap,
      icon: Icon(
        viewerHas ? Icons.favorite : Icons.favorite_border,
        size: 18,
        color: accent,
      ),
      label: Text(
        '$count',
        style: theme.textTheme.bodyMedium?.copyWith(color: accent),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final RunCommentWithAuthor entry;
  final bool canDelete;
  final VoidCallback? onReply;
  final VoidCallback onDelete;
  final bool isReply;

  const _CommentTile({
    required this.entry,
    required this.canDelete,
    required this.onReply,
    required this.onDelete,
    this.isReply = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isReply ? 6 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniAvatar(
            displayName: entry.author.displayName,
            avatarUrl: entry.author.avatarUrl,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.author.displayName ?? 'Runner',
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _fmtRelative(entry.comment.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(entry.comment.body, style: theme.textTheme.bodyMedium),
                Row(
                  children: [
                    if (onReply != null)
                      TextButton(
                        onPressed: onReply,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 28),
                        ),
                        child: const Text('Reply'),
                      ),
                    if (canDelete)
                      TextButton(
                        onPressed: onDelete,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 28),
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: const Text('Delete'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtRelative(DateTime started) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    final mins = ms ~/ 60000;
    if (mins < 1) return 'just now';
    if (mins < 60) return '${mins}m ago';
    final hrs = mins ~/ 60;
    if (hrs < 24) return '${hrs}h ago';
    final days = hrs ~/ 24;
    if (days < 30) return '${days}d ago';
    return '${started.day}/${started.month}/${started.year}';
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool posting;
  final VoidCallback onPost;
  final VoidCallback? onCancel;

  const _Composer({
    required this.controller,
    required this.hint,
    required this.posting,
    required this.onPost,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            minLines: 1,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            FilledButton(
              onPressed: posting ? null : onPost,
              child: posting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post'),
            ),
            if (onCancel != null)
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ),
      ],
    );
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
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.primary,
        image: avatarUrl != null && avatarUrl!.isNotEmpty
            ? DecorationImage(
                // Decode at ~3× the rendered 32 dp circle — comments can
                // stack into a long list, so a 1024² JPEG decoded in full
                // for each thumbnail is wasted memory.
                image: ResizeImage(
                  NetworkImage(avatarUrl!),
                  width: 96,
                  height: 96,
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null || avatarUrl!.isEmpty
          ? Text(
              letter,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

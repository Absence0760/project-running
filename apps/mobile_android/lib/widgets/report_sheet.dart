import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/gen/app_localizations.dart';
import '../rate_limit_errors.dart';
import 'top_banner.dart';

/// Modal report sheet — entry point for the moderation flow on
/// profiles, clubs, routes, comments, club posts, and runs. Mirrors
/// the web `submitReport` surface. The user picks a reason from a
/// fixed list + optional free-text notes, then taps Submit.
///
/// Errors are surfaced inline:
///   - 23505 (duplicate pending report) → "You already have a
///     pending report against this content."
///   - P0001 (rate-limited create_report bucket) → routed through
///     `rateLimitErrorMessage` for the shared friendly wording.
///   - Anything else → raw error message.
///
/// Use the static [show] method rather than instantiating directly:
///
///   ```
///   showReportSheet(
///     context,
///     api: api,
///     targetKind: 'user',
///     targetId: user.id,
///   );
///   ```
Future<void> showReportSheet(
  BuildContext context, {
  required ApiClient api,
  required String targetKind,
  required String targetId,
}) async {
  // Capture the host context so the success banner survives the
  // modal's Navigator.pop — Overlay.of on a popped sheet's context
  // returns the same overlay, but the widget itself is unmounted by
  // the time the banner inserts.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ReportSheet(
      api: api,
      targetKind: targetKind,
      targetId: targetId,
      onSuccess: () {
        Navigator.of(ctx).pop();
        showTopBanner(
          context,
          AppLocalizations.of(context).reportSuccess,
        );
      },
    ),
  );
}

/// The ordered reason VALUE keys shown in the picker. These mirror the
/// web `ReportReason` union; the migration's CHECK constraint rejects
/// anything outside this set so keeping them in sync is load-bearing.
/// The human label for each is resolved per-locale at render time.
const _reasonKeys = <String>[
  'spam',
  'harassment',
  'inappropriate',
  'impersonation',
  'other',
];

String _reasonLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'spam':
      return l10n.reportReasonSpam;
    case 'harassment':
      return l10n.reportReasonHarassment;
    case 'inappropriate':
      return l10n.reportReasonInappropriate;
    case 'impersonation':
      return l10n.reportReasonImpersonation;
    default:
      return l10n.reportReasonOther;
  }
}

class _ReportSheet extends StatefulWidget {
  final ApiClient api;
  final String targetKind;
  final String targetId;
  final VoidCallback onSuccess;

  const _ReportSheet({
    required this.api,
    required this.targetKind,
    required this.targetId,
    required this.onSuccess,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = 'spam';
  final _notesCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _notesCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notes = _notesCtl.text.trim();
      await widget.api.submitReport(
        targetKind: widget.targetKind,
        targetId: widget.targetId,
        reason: _reason,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      widget.onSuccess();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.code == '23505') {
        setState(() =>
            _error = AppLocalizations.of(context).reportErrDuplicate);
        return;
      }
      final friendly = rateLimitErrorMessage(code: e.code, message: e.message);
      setState(() => _error = friendly ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _title(l10n, widget.targetKind),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.reportDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.reportReason, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final key in _reasonKeys)
            RadioListTile<String>(
              value: key,
              groupValue: _reason,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _reason = v ?? _reason),
              title: Text(_reasonLabel(l10n, key)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtl,
            maxLines: 3,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: l10n.reportNotesLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.reportCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.reportSubmit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _title(AppLocalizations l10n, String kind) {
    switch (kind) {
      case 'user':
        return l10n.reportTitleUser;
      case 'club':
        return l10n.reportTitleClub;
      case 'route':
        return l10n.reportTitleRoute;
      case 'comment':
        return l10n.reportTitleComment;
      case 'club_post':
        return l10n.reportTitlePost;
      case 'run':
        return l10n.reportTitleRun;
      case 'route_review':
        return l10n.reportTitleReview;
    }
    return l10n.reportTitleContent;
  }
}

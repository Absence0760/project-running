import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../rate_limit_errors.dart';
import 'top_banner.dart';

/// Modal report sheet — entry point for the moderation flow on
/// profiles, clubs, and routes. Mirrors the web `submitReport`
/// surface. The user picks a reason from a fixed list + optional
/// free-text notes, then taps Submit.
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
          "Report submitted — thanks for flagging this for review.",
        );
      },
    ),
  );
}

/// Each reason maps to a label shown in the picker. Values mirror
/// the web `ReportReason` union; the migration's CHECK constraint
/// rejects anything outside this set so keeping them in sync is
/// load-bearing.
const _reasonLabels = <String, String>{
  'spam': 'Spam',
  'harassment': 'Harassment or abuse',
  'inappropriate': 'Inappropriate content',
  'impersonation': 'Impersonation',
  'other': 'Other',
};

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
        setState(() => _error =
            'You already have a pending report against this content.');
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
    final insets = MediaQuery.of(context).viewInsets;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Report ${_kindLabel(widget.targetKind)}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Your report goes to a moderator. False reports are reviewed too — please only flag content that violates our community guidelines.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text('Reason', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          for (final entry in _reasonLabels.entries)
            RadioListTile<String>(
              value: entry.key,
              groupValue: _reason,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _reason = v ?? _reason),
              title: Text(entry.value),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtl,
            maxLines: 3,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
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
                  child: const Text('Cancel'),
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
                      : const Text('Submit report'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _kindLabel(String kind) {
    switch (kind) {
      case 'user':
        return 'user';
      case 'club':
        return 'club';
      case 'route':
        return 'route';
    }
    return 'content';
  }
}

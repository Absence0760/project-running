import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../ai_disclosure.dart';
import '../auth_error.dart';
import '../l10n/gen/app_localizations.dart';

/// The AI-processing disclosure a runner accepts (GDPR Art 6(1)(a)).
///
/// One copy, three hosts: the Coach first-use gate, the Settings → Account
/// tile where an existing acceptance is widened, and the route-detail
/// fallback notice. Keeping the copy here is what stops two surfaces
/// describing different processing while writing the same consent record —
/// the bug one layer up from the version ladder in `ai_disclosure.dart`.
/// Mirrors web's `AiDisclosureNotice.svelte`.
class AiDisclosureNotice extends StatelessWidget {
  const AiDisclosureNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final bullets = [
      l10n.coachConsentBulletProfile,
      l10n.coachConsentBulletRuns,
      l10n.coachConsentBulletPlan,
      l10n.coachConsentBulletMessages,
      l10n.coachConsentBulletRoutes,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.coachConsentIntro, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $bullet'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.coachConsentProcessing, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Present the disclosure and, on accept, record it at
/// [kAiDisclosureCurrentVersion]. Resolves to the record the SERVER stored,
/// or null when the runner cancelled — a caller that unlocked on anything
/// else would be acting on a write it never saw land (decisions § 560).
Future<AiDisclosureRecord?> showAiDisclosureDialog(
  BuildContext context,
  ApiClient api,
) {
  return showDialog<AiDisclosureRecord>(
    context: context,
    builder: (_) => _AiDisclosureDialog(api: api),
  );
}

class _AiDisclosureDialog extends StatefulWidget {
  const _AiDisclosureDialog({required this.api});

  final ApiClient api;

  @override
  State<_AiDisclosureDialog> createState() => _AiDisclosureDialogState();
}

class _AiDisclosureDialogState extends State<_AiDisclosureDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final row = await widget.api
          .recordAiDisclosureConsent(kAiDisclosureCurrentVersion);
      if (!mounted) return;
      Navigator.of(context).pop(aiDisclosureFromProfileRow(row));
    } catch (e) {
      debugPrint('ai_disclosure: record failed: $e');
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      setState(() {
        _error = l10n.aiDisclosureRecordFailed(friendlyError(l10n, e));
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.coachConsentHeadline),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const AiDisclosureNotice(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.coachConsentCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _accept,
          child: Text(
            _saving ? l10n.coachConsentSaving : l10n.coachConsentAccept,
          ),
        ),
      ],
    );
  }
}

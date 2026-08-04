import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Confirm leaving a form whose unsaved edits would be lost. Resolves `true`
/// when the user chooses to discard, `false` on cancel / barrier dismiss.
/// [body] swaps the generic message for a surface-specific one (e.g. the
/// privacy-zones editor's).
Future<bool> confirmDiscard(BuildContext context, {String? body}) async {
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.discardChangesTitle),
          content: Text(body ?? l10n.discardChangesBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.discardChangesCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(l10n.discardChangesDiscard),
            ),
          ],
        ),
      ) ??
      false;
}

/// Blocks a route pop while [isDirty] reports unsaved edits: the pop attempt
/// shows [confirmDiscard] and only completes on confirmation.
///
/// [isDirty] is probed at pop time, not build time — most form edits live in
/// TextEditingControllers, which never rebuild the enclosing route, so a
/// build-time `canPop` would go stale and let a dirty form slip out unguarded.
/// The system back gesture and the AppBar back/close button both route
/// through `maybePop` and are intercepted; an in-form Cancel button must call
/// `Navigator.maybePop` for the same reason. A save path that has already
/// persisted should keep calling `Navigator.pop`, which bypasses the guard.
class DiscardGuard extends StatefulWidget {
  const DiscardGuard({
    super.key,
    required this.isDirty,
    required this.child,
    this.confirmBody,
  });

  final bool Function() isDirty;
  final String? confirmBody;
  final Widget child;

  @override
  State<DiscardGuard> createState() => _DiscardGuardState();
}

class _DiscardGuardState extends State<DiscardGuard> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _confirming) return;
        final navigator = Navigator.of(context);
        if (!widget.isDirty()) {
          navigator.pop(result);
          return;
        }
        _confirming = true;
        final leave = await confirmDiscard(context, body: widget.confirmBody);
        _confirming = false;
        if (leave && mounted) navigator.pop(result);
      },
      child: widget.child,
    );
  }
}

import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Confirm an action that destroys data, or a relationship the user cannot
/// restore on their own — delete, remove, clear, erase, discard, revoke,
/// unlink, deny, or leave. Resolves `true` only on explicit confirmation;
/// cancel and barrier dismiss both resolve `false`.
///
/// Not for merely consequential actions that the same user can undo from the
/// same surface (reconnecting an integration, un-archiving a conversation,
/// replacing an active plan) — a confirm that fires on the recoverable and the
/// irreversible alike teaches the user to dismiss it without reading.
///
/// [confirmLabel] must name the consequence ("Delete", "Leave"), never agree
/// with the question ("OK", "Yes"): the error colour is a second signal that a
/// colour-blind reader may not receive, so the verb has to carry the meaning
/// on its own. Cancel comes first and stays unstyled so the safe action sits
/// where a reflex tap lands.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? body,
  String? cancelLabel,
}) async {
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: body == null ? null : Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cancelLabel ?? l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

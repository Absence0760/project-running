import 'package:flutter/material.dart';

/// Canonical presentation for a create / edit entity form on mobile: a
/// full-screen modal dialog (slide-up, close affordance) hosting [builder]
/// inside a [Scaffold] + [AppBar] + [SafeArea].
///
/// Every "add / edit X" surface routes through here — gear, club, event,
/// goal, gym, manual run, planned-workout edit — so the presentation is
/// identical and no form re-derives the wrapper. Replaces the earlier mix
/// of `showModalBottomSheet` (gear / event / workout-edit) and bare
/// `MaterialPageRoute` pages (club): the sheets fought the soft keyboard
/// (`viewInsets` + `FractionallySizedBox` both reflow during open, the
/// "slow and glitchy" feel) and a plain page lacked the dialog's slide-up +
/// close affordance.
///
/// [title] is read from the caller's context once (the heading lives in the
/// AppBar, not inline in the body). Resolves to whatever the form pops.
Future<T?> showFullScreenForm<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: builder(ctx)),
      ),
    ),
  );
}

/// Standard scrollable chrome for a [showFullScreenForm] child: a 20px
/// inset that grows to clear whichever system UI is active — the soft
/// keyboard (`viewInsets.bottom`, when a field is focused) or the gesture /
/// nav bar (`viewPadding.bottom`, otherwise). They never overlap (the
/// keyboard replaces the nav bar when up), so picking whichever is non-zero
/// is correct; pre-fix the sheets only padded for the keyboard, leaving the
/// Cancel / Save buttons under Samsung's translucent gesture bar. Wraps the
/// children in a [SingleChildScrollView] + stretch [Column].
class FullScreenFormBody extends StatelessWidget {
  const FullScreenFormBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Uppercase muted section label used between field groups on the
/// full-screen forms (goal targets, gym title, …).
class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

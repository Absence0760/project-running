import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// Obscured text field with a show/hide visibility toggle.
///
/// Every password-entry surface (sign-up, sign-in, change-password)
/// uses this instead of a bare `TextField(obscureText: true)` so the
/// reveal affordance and its localized a11y label stay consistent.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? errorText;
  final InputBorder? border;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.errorText,
    this.border,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.labelText,
        border: widget.border,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          tooltip:
              _obscure ? l10n.authShowPassword : l10n.authHidePassword,
          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, IdentityAvatar;

import '../ai_disclosure.dart';
import '../auth_change_aware.dart';
import '../auth_error.dart';
import '../auth_validation.dart';
import '../backup.dart';
import '../exif_strip.dart';
import '../backup_server_client.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../password_change.dart';
import '../preferences.dart';
import '../text_limits.dart';
import '../settings_sync.dart';
import '../widgets/ai_disclosure_notice.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/password_field.dart';
import '../widgets/top_banner.dart';
import 'import_screen.dart';
import 'sign_in_screen.dart';

class SettingsAccountScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;
  final LocalRouteStore? routeStore;
  final SettingsSyncService? settingsSync;

  const SettingsAccountScreen({
    super.key,
    required this.apiClient,
    required this.preferences,
    required this.settingsSync,
    this.runStore,
    this.routeStore,
  });

  @override
  State<SettingsAccountScreen> createState() => _SettingsAccountScreenState();
}

class _SettingsAccountScreenState extends State<SettingsAccountScreen>
    with AuthChangeAware<SettingsAccountScreen> {
  /// The versioned AI-processing consent record (decisions.md § 571). This
  /// is the surface where a runner who accepted an older disclosure — or
  /// none at all — reads the current one and accepts it; the AI route
  /// assistant refuses until they do, and the Coach surface must not nag
  /// about it because the older acceptance covers the Coach fine.
  AiDisclosureRecord _disclosure = const AiDisclosureRecord();
  bool _coachConsentWithdrawing = false;

  /// Something is on record — a withdrawal is meaningful.
  bool get _aiConsentGranted =>
      checkAiDisclosure(_disclosure, kAiDisclosureVersionCoach).ok;

  /// The record covers everything this build can ask for — no acceptance
  /// to offer. Anything less (nothing on record, or an older rung) leaves
  /// the accept control up, so a runner refused by an AI endpoint always
  /// has somewhere to go.
  bool get _aiConsentCurrent =>
      checkAiDisclosure(_disclosure, kAiDisclosureCurrentVersion).ok;
  // In-flight guard for the multi-second account actions (full backup,
  // restore, CSV export, sign-out) so a double-tap can't fire two backup
  // builds / two share sheets / two restore loops.
  bool _accountBusy = false;

  String? _avatarUrl;
  bool _avatarBusy = false;
  final ImagePicker _avatarPicker = ImagePicker();

  String? _displayName;
  bool _displayNameBusy = false;

  // Change-email flow: GoTrue's secure email change confirms from BOTH
  // the old and the new address, so the account email doesn't flip until
  // both links are followed. We surface a persistent "confirmation
  // pending" note rather than treating it as done. Snapshotted at request
  // time so the note is stable regardless of later auth-store churn.
  String? _pendingEmailNew;
  String _pendingEmailOld = '';

  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_onChange);
    _loadAiDisclosure();
    _loadAvatar();
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    super.dispose();
  }

  @override
  ApiClient? get authApi => widget.apiClient;

  /// Sign-out can happen on this very screen (or a session can expire
  /// under it) and the initState-loaded avatar + coach-consent stamp
  /// belong to the departed user — clear them and reload as whoever is
  /// signed in now (the loaders no-op while signed out).
  @override
  void onAuthUserChanged(String? userId) {
    setState(() {
      _disclosure = const AiDisclosureRecord();
      _avatarUrl = null;
    });
    _loadAiDisclosure();
    _loadAvatar();
  }

  Future<void> _loadAiDisclosure() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final record = aiDisclosureFromProfileRow(await api.fetchAiDisclosure());
      if (mounted) setState(() => _disclosure = record);
    } catch (e) {
      // Non-fatal, and fail-closed: an unreadable record leaves the
      // withdrawal control hidden and the accept control offered, which is
      // the safe way round — a runner can always re-accept, and the RPC is
      // monotone so doing so cannot walk a wider acceptance back.
      debugPrint('settings account: AI disclosure lookup failed: $e');
    }
  }

  Future<void> _loadAvatar() async {
    final api = widget.apiClient;
    if (api == null || api.userId == null) return;
    try {
      final profile = await api.fetchMyProfile();
      if (mounted) {
        setState(() {
          _avatarUrl = profile?.avatarUrl;
          _displayName = profile?.displayName;
        });
      }
    } catch (_) {
      // Non-fatal: the tile falls back to the email initial.
    }
  }

  Future<void> _editDisplayName() async {
    final api = widget.apiClient;
    final l10n = AppLocalizations.of(context);
    if (api == null || api.userId == null) {
      showTopBanner(context, l10n.settingsAccountSignInToSync);
      return;
    }
    final ctl = TextEditingController(text: _displayName ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsAccountDisplayName),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: kDisplayNameMaxLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.settingsAccountDisplayName,
            helperText: l10n.settingsAccountDisplayNameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.settingsAccountCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(l10n.settingsAccountSave),
          ),
        ],
      ),
    );
    if (saved == null || !mounted) return;
    final trimmed = saved.trim();
    setState(() => _displayNameBusy = true);
    try {
      await api.updateDisplayName(trimmed);
      if (!mounted) return;
      setState(() => _displayName = trimmed.isEmpty ? null : trimmed);
      showTopBanner(context, l10n.settingsAccountDisplayNameUpdated);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountDisplayNameUpdateFailed);
    } finally {
      if (mounted) setState(() => _displayNameBusy = false);
    }
  }

  Future<void> _pickAvatar() async {
    final api = widget.apiClient;
    final l10n = AppLocalizations.of(context);
    if (api == null || api.userId == null) {
      showTopBanner(context, l10n.settingsAccountSignInToSync);
      return;
    }
    XFile? f;
    try {
      f = await _avatarPicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
        maxHeight: 1024,
      );
    } catch (e) {
      debugPrint('settings account avatar failed: $e');
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
      return;
    }
    if (f == null) return;
    final Uint8List picked;
    try {
      picked = Uint8List.fromList(await f.readAsBytes());
    } catch (e) {
      debugPrint('settings account avatar read failed: $e');
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
      return;
    }
    // Strip EXIF/GPS before the bytes leave the device — the avatars bucket is
    // public with no server-side strip worker, so this is the ONLY strip. The
    // format comes from the bytes, not the picked filename: a HEIC named
    // `.jpg` would otherwise reach the JPEG walker, fail its SOI check, and be
    // uploaded whole with the home coordinate still in it.
    final contentType = detectImageMime(picked);
    if (contentType == null) {
      if (!mounted) return;
      showTopBanner(context, l10n.settingsAccountAvatarUnsupported);
      return;
    }
    if (!mounted) return;
    setState(() => _avatarBusy = true);
    try {
      final clean = stripImageExif(picked, contentType);
      final url = await api.uploadAvatar(bytes: clean, contentType: contentType);
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _avatarBusy = false;
      });
      showTopBanner(context, l10n.settingsAccountAvatarSaved);
    } catch (e) {
      debugPrint('settings account avatar failed: $e');
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      showTopBanner(context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _removeAvatar() async {
    final api = widget.apiClient;
    final l10n = AppLocalizations.of(context);
    if (api == null) return;
    final ok = await confirmDestructive(
      context,
      title: l10n.settingsAccountAvatarRemoveTitle,
      body: l10n.settingsAccountAvatarRemoveConfirm,
      confirmLabel: l10n.settingsAccountAvatarRemove,
      cancelLabel: l10n.settingsAccountCancel,
    );
    if (!ok) return;
    if (!mounted) return;
    setState(() => _avatarBusy = true);
    try {
      await api.removeAvatar();
      if (!mounted) return;
      setState(() {
        _avatarUrl = null;
        _avatarBusy = false;
      });
      showTopBanner(context, l10n.settingsAccountAvatarRemoved);
    } catch (e) {
      debugPrint('settings account avatar failed: $e');
      if (!mounted) return;
      setState(() => _avatarBusy = false);
      showTopBanner(context, l10n.settingsAccountAvatarFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _acceptAiDisclosure() async {
    final api = widget.apiClient;
    if (api == null) return;
    final l10n = AppLocalizations.of(context);
    // The dialog owns the write and reports the record the SERVER stored;
    // a null result is a cancel (or a failure it already surfaced), so
    // nothing here may assume an acceptance landed.
    final recorded = await showAiDisclosureDialog(context, api);
    if (recorded == null || !mounted) return;
    setState(() => _disclosure = recorded);
    showTopBanner(context, l10n.settingsAccountAiConsentAccepted);
  }

  Future<void> _withdrawAiDisclosure() async {
    final api = widget.apiClient;
    if (api == null || _coachConsentWithdrawing) return;
    setState(() => _coachConsentWithdrawing = true);
    final l10n = AppLocalizations.of(context);
    try {
      await api.withdrawAiDisclosureConsent();
      if (!mounted) return;
      setState(() => _disclosure = const AiDisclosureRecord());
      showTopBanner(context, l10n.settingsAccountCoachConsentWithdrawn);
    } catch (e) {
      debugPrint('SettingsAccountScreen AI-consent withdraw failed: $e');
      if (mounted) {
        showTopBanner(
            context,
            l10n.settingsAccountCoachConsentWithdrawFailed(
                friendlyError(l10n, e)));
      }
    } finally {
      if (mounted) setState(() => _coachConsentWithdrawing = false);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _signIn() async {
    final api = widget.apiClient;
    if (api == null) {
      showTopBanner(
          context, AppLocalizations.of(context).settingsAccountBackendNotConfigured);
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _signOut() async {
    final api = widget.apiClient;
    if (api == null || _accountBusy) return;
    setState(() => _accountBusy = true);
    try {
      await api.signOut();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).settingsAccountSignOutFailed);
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  /// Change-password step-up (issue #381, decisions §278). A live access
  /// token alone must never be enough to rotate the password — the dialog
  /// proves possession of the CURRENT password before writing the new one.
  /// An OAuth-only account has no password to prove, so the dialog also
  /// offers the mailed reset link on web's `/auth/reset` as the equivalent
  /// proof. The pure decision lives in `password_change.dart`.
  Future<void> _changePassword() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null) {
      showTopBanner(context, l10n.settingsAccountSignInToSync);
      return;
    }
    final currentCtl = TextEditingController();
    final pwdCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    final pwdFocus = FocusNode();
    final confirmFocus = FocusNode();

    final result = await showDialog<PasswordChangeResult>(
      context: context,
      builder: (ctx) {
        String? error;
        bool saving = false;
        bool sendingReset = false;
        return StatefulBuilder(
          builder: (ctx, setInner) {
            final allFilled = currentCtl.text.isNotEmpty &&
                pwdCtl.text.isNotEmpty &&
                confirmCtl.text.isNotEmpty;

            Future<void> submit() async {
              if (saving || !allFilled) return;
              setInner(() {
                saving = true;
                error = null;
              });
              final res = await changePassword(
                PasswordChangeInput(
                  currentPassword: currentCtl.text,
                  newPassword: pwdCtl.text,
                  confirmPassword: confirmCtl.text,
                ),
                verifyCurrentPassword: api.verifyCurrentPassword,
                updatePassword: (password) async {
                  try {
                    await api.updatePassword(password);
                    return null;
                  } catch (e) {
                    return friendlyError(l10n, e);
                  }
                },
              );
              if (!ctx.mounted) return;
              if (res.ok) {
                Navigator.pop(ctx, res);
                return;
              }
              setInner(() {
                saving = false;
                error = _passwordChangeMessage(l10n, res.reason!, res.detail);
              });
            }

            Future<void> sendReset() async {
              if (sendingReset) return;
              final email = api.userEmail ?? '';
              if (email.isEmpty) return;
              setInner(() {
                sendingReset = true;
                error = null;
              });
              try {
                await api.sendPasswordResetEmail(
                  email: email,
                  redirectTo: _resetRedirect(),
                );
                if (ctx.mounted) Navigator.pop(ctx, null);
                if (mounted) {
                  showTopBanner(
                    context,
                    l10n.settingsAccountResetLinkSent,
                    duration: const Duration(seconds: 5),
                  );
                }
              } catch (e) {
                debugPrint('SettingsAccountScreen reset link failed: $e');
                if (ctx.mounted) {
                  setInner(() {
                    sendingReset = false;
                    error = friendlyError(l10n, e);
                  });
                }
              }
            }

            return AlertDialog(
              title: Text(l10n.settingsAccountChangePassword),
              content: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.settingsAccountPasswordStepUpHint,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: currentCtl,
                      labelText: l10n.settingsAccountCurrentPassword,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setInner(() {}),
                      onSubmitted: (_) => pwdFocus.requestFocus(),
                    ),
                    const SizedBox(height: 8),
                    PasswordField(
                      controller: pwdCtl,
                      focusNode: pwdFocus,
                      labelText: l10n.settingsAccountNewPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setInner(() {}),
                      onSubmitted: (_) => confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 8),
                    PasswordField(
                      controller: confirmCtl,
                      focusNode: confirmFocus,
                      labelText: l10n.settingsAccountConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setInner(() {}),
                      onSubmitted: (_) => submit(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: TextStyle(
                              color: AppSemanticColors.of(ctx).danger)),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: sendingReset ? null : sendReset,
                        child: Text(
                          sendingReset
                              ? l10n.settingsAccountSendingResetLink
                              : l10n.settingsAccountSendResetLink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx, null),
                  child: Text(l10n.settingsAccountCancel),
                ),
                FilledButton(
                  onPressed: (saving || !allFilled) ? null : submit,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.settingsAccountSave),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !result.ok) return;
    // Commits the autofill session so the platform password manager offers
    // to update the stored credential.
    TextInput.finishAutofillContext();
    if (!mounted) return;
    showTopBanner(context, l10n.settingsAccountPasswordUpdated);
  }

  String _passwordChangeMessage(
    AppLocalizations l10n,
    PasswordChangeReason reason,
    String? detail,
  ) {
    switch (reason) {
      case PasswordChangeReason.tooShort:
        return l10n.authErrorPasswordTooShort(kPasswordMinLength);
      case PasswordChangeReason.mismatch:
        return l10n.settingsAccountPasswordsMismatch;
      case PasswordChangeReason.currentMissing:
        return l10n.settingsAccountCurrentPasswordRequired;
      case PasswordChangeReason.currentInvalid:
        return l10n.settingsAccountCurrentPasswordIncorrect;
      case PasswordChangeReason.updateFailed:
        return l10n.settingsAccountPasswordUpdateFailed(detail ?? '');
    }
  }

  /// The web `/auth/reset` URL a mailed reset link should land on — mobile
  /// doesn't host the password-edit form. Mirrors the sign-in screen's
  /// reset flow: `WEB_BASE_URL` with the prod host as the fallback.
  String _resetRedirect() {
    var webBase =
        (dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null)
                ?.trim() ??
            '';
    if (webBase.isEmpty) webBase = 'https://threkir.com';
    if (webBase.endsWith('/')) {
      webBase = webBase.substring(0, webBase.length - 1);
    }
    return '$webBase/auth/reset';
  }

  Future<void> _changeEmail() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final current = api?.userEmail ?? '';
    final emailCtl = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setInner) => AlertDialog(
            title: Text(l10n.settingsAccountChangeEmail),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: l10n.settingsAccountNewEmail,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style:
                          TextStyle(color: AppSemanticColors.of(ctx).danger)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.settingsAccountCancel),
              ),
              FilledButton(
                onPressed: () {
                  final v = emailCtl.text.trim();
                  if (!looksLikeEmail(v) ||
                      v.toLowerCase() == current.toLowerCase()) {
                    setInner(() =>
                        error = l10n.settingsAccountEmailChangeInvalid);
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: Text(l10n.settingsAccountSave),
              ),
            ],
          ),
        );
      },
    );
    if (target == null) return;
    if (!mounted) return;
    try {
      if (api == null) throw Exception('Not authenticated');
      await api.updateEmail(target);
      if (!mounted) return;
      setState(() {
        _pendingEmailOld = current;
        _pendingEmailNew = target;
      });
      showTopBanner(
        context,
        l10n.settingsAccountEmailChangePending(current, target),
      );
    } catch (e) {
      debugPrint('SettingsAccountScreen email update failed: $e');
      if (!mounted) return;
      showTopBanner(context,
          l10n.settingsAccountEmailChangeFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _deleteAccount() async {
    // Re-entry challenge mirroring the web ConfirmDialog `requireText`
    // gate: the user must type their email (or "DELETE" when offline /
    // no email) before the Delete button enables. Apple 5.1.1 +
    // data-loss confirmation — a stray tap can't trigger an
    // irreversible server-side wipe.
    final l10n = AppLocalizations.of(context);
    final email = widget.apiClient?.userEmail ?? '';
    final challengeTarget = email.isEmpty ? 'DELETE' : email;
    final challengeCtl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final met = challengeCtl.text.trim().toLowerCase() ==
              challengeTarget.trim().toLowerCase();
          return AlertDialog(
            title: Text(l10n.settingsAccountDeleteTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsAccountDeleteBody),
                const SizedBox(height: 16),
                TextField(
                  controller: challengeCtl,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: email.isEmpty
                        ? l10n.settingsAccountDeleteChallengeText
                        : l10n.settingsAccountDeleteChallengeEmail(email),
                  ),
                  onChanged: (_) => setInner(() {}),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.settingsAccountCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppSemanticColors.of(ctx).danger,
                  foregroundColor: AppSemanticColors.of(ctx).onDanger,
                ),
                onPressed: met ? () => Navigator.pop(ctx, true) : null,
                child: Text(l10n.settingsAccountDelete),
              ),
            ],
          );
        },
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    try {
      final api = widget.apiClient;
      if (api == null) {
        showTopBanner(context, l10n.settingsAccountDeleteSignInFirst);
        return;
      }
      await api.deleteAccount();
      await api.signOut();
      if (mounted) {
        showTopBanner(context, l10n.settingsAccountDeleted);
        setState(() {});
      }
    } catch (e) {
      debugPrint('SettingsAccountScreen delete account failed: $e');
      if (!mounted) return;
      showTopBanner(
          context, l10n.settingsAccountDeleteFailed(friendlyError(l10n, e)));
    }
  }

  Future<void> _exportRunsCsv() async {
    final l10n = AppLocalizations.of(context);
    final store = widget.runStore;
    final runs = store?.runs ?? const [];
    if (runs.isEmpty) {
      showTopBanner(context, l10n.settingsAccountNoRunsToExport);
      return;
    }
    if (_accountBusy) return;
    setState(() => _accountBusy = true);
    try {
      final buf =
          StringBuffer('date,distance_m,duration_s,pace_s_per_km,source\n');
      for (final r in runs) {
        final pace = r.distanceMetres > 0
            ? (r.duration.inSeconds / (r.distanceMetres / 1000)).round()
            : 0;
        buf.writeln(
          '${r.startedAt.toUtc().toIso8601String()},'
          '${r.distanceMetres.round()},'
          '${r.duration.inSeconds},'
          '$pace,'
          '${r.source.name}',
        );
      }
      final tmp = await getTemporaryDirectory();
      final ts =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${tmp.path}/runs-$ts.csv');
      await file.writeAsString(buf.toString());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        text: l10n.settingsAccountCsvShareText,
      );
    } catch (e) {
      if (mounted) showTopBanner(context, l10n.settingsAccountCsvExportFailed(e));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _exportBackup() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, l10n.settingsAccountBackupSignInFirst);
      return;
    }
    if (_accountBusy) return;
    setState(() => _accountBusy = true);
    showTopBanner(context, l10n.settingsAccountBackupPreparing);
    try {
      final tmp = await getTemporaryDirectory();
      final ts =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${tmp.path}/run-app-backup-$ts.zip');
      final serviceBase = dotenv.env['LIVE_HUB_URL']?.trim() ?? '';
      await BackupService(
        api: api,
        serverClient: serviceBase.isEmpty
            ? null
            : BackupServerClient(baseUrl: serviceBase),
      ).createBackup(outputFile: file, runStore: widget.runStore);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: l10n.settingsAccountBackupShareText,
      );
    } catch (e) {
      if (mounted) showTopBanner(context, l10n.settingsAccountBackupFailed(e));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    final store = widget.runStore;
    if (store == null) {
      showTopBanner(context, l10n.settingsAccountRestoreUnavailable);
      return;
    }
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    final offline = api == null || api.userId == null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsAccountRestoreTitle),
        content: Text(
          offline
              ? l10n.settingsAccountRestoreBodyOffline
              : l10n.settingsAccountRestoreBodyOnline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.settingsAccountCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.settingsAccountRestore),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted || _accountBusy) return;
    setState(() => _accountBusy = true);
    showTopBanner(context, l10n.settingsAccountRestoring);
    try {
      final res = await BackupService(api: api).restore(
        zipFile: File(path),
        runStore: store,
        routeStore: widget.routeStore,
      );
      if (!mounted) return;
      showTopBanner(
        context,
        l10n.settingsAccountRestoreDone(
          res.runsImported,
          res.tracksUploaded,
          res.routesImported,
          res.warnings.isNotEmpty
              ? l10n.settingsAccountRestoreWarningsSuffix(res.warnings.length)
              : '',
        ),
      );
    } catch (e) {
      if (mounted) showTopBanner(context, l10n.settingsAccountRestoreFailed(e));
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final signedIn = widget.apiClient?.userId != null;
    final email = widget.apiClient?.userEmail ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccountTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: signedIn
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                ),
              ),
              title: Text(
                  email.isEmpty ? l10n.settingsAccountOfflineMode : email),
              subtitle: Text(signedIn
                  ? l10n.settingsAccountSignedInSync
                  : l10n.settingsAccountSignInToSync),
              trailing: signedIn
                  ? IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: l10n.settingsAccountSignOut,
                      onPressed: _accountBusy ? null : _signOut,
                    )
                  : FilledButton.tonal(
                      onPressed: _signIn,
                      child: Text(l10n.settingsAccountSignIn),
                    ),
            ),
            if (signedIn)
              ListTile(
                leading: IdentityAvatar(
                  seed: widget.apiClient?.userId ?? email,
                  name: email,
                  size: 40,
                  imageUrl: _avatarUrl,
                ),
                title: Text(l10n.settingsAccountAvatar),
                subtitle: Text(l10n.settingsAccountAvatarHint),
                trailing: _avatarBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: l10n.settingsAccountAvatarRemove,
                            onPressed: _removeAvatar,
                          )
                        : const Icon(Icons.photo_camera),
                onTap: _avatarBusy ? null : _pickAvatar,
              ),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(l10n.settingsAccountDisplayName),
                subtitle: Text(
                  (_displayName != null && _displayName!.isNotEmpty)
                      ? _displayName!
                      : l10n.settingsAccountDisplayNameUnset,
                ),
                trailing: _displayNameBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_outlined),
                onTap: _displayNameBusy ? null : _editDisplayName,
              ),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.settingsAccountSendErrorReports),
              subtitle: Text(l10n.settingsAccountSendErrorReportsSubtitle),
              value: !widget.preferences.sentryOptOut,
              onChanged: (enabled) async {
                await widget.preferences.setSentryOptOut(!enabled);
                if (!mounted) return;
                showTopBanner(
                  context,
                  enabled
                      ? l10n.settingsAccountErrorReportingEnabled
                      : l10n.settingsAccountErrorReportingDisabled,
                );
              },
            ),
            if (signedIn && !_aiConsentCurrent)
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(_aiConsentGranted
                    ? l10n.settingsAccountAiConsentUpdateTitle
                    : l10n.settingsAccountAiConsentGrantTitle),
                subtitle: Text(_aiConsentGranted
                    ? l10n.settingsAccountAiConsentUpdateSubtitle
                    : l10n.settingsAccountAiConsentGrantSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _acceptAiDisclosure,
              ),
            if (signedIn && _aiConsentGranted)
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(l10n.settingsAccountCoachConsentWithdraw),
                subtitle: Text(l10n.settingsAccountCoachConsentActive),
                trailing: _coachConsentWithdrawing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap:
                    _coachConsentWithdrawing ? null : _withdrawAiDisclosure,
              ),
            if (widget.runStore != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.move_to_inbox),
                title: Text(l10n.settingsAccountImport),
                subtitle: Text(l10n.settingsAccountImportSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ImportScreen(
                        apiClient: widget.apiClient,
                        runStore: widget.runStore!,
                        routeStore: widget.routeStore,
                        preferences: widget.preferences,
                        settingsSync: widget.settingsSync,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(l10n.settingsAccountFullBackup),
                subtitle: Text(l10n.settingsAccountFullBackupSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_accountBusy,
                onTap: _exportBackup,
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: Text(l10n.settingsAccountExportCsv),
                subtitle: Text(l10n.settingsAccountExportCsvSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_accountBusy,
                onTap: _exportRunsCsv,
              ),
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: Text(l10n.settingsAccountRestoreTile),
                subtitle: Text(l10n.settingsAccountRestoreTileSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_accountBusy,
                onTap: _restoreBackup,
              ),
            ],
            if (signedIn) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.alternate_email),
                title: Text(l10n.settingsAccountChangeEmail),
                subtitle: _pendingEmailNew == null
                    ? null
                    : Text(l10n.settingsAccountEmailChangePending(
                        _pendingEmailOld, _pendingEmailNew!)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changeEmail,
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(l10n.settingsAccountChangePassword),
                trailing: const Icon(Icons.chevron_right),
                onTap: _changePassword,
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: AppSemanticColors.of(context).danger),
                title: Text(
                  l10n.settingsAccountDeleteAccount,
                  style:
                      TextStyle(color: AppSemanticColors.of(context).danger),
                ),
                subtitle: Text(l10n.settingsAccountDeleteAccountSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: _deleteAccount,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

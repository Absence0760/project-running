import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, IdentityAvatar;

import '../ai_disclosure.dart';
import '../auth_change_aware.dart';
import '../auth_error.dart';
import '../auth_validation.dart';
import '../backup.dart';
import '../exif_strip.dart';
import '../backup_server_client.dart';
import '../export_job.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../password_change.dart';
import '../preferences.dart';
import '../text_limits.dart';
import '../settings_sync.dart';
import '../share_sheet.dart';
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

  /// Transport for the queued Art 20 export rail. Production resolves
  /// it from `LIVE_HUB_URL`; tests inject a fake so the whole
  /// enqueue → poll → resume path can be driven without sockets.
  final BackupServerClient? exportClient;

  const SettingsAccountScreen({
    super.key,
    required this.apiClient,
    required this.preferences,
    required this.settingsSync,
    this.runStore,
    this.routeStore,
    this.exportClient,
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
  /// Last server-built archive that came back short of the account's run
  /// history. Held on the screen rather than only bannered: a truncated
  /// Art. 20 export is a claim the runner has to be able to re-read after
  /// the banner has gone, and the archive itself only says so inside
  /// manifest.json.
  LocalArchiveSummary? _backupLocalShortfall;
  RestoreResult? _lastIncompleteRestore;

  /// The subject's most recent queued Art 20 export, or null when they
  /// have never asked for one. Nothing about it is persisted on the
  /// device: the status endpoint answers for their LATEST export, so an
  /// app killed between asking and finishing finds its way back with no
  /// local state at all (decisions.md § 724).
  ExportJob? _exportJob;
  ExportShortfall? _exportShortfall;
  bool _exportStatusUnreadable = false;
  bool _exportBusy = false;
  int _exportPollFailures = 0;
  Timer? _exportPollTimer;

  /// The last archive this screen handed over came from the on-device
  /// writer, which is narrower than the server export. Held so the
  /// runner can re-read WHICH archive they got after the share sheet
  /// and the banner have gone.
  bool _lastBackupWasOnDevice = false;

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
    unawaited(_resumeExportJob());
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_onChange);
    _exportPollTimer?.cancel();
    _exportPollTimer = null;
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
    // The export card is one subject's data-rights request; leaving it
    // up across a sign-out would show the next account someone else's
    // export state and offer them its download.
    _exportPollTimer?.cancel();
    _exportPollTimer = null;
    setState(() {
      _disclosure = const AiDisclosureRecord();
      _avatarUrl = null;
      _exportJob = null;
      _exportShortfall = null;
      _exportStatusUnreadable = false;
      _exportPollFailures = 0;
      _lastBackupWasOnDevice = false;
    });
    _loadAiDisclosure();
    _loadAvatar();
    unawaited(_resumeExportJob());
  }

  /// Transport for the queued export rail, or null when this build has
  /// no service configured. An unconfigured build says so on the
  /// surface rather than quietly handing over the on-device archive as
  /// though it were the Art 20 export.
  BackupServerClient? _resolveExportClient() {
    final injected = widget.exportClient;
    if (injected != null) return injected.isConfigured ? injected : null;
    String base;
    try {
      base = dotenv.env['LIVE_HUB_URL']?.trim() ?? '';
    } catch (e) {
      debugPrint('SettingsAccountScreen export client unavailable: $e');
      return null;
    }
    if (base.isEmpty) return null;
    return BackupServerClient(baseUrl: base);
  }

  String? get _exportToken {
    final token = widget.apiClient?.currentAccessToken;
    return (token == null || token.isEmpty) ? null : token;
  }

  /// Pick up an export that was already building — or has since
  /// finished — when this screen mounts.
  ///
  /// A phone that queues an export and then goes to the lock screen is
  /// the normal case, not the edge case, so this is the whole resume
  /// mechanism: the status endpoint answers for the subject's LATEST
  /// export, and the one-in-flight index makes that unambiguous, so
  /// nothing has to survive on the device. A read that fails is silent
  /// — a subject who never asked for an export must not be shown an
  /// error about one.
  Future<void> _resumeExportJob() async {
    final client = _resolveExportClient();
    final token = _exportToken;
    if (client == null || token == null) return;
    try {
      final job = await client.fetchLatestExportJob(accessToken: token);
      if (!mounted || job.status == ExportJobStatus.none) return;
      setState(() {
        _exportJob = job;
        _exportShortfall = exportJobShortfall(job);
      });
      if (isExportJobActive(job.status)) _scheduleExportPoll(0);
    } catch (e) {
      debugPrint('SettingsAccountScreen export resume failed: $e');
    }
  }

  /// Ask the server to build the Art 20 archive. Returns as soon as the
  /// job is queued — the build no longer rides this phone's connection,
  /// so the app may be backgrounded or killed from here on.
  Future<void> _requestAccountExport() async {
    final l10n = AppLocalizations.of(context);
    final api = widget.apiClient;
    if (api == null || api.userId == null) {
      showTopBanner(context, l10n.settingsAccountBackupSignInFirst);
      return;
    }
    final client = _resolveExportClient();
    final token = _exportToken;
    if (client == null || token == null) {
      showTopBanner(context, l10n.settingsAccountExportUnavailable);
      return;
    }
    if (_exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final job = await client.enqueueExport(accessToken: token);
      if (!mounted) return;
      setState(() {
        _exportJob = job;
        _exportShortfall = null;
        _exportStatusUnreadable = false;
        _exportPollFailures = 0;
      });
      showTopBanner(context, l10n.settingsAccountExportQueued);
      _scheduleExportPoll(0);
    } on BackupServerError catch (e) {
      // Surfaced, never swallowed: the rail this replaced fell through
      // to the on-device writer on any non-200, so a refused Art 20
      // request reached the subject as a narrower archive they were
      // never told was narrower.
      if (!mounted) return;
      final retry = e.retryAfterSeconds;
      showTopBanner(
        context,
        e.isRateLimited && retry != null
            ? l10n.settingsAccountExportRateLimited(retry)
            : l10n.settingsAccountExportRequestFailed(e.message),
      );
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.settingsAccountExportRequestFailed('$e'));
      }
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  void _scheduleExportPoll(int attempt) {
    _exportPollTimer?.cancel();
    _exportPollTimer = null;
    final job = _exportJob;
    if (job == null || !isExportJobActive(job.status)) return;
    _exportPollTimer =
        Timer(Duration(milliseconds: exportPollDelayMs(attempt)), () {
      _exportPollTimer = null;
      unawaited(_readExportJob(attempt + 1));
    });
  }

  Future<void> _readExportJob(int attempt) async {
    final client = _resolveExportClient();
    final token = _exportToken;
    if (client == null || token == null) return;
    ExportJob job;
    try {
      job = await client.fetchLatestExportJob(accessToken: token);
    } catch (e) {
      // A status read that failed is not an export that failed. Try a
      // few more times before saying anything, and never rewrite the
      // job the screen is showing on the strength of one lost request.
      if (!mounted) return;
      _exportPollFailures += 1;
      if (_exportPollFailures >= 5) {
        setState(() => _exportStatusUnreadable = true);
        return;
      }
      _scheduleExportPoll(attempt);
      return;
    }
    if (!mounted) return;
    final wasBuilding =
        isExportJobActive(_exportJob?.status ?? ExportJobStatus.none);
    setState(() {
      _exportPollFailures = 0;
      _exportStatusUnreadable = false;
      _exportJob = job;
      _exportShortfall = exportJobShortfall(job);
    });
    if (wasBuilding && job.status == ExportJobStatus.ready) {
      // Deliberately no share sheet: this runs on a timer, not on a
      // tap, and a share sheet that opens itself while the phone is in
      // a pocket is worse than a card. The runner taps Download, which
      // also makes the resume case and the finished-while-watching case
      // the same code path.
      showTopBanner(
        context,
        AppLocalizations.of(context).settingsAccountExportReadyBanner(job.count ?? 0),
      );
    }
    _scheduleExportPoll(attempt);
  }

  /// Download a ready export and hand it to the share sheet.
  ///
  /// The URL is minted HERE rather than reused from the card: it is
  /// signed for ten minutes from the read that produced it, and a card
  /// left on screen outlives that window.
  Future<void> _downloadAccountExport() async {
    final l10n = AppLocalizations.of(context);
    final client = _resolveExportClient();
    final token = _exportToken;
    if (client == null || token == null || _exportBusy) return;
    setState(() => _exportBusy = true);
    try {
      final job = await client.fetchLatestExportJob(accessToken: token);
      if (!mounted) return;
      setState(() {
        _exportJob = job;
        _exportShortfall = exportJobShortfall(job);
      });
      final url = job.url;
      if (job.status != ExportJobStatus.ready || url == null) return;
      final tmp = await getTemporaryDirectory();
      final ts =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final ext = job.format == 'csv' ? 'csv' : 'zip';
      final file = File('${tmp.path}/run-app-export-$ts.$ext');
      await client.downloadToFile(url: Uri.parse(url), outputFile: file);
      if (!mounted) return;
      await shareFilesFrom(
        context,
        files: [XFile(file.path)],
        text: l10n.settingsAccountBackupShareText,
      );
      final short = _exportShortfall;
      if (mounted && short != null) {
        showTopBanner(
          context,
          l10n.settingsAccountBackupPartial(short.count, short.total),
        );
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, l10n.settingsAccountExportDownloadFailed('$e'));
      }
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
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
      await shareFilesFrom(
        context,
        files: [XFile(file.path, mimeType: 'text/csv')],
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
      final outcome = await BackupService(api: api)
          .createBackup(outputFile: file, runStore: widget.runStore);
      final localShort = outcome.localShortfall;
      if (mounted) {
        setState(() {
          _backupLocalShortfall = localShort;
          _lastBackupWasOnDevice = true;
        });
      }
      await shareFilesFrom(
        context,
        files: [XFile(file.path)],
        text: l10n.settingsAccountBackupShareText,
      );
      // After the share sheet closes, not before — a banner raised
      // underneath it is a disclosure nobody reads.
      if (mounted && localShort != null) {
        showTopBanner(
          context,
          l10n.settingsAccountBackupTracksPartial(
            localShort.blobsMissing,
            localShort.blobsWanted,
          ),
        );
      }
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
      setState(() =>
          _lastIncompleteRestore = res.archiveIncomplete ? res : null);
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

  bool get _exportJobBuilding =>
      isExportJobActive(_exportJob?.status ?? ExportJobStatus.none);

  Widget _accountNotice({
    required Key key,
    required String text,
    bool emphasis = true,
  }) {
    final theme = Theme.of(context);
    final color =
        emphasis ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            emphasis ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// What the screen may say about the subject's most recent export.
  ///
  /// Every branch is a claim about their data-rights request, so an
  /// unrecognised state has already been turned into `failed` by
  /// `exportJobFromResponse` — there is no branch here that renders a
  /// download for a job with no URL, and none that leaves a job the
  /// client cannot read looking like one still building.
  List<Widget> _accountExportState(AppLocalizations l10n) {
    final widgets = <Widget>[];
    final unsynced = widget.runStore?.unsyncedRuns.length ?? 0;
    if (unsynced > 0 && _resolveExportClient() != null) {
      // The server builds from the cloud rows, so a run still sitting
      // on this device cannot be in the archive. Standing fact about
      // the account, so it is a notice rather than a banner.
      widgets.add(_accountNotice(
        key: const Key('account-export-unsynced'),
        text: l10n.settingsAccountExportUnsyncedWarning(unsynced),
      ));
    }
    final job = _exportJob;
    if (job != null && job.status != ExportJobStatus.none) {
      switch (job.status) {
        case ExportJobStatus.queued:
        case ExportJobStatus.running:
          widgets.add(_accountNotice(
            key: const Key('account-export-building'),
            text: l10n.settingsAccountExportBuildingNotice,
            emphasis: false,
          ));
        case ExportJobStatus.ready:
          widgets.add(_accountNotice(
            key: const Key('account-export-ready'),
            text: l10n.settingsAccountExportReadyNotice,
            emphasis: false,
          ));
          widgets.add(ListTile(
            key: const Key('account-export-download'),
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.settingsAccountExportDownload),
            enabled: !_exportBusy,
            onTap: _downloadAccountExport,
          ));
        case ExportJobStatus.expired:
          widgets.add(_accountNotice(
            key: const Key('account-export-expired'),
            text: l10n.settingsAccountExportExpiredNotice,
          ));
        case ExportJobStatus.stalled:
          widgets.add(_accountNotice(
            key: const Key('account-export-stalled'),
            text: l10n.settingsAccountExportStalledNotice,
          ));
        case ExportJobStatus.failed:
          widgets.add(_accountNotice(
            key: const Key('account-export-failed'),
            text: l10n.settingsAccountExportFailedNotice(
                job.errorCode ?? 'unknown'),
          ));
        case ExportJobStatus.none:
          break;
      }
    }
    if (_exportStatusUnreadable) {
      widgets.add(_accountNotice(
        key: const Key('account-export-status-unreadable'),
        text: l10n.settingsAccountExportStatusUnavailable,
      ));
    }
    final short = _exportShortfall;
    if (short != null) {
      widgets.add(_accountNotice(
        key: const Key('account-export-shortfall'),
        text: l10n.settingsAccountBackupPartialNotice(short.count, short.total),
      ));
    }
    return widgets;
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
                key: const Key('account-export-tile'),
                leading: const Icon(Icons.cloud_download_outlined),
                title: Text(l10n.settingsAccountAccountExport),
                subtitle: Text(l10n.settingsAccountAccountExportSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_exportBusy && !_exportJobBuilding,
                onTap: _requestAccountExport,
              ),
              ..._accountExportState(l10n),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: Text(l10n.settingsAccountFullBackup),
                subtitle: Text(l10n.settingsAccountFullBackupSubtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_accountBusy,
                onTap: _exportBackup,
              ),
              if (_lastBackupWasOnDevice)
                _accountNotice(
                  key: const Key('backup-on-device'),
                  text: l10n.settingsAccountBackupOnDeviceNotice,
                  emphasis: false,
                ),
              if (_backupLocalShortfall != null)
                Padding(
                  key: const Key('backup-tracks-shortfall'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.settingsAccountBackupTracksPartialNotice(
                            _backupLocalShortfall!.blobsMissing,
                            _backupLocalShortfall!.blobsWanted,
                          ),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ),
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
              if (_lastIncompleteRestore != null)
                Padding(
                  key: const Key('restore-incomplete-archive'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.settingsAccountRestoreIncompleteArchive(
                            _lastIncompleteRestore!.runsImported,
                          ),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ),
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

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show StatusPill, TextLane;

import '../auth_error.dart';
import '../audio_cues.dart';
import '../guided_runs.dart';
import '../main.dart' show pendingArmGuidedRun;
import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';

/// Browse the guided-runs library and preview each script.
///
/// Preview only. A run is armed for RECORDING from the Run tab — either from
/// its own picker or by the detail screen's "Use this run", which parks the
/// library id on `pendingArmGuidedRun` for the recorder to drain — and the
/// cues then fire from the L4 block in
/// `run_screen.dart#_onSnapshot` through `audio_cues.dart#announceGuidedCue`
/// — the queueing sibling of the interrupting [speakGuidedCue] this screen's
/// per-cue preview button uses.
class GuidedRunsScreen extends StatelessWidget {
  const GuidedRunsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = guidedRunLibrary(l10n);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.guidedRunsTitle)),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(0, 8, 0, 8 + bottomInset),
        itemCount: library.length,
        itemBuilder: (context, i) {
          return _GuidedRunCard(run: library[i]);
        },
      ),
    );
  }
}

class _GuidedRunCard extends StatelessWidget {
  final GuidedRun run;
  const _GuidedRunCard({required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final minutes = (run.durationSec / 60).round();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GuidedRunDetailScreen(run: run),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(
                    label: l10n.guidedRunMinutesBadge(minutes),
                    foreground: theme.colorScheme.onPrimaryContainer,
                    fill: theme.colorScheme.primaryContainer,
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 8),
              Text(run.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                run.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(run.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                l10n.guidedRunCueCount(run.cues.length),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GuidedRunDetailScreen extends StatefulWidget {
  final GuidedRun run;
  final AudioCues? audioCues;

  const GuidedRunDetailScreen({
    super.key,
    required this.run,
    this.audioCues,
  });

  @override
  State<GuidedRunDetailScreen> createState() => _GuidedRunDetailScreenState();
}

class _GuidedRunDetailScreenState extends State<GuidedRunDetailScreen> {
  late final AudioCues _audioCues = widget.audioCues ?? AudioCues();

  String _fmtMmSs(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Arm this script on the recorder and get out of the way: the Run tab is
  /// several pops down, so the shell has to come back to the front before
  /// the tab switch HomeScreen makes is visible.
  void _useThisRun() {
    pendingArmGuidedRun.value = widget.run.id;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _previewCue(String text) async {
    try {
      await _audioCues.speakGuidedCue(text);
    } catch (e) {
      debugPrint('guided run preview error: $e');
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).guidedRunPreviewError(friendlyError(AppLocalizations.of(context), e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.run.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.run.subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 12),
          Text(widget.run.description,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _useThisRun,
            icon: const Icon(Icons.headset_mic_outlined),
            label: Text(l10n.guidedRunUseThisRun),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.guidedRunFullScript,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.06,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final cue in widget.run.cues)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: TextLane(
                  width: 56,
                  child: Text(
                    _fmtMmSs(cue.atSec),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                title: Text(cue.text),
                trailing: IconButton(
                  tooltip: l10n.guidedRunPreviewCue,
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => _previewCue(cue.text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

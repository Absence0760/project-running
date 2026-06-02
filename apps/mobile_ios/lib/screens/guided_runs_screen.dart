import 'package:flutter/material.dart';

import '../audio_cues.dart';
import '../guided_runs.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/top_banner.dart';

/// Browse the guided-runs library and preview each script. The
/// actual cue-firing during a recorded run hooks into the recorder
/// via `audio_cues.dart#speakGuidedCue` — the integration into the
/// L0-L4 recording stack is a follow-up task; this screen is the
/// surface today.
class GuidedRunsScreen extends StatelessWidget {
  const GuidedRunsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = guidedRunLibrary(l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccountGuidedRuns)),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.guidedRunMinutesBadge(minutes),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              Text(run.description, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                l10n.guidedRunCueCount(run.cues.length),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
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

  Future<void> _previewCue(String text) async {
    try {
      await _audioCues.speakGuidedCue(text);
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, AppLocalizations.of(context).guidedRunPreviewError('$e'));
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
                color: theme.colorScheme.outline,
              )),
          const SizedBox(height: 12),
          Text(widget.run.description,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
          const SizedBox(height: 24),
          Text(
            l10n.guidedRunFullScript,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
              letterSpacing: 0.06,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final cue in widget.run.cues)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: SizedBox(
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

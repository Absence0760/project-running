import 'package:core_models/core_models.dart' show ActivityType;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../activity_type_labels.dart';
import '../auth_error.dart';
import '../challenge_goal.dart';
import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../preferences.dart';
import '../rate_limit_message.dart';
import '../social_service.dart';
import '../typed_decimal.dart';
import 'challenge_progress_bar.dart';
import 'full_screen_form.dart';

/// The metric vocabulary `challenges_metric_ck` admits, in the order web's
/// `ChallengeEditor.svelte` lists it.
const List<String> kChallengeMetrics = [
  'distance',
  'duration',
  'vert',
  'activity_count',
  'streak_days',
];

/// The scope vocabulary `challenges_scope_ck` admits.
const List<String> kChallengeScopes = [
  'individual',
  'club_vs_club',
  'group_goal',
];

/// The unit a goal for [metric] is typed in, named in the reader's language.
///
/// The kind comes from [challengeGoalUnit] (the shared pair); only the
/// resolution to a displayable label lives here, because two of the five are
/// localised words and the other two are the unit-preference symbols.
String challengeGoalSuffix(
  AppLocalizations l10n,
  String metric,
  DistanceUnit unit,
) {
  switch (challengeGoalUnit(metric)) {
    case ChallengeGoalUnit.hours:
      return l10n.challengesSuffixHours;
    case ChallengeGoalUnit.elevation:
      return UnitFormat.elevationLabel(unit);
    case ChallengeGoalUnit.activities:
      return l10n.challengesSuffixActivities;
    case ChallengeGoalUnit.days:
      return l10n.challengesSuffixDays;
    case ChallengeGoalUnit.distance:
      return UnitFormat.distanceLabel(unit);
  }
}

/// Show the "Create challenge" form as a full-screen dialog. Resolves to the
/// new challenge's id, or null when the author backed out.
///
/// Mirrors the create half of web's `ChallengeEditor.svelte` — title,
/// description, metric, scope, goal, activity type, club anchor, window.
/// Editing an existing challenge stays web-only per § 24. Presentation goes
/// through [showFullScreenForm], the shared create/edit-entity wrapper, so
/// the discard guard and the keyboard / nav-bar insets come with it.
Future<String?> showChallengeFormSheet(
  BuildContext context, {
  required SocialService social,
}) {
  final formKey = GlobalKey<_ChallengeFormState>();
  return showFullScreenForm<String>(
    context,
    title: AppLocalizations.of(context).challengesCreate,
    isDirty: () => formKey.currentState?.isDirty ?? false,
    builder: (_) => _ChallengeForm(key: formKey, social: social),
  );
}

class _ChallengeForm extends StatefulWidget {
  final SocialService social;
  const _ChallengeForm({super.key, required this.social});

  @override
  State<_ChallengeForm> createState() => _ChallengeFormState();
}

class _ChallengeFormState extends State<_ChallengeForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _goal = TextEditingController();

  String _metric = 'distance';
  String _scope = 'individual';
  String? _activityType;
  String? _clubId;
  late DateTime _starts;
  late DateTime _ends;
  bool _busy = false;

  /// Clubs the author may anchor the challenge to. The insert policy only
  /// admits a club anchor from an admin of that club, so offering the rest
  /// would offer a choice the server refuses.
  List<ClubView> _adminClubs = const [];

  String? _titleError;
  String? _goalError;
  String? _windowError;
  String? _error;

  late final String _initialSnapshot;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Both bounds are truncated to the minute the pickers offer, so the
    // default window is exactly 30 days rather than 30 days less however many
    // seconds happened to be on the clock — which is a whole active day off
    // the streak ceiling the goal field states.
    _starts = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    _ends = DateTime(now.year, now.month, now.day + 30, now.hour, now.minute);
    _initialSnapshot = _snapshot();
    _loadClubs();
  }

  /// L4 auxiliary: the club anchor is optional, so a failed read leaves the
  /// picker absent rather than blocking the form or raising an error.
  Future<void> _loadClubs() async {
    try {
      final clubs = await widget.social.fetchMyClubs();
      if (!mounted) return;
      setState(() => _adminClubs = clubs.where((c) => c.isAdmin).toList());
    } catch (e) {
      debugPrint('challenge form: club load failed: $e');
    }
  }

  String _snapshot() => [
        _title.text,
        _description.text,
        _goal.text,
        _metric,
        _scope,
        _activityType ?? '',
        _clubId ?? '',
        _starts.toIso8601String(),
        _ends.toIso8601String(),
      ].join('|');

  bool get isDirty => _snapshot() != _initialSnapshot;

  int get _startMs => _starts.millisecondsSinceEpoch;
  int get _endMs => _ends.millisecondsSinceEpoch;
  int get _streakCeiling => maxStreakDaysInWindow(_startMs, _endMs);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _pickWindowBound({required bool start}) async {
    final current = start ? _starts : _ends;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      final picked =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (start) {
        _starts = picked;
      } else {
        _ends = picked;
      }
      _windowError = null;
    });
  }

  // club_vs_club aggregates across many clubs, so it never anchors to a
  // single club; drop the anchor the moment that scope is picked, mirroring
  // the web editor's effect and the `challenges_scope_club_ck` constraint.
  void _pickScope(String next) {
    if (_scope == next) return;
    setState(() {
      _scope = next;
      if (next == 'club_vs_club') _clubId = null;
    });
  }

  void _pickMetric(String next) {
    if (_metric == next) return;
    setState(() {
      _metric = next;
      // The typed number meant the previous metric's unit; a 100 that meant
      // kilometres must not silently become 100 hours.
      _goal.clear();
      _goalError = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim();

    // Validate every field in one pass so each invalid one is flagged inline
    // at once (the goal_editor_sheet idiom), rather than one attempt each.
    final titleError = title.isEmpty ? l10n.challengesErrTitle : null;

    // `challenges_window_ck` refuses ends_at <= starts_at with a 23514 that
    // names neither bound. Catching it here is the only way the author is
    // told which end to move. Graded first: the goal's own window rule reads
    // off the same two bounds, so an inverted window would otherwise report
    // a nonsense ceiling of zero days beside the real complaint.
    final windowError =
        _ends.isAfter(_starts) ? null : l10n.challengesErrWindow;

    num? goal;
    String? goalError;
    final goalText = _goal.text.trim();
    if (goalText.isNotEmpty) {
      final typed = parseTypedDecimal(goalText);
      if (typed == null) {
        goalError = l10n.challengesErrGoal;
      } else {
        final stored = challengeGoalToStored(typed, _metric, activeDistanceUnit);
        switch (checkChallengeGoal(stored, _metric, _startMs, _endMs)) {
          case ChallengeGoalRefusal.notPositive:
            goalError = l10n.challengesErrGoal;
          case ChallengeGoalRefusal.exceedsWindow:
            // An inverted window carries its own message and moving the end
            // is the fix for both, so a ceiling of zero days beside it is
            // noise rather than a second thing to correct.
            goalError = windowError == null
                ? l10n.challengesGoalStreakCeiling(_streakCeiling)
                : null;
          case null:
            goal = stored;
        }
      }
    }

    setState(() {
      _titleError = titleError;
      _goalError = goalError;
      _windowError = windowError;
    });
    if (titleError != null || goalError != null || windowError != null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.social.createChallenge(
        title: title,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        metric: _metric,
        scope: _scope,
        goalValue: goal,
        activityType: _activityType,
        clubId: _clubId,
        startsAt: _starts,
        endsAt: _ends,
      );
      if (!mounted) return;
      Navigator.of(context).pop<String?>(id);
    } catch (e) {
      debugPrint('challenge create failed: $e');
      if (!mounted) return;
      // The create_challenge throttle (migration 20270610_001) raises a
      // P0001 carrying the bucket and the wait. It has to win over
      // friendlyError, whose rate-limited branch collapses it into a generic
      // "too many attempts" naming neither (decisions § 747).
      String? friendly;
      if (e is PostgrestException) {
        friendly =
            rateLimitErrorMessage(l10n, code: e.code, message: e.message);
      }
      setState(() {
        _busy = false;
        _error = friendly ?? friendlyError(l10n, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tag = localeToTag(Localizations.localeOf(context));
    final unit = activeDistanceUnit;
    return FullScreenFormBody(
      children: [
        TextField(
          key: const Key('challenge-title'),
          controller: _title,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: l10n.challengesTitleLabel,
            errorText: _titleError,
          ),
          onChanged: (_) {
            if (_titleError != null) setState(() => _titleError = null);
          },
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('challenge-description'),
          controller: _description,
          maxLines: 3,
          maxLength: 2000,
          decoration:
              InputDecoration(labelText: l10n.challengesDescriptionLabel),
        ),
        const SizedBox(height: 12),
        Text(l10n.challengesMetricLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final metric in kChallengeMetrics)
              ChoiceChip(
                label: Text(challengeMetricLabel(l10n, metric)),
                selected: _metric == metric,
                onSelected: (_) => _pickMetric(metric),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.challengesScopeLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final scope in kChallengeScopes)
              ChoiceChip(
                label: Text(_scopeLabel(l10n, scope)),
                selected: _scope == scope,
                onSelected: (_) => _pickScope(scope),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('challenge-goal'),
          controller: _goal,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: typedDecimalInputFormatters,
          decoration: InputDecoration(
            labelText: l10n.challengesGoalOptional,
            suffixText: challengeGoalSuffix(l10n, _metric, unit),
            errorText: _goalError,
          ),
          onChanged: (_) => setState(() => _goalError = null),
        ),
        for (final hint in _goalHints(l10n, unit)) ...[
          const SizedBox(height: 4),
          Text(hint, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _activityType,
          decoration:
              InputDecoration(labelText: l10n.challengesActivityTypeLabel),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(l10n.challengesActivityAny),
            ),
            for (final a in ActivityType.values)
              DropdownMenuItem<String?>(
                value: a.name,
                child: Text(activityTypeLabel(l10n, a)),
              ),
          ],
          onChanged: (v) => setState(() => _activityType = v),
        ),
        if (_scope != 'club_vs_club' && _adminClubs.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _clubId,
            decoration: InputDecoration(labelText: l10n.challengesClubLabel),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l10n.challengesClubNone),
              ),
              for (final c in _adminClubs)
                DropdownMenuItem<String?>(
                  value: c.row.id,
                  child: Text(c.row.name),
                ),
            ],
            onChanged: (v) => setState(() => _clubId = v),
          ),
        ],
        const SizedBox(height: 12),
        _windowRow(
          label: l10n.challengesStartLabel,
          value: formatDateTime(_starts, tag),
          onTap: () => _pickWindowBound(start: true),
        ),
        const SizedBox(height: 8),
        _windowRow(
          label: l10n.challengesEndLabel,
          value: formatDateTime(_ends, tag),
          onTap: () => _pickWindowBound(start: false),
          errorText: _windowError,
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.maybePop(context),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.challengesCreate),
            ),
          ],
        ),
      ],
    );
  }

  /// The readback that makes a mistyped goal visible before it is stored, plus
  /// the streak ceiling stated up front rather than only on a refusal. The
  /// readback is offered only where a conversion happened — for the two
  /// counting metrics the typed number IS the stored one, so echoing it back
  /// says nothing.
  List<String> _goalHints(AppLocalizations l10n, DistanceUnit unit) {
    final out = <String>[];
    final typed = parseTypedDecimal(_goal.text.trim());
    if (typed != null && typed > 0 && _metric != 'activity_count' &&
        _metric != 'streak_days') {
      final stored = challengeGoalToStored(typed, _metric, unit);
      out.add(l10n.challengesGoalPreview(
          challengeValueLabel(l10n, _metric, stored)));
    }
    if (_metric == 'streak_days' && _streakCeiling > 0) {
      out.add(l10n.challengesGoalStreakCeiling(_streakCeiling));
    }
    return out;
  }

  Widget _windowRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    String? errorText,
  }) {
    return Semantics(
      button: true,
      // excludeSemantics drops the decorator's own nodes, so the error has to
      // be spoken here or a screen reader hears the row as merely unchanged.
      label: errorText == null
          ? '$label, $value'
          : '$label, $value, $errorText',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            suffixIcon: const Icon(Icons.event),
          ),
          child: Text(value),
        ),
      ),
    );
  }

  String _scopeLabel(AppLocalizations l10n, String scope) {
    switch (scope) {
      case 'club_vs_club':
        return l10n.challengesScopeClubVsClub;
      case 'group_goal':
        return l10n.challengesScopeGroupGoal;
      case 'individual':
      default:
        return l10n.challengesScopeIndividual;
    }
  }
}

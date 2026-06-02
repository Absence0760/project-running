import 'package:flutter/material.dart';

import '../l10n/date_format.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/locale_support.dart';
import '../social_service.dart';

/// Modal bottom sheet for creating a new event under a club. Mirrors
/// the web `EventEditor.svelte` (one-off / weekly / biweekly / monthly).
Future<String?> showEventFormSheet(
  BuildContext context, {
  required SocialService social,
  required String clubId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EventForm(social: social, clubId: clubId),
  );
}

class _EventForm extends StatefulWidget {
  final SocialService social;
  final String clubId;
  const _EventForm({required this.social, required this.clubId});

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _meetLabel = TextEditingController();
  final _distanceKm = TextEditingController();
  final _durationMin = TextEditingController();
  DateTime _starts = DateTime.now().add(const Duration(days: 1, hours: 1));
  String _recurrence = 'none'; // none | weekly | biweekly | monthly
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _meetLabel.dispose();
    _distanceKm.dispose();
    _durationMin.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _starts,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_starts),
    );
    if (time == null || !mounted) return;
    setState(() {
      _starts = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty || _busy) return;
    final distance = double.tryParse(_distanceKm.text.trim());
    final duration = int.tryParse(_durationMin.text.trim());
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Recurrence mapping mirrors `apps/web/src/lib/recurrence.ts`:
      // weekly → FREQ=WEEKLY, biweekly → WEEKLY+INTERVAL=2 (we collapse
      // to "weekly_alt" via a byday hint for v1), monthly → MONTHLY.
      String? freq;
      String? byday;
      switch (_recurrence) {
        case 'weekly':
          freq = 'weekly';
          break;
        case 'biweekly':
          freq = 'biweekly';
          break;
        case 'monthly':
          freq = 'monthly';
          break;
      }
      if (freq != null) {
        // ISO weekday byday hint for repeat-on-same-DOW behaviour.
        const dow = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
        byday = dow[(_starts.weekday - 1) % 7];
      }
      await widget.social.createEvent(
        clubId: widget.clubId,
        title: title,
        startsAt: _starts,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        durationMin: duration,
        meetLabel:
            _meetLabel.text.trim().isEmpty ? null : _meetLabel.text.trim(),
        distanceM: distance == null ? null : distance * 1000,
        recurrenceFreq: freq,
        // `recurrence_byday` is a text[] column — wrap the single
        // weekday code in a one-element list so postgrest receives a
        // JSON array, not a bare string.
        recurrenceByDay: byday == null ? null : [byday],
      );
      if (!mounted) return;
      Navigator.of(context).pop<String?>('ok');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.eventFormTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.eventFormTitleLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDateTime,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.eventFormStartsAt,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.event),
                ),
                child: Text(formatDateTime(
                    _starts, localeToTag(Localizations.localeOf(context)))),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: l10n.eventFormDescriptionLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _meetLabel,
              maxLength: 120,
              decoration: InputDecoration(
                labelText: l10n.eventFormMeetLabel,
                hintText: l10n.eventFormMeetHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _distanceKm,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.eventFormDistanceLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _durationMin,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.eventFormDurationLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.eventFormRecurrence, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final option in [
                  ('none', l10n.eventFormRecurOneOff),
                  ('weekly', l10n.eventFormRecurWeekly),
                  ('biweekly', l10n.eventFormRecurBiweekly),
                  ('monthly', l10n.eventFormRecurMonthly),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _recurrence == option.$1,
                    onSelected: (_) =>
                        setState(() => _recurrence = option.$1),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(l10n.eventFormCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.eventFormCreate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

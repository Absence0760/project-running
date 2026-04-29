import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';

import '../training.dart';

/// Month-by-month calendar projection of a training plan, mirroring the
/// web's `PlanCalendar.svelte`. Each day cell shows the workout kind +
/// target distance when one is scheduled; completed workouts get a
/// green tick; out-of-month / out-of-plan days are dimmed.
///
/// `onSelect` is invoked when the user taps a workout cell. Hosts pass
/// the same handler they use for the weekly grid (push the workout
/// detail screen).
class PlanCalendar extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final List<PlanWorkoutRow> workouts;
  final void Function(PlanWorkoutRow workout)? onSelect;

  const PlanCalendar({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.workouts,
    this.onSelect,
  });

  @override
  State<PlanCalendar> createState() => _PlanCalendarState();
}

class _PlanCalendarState extends State<PlanCalendar> {
  late int _currentIdx = _initialIdx();

  List<({int year, int month})> get _months {
    final out = <({int year, int month})>[];
    var y = widget.startDate.year;
    var m = widget.startDate.month - 1; // 0-indexed
    final ey = widget.endDate.year;
    final em = widget.endDate.month - 1;
    while (y < ey || (y == ey && m <= em)) {
      out.add((year: y, month: m));
      m += 1;
      if (m > 11) {
        m = 0;
        y += 1;
      }
    }
    return out;
  }

  int _initialIdx() {
    final today = DateTime.now();
    final m = _months;
    final idx = m.indexWhere(
        (e) => e.year == today.year && e.month == today.month - 1);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = _months;
    if (months.isEmpty) return const SizedBox.shrink();
    final current = months[_currentIdx];
    final today = _toIso(DateTime.now());

    final byDate = <String, PlanWorkoutRow>{
      for (final w in widget.workouts) _toIso(w.scheduledDate): w,
    };

    final cells = _buildGrid(current.year, current.month);
    final startIso = _toIso(widget.startDate);
    final endIso = _toIso(widget.endDate);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentIdx > 0
                    ? () => setState(() => _currentIdx -= 1)
                    : null,
                tooltip: 'Previous month',
              ),
              Text(
                '${_monthLabel(current.month)} ${current.year}',
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentIdx < months.length - 1
                    ? () => setState(() => _currentIdx += 1)
                    : null,
                tooltip: 'Next month',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in _dow)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Render cells in rows of 7. Use a Column-of-Rows rather than
          // GridView so the cells size to their content (title + pill +
          // distance), which would otherwise force a fixed aspect ratio.
          for (var r = 0; r < cells.length; r += 7)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: _buildCell(
                        theme,
                        cells[r + i],
                        byDate[cells[r + i].iso],
                        today,
                        startIso,
                        endIso,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(
    ThemeData theme,
    _Cell cell,
    PlanWorkoutRow? wo,
    String today,
    String startIso,
    String endIso,
  ) {
    final inPlan = cell.iso.compareTo(startIso) >= 0 &&
        cell.iso.compareTo(endIso) <= 0;
    final isToday = cell.iso == today;
    final outOfMonth = !cell.inMonth;
    final hasWorkout = wo != null && inPlan;

    final kind = wo == null ? null : workoutKindFromDb(wo.kind);
    final kindColor = kind == null ? null : _kindColor(theme, kind);
    final isDone = hasWorkout && wo.completedRunId != null;

    final base = Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: !inPlan
            ? Colors.transparent
            : (isDone
                ? theme.colorScheme.tertiaryContainer
                : theme.colorScheme.surfaceContainerHigh),
        border: Border.all(
          color: !inPlan
              ? Colors.transparent
              : (isToday ? theme.colorScheme.primary : theme.dividerColor),
          width: isToday ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      foregroundDecoration: hasWorkout
          ? BoxDecoration(
              border: Border(
                left: BorderSide(color: kindColor!, width: 3),
              ),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      constraints: const BoxConstraints(minHeight: 56),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${cell.day}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: outOfMonth
                    ? theme.colorScheme.outline.withValues(alpha: 0.4)
                    : theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (hasWorkout) ...[
            Text(
              workoutKindLabel(kind!).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: kindColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (wo.targetDistanceM != null && wo.kind != 'rest')
              Text(
                fmtKm(wo.targetDistanceM, 1),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 9,
                ),
              ),
            if (isDone)
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(Icons.check_circle,
                    size: 11, color: theme.colorScheme.tertiary),
              ),
          ],
        ],
      ),
    );

    if (!hasWorkout) return Opacity(opacity: outOfMonth ? 0.55 : 1, child: base);

    return Opacity(
      opacity: outOfMonth ? 0.55 : 1,
      child: InkWell(
        onTap: widget.onSelect == null ? null : () => widget.onSelect!(wo),
        borderRadius: BorderRadius.circular(6),
        child: base,
      ),
    );
  }

  static Color _kindColor(ThemeData theme, WorkoutKind k) {
    switch (k) {
      case WorkoutKind.easy:
      case WorkoutKind.recovery:
        return theme.colorScheme.outline;
      case WorkoutKind.long:
      case WorkoutKind.race:
        return theme.colorScheme.primary;
      case WorkoutKind.tempo:
        return const Color(0xFFC98ECF);
      case WorkoutKind.interval:
        return const Color(0xFFD97A54);
      case WorkoutKind.marathonPace:
        return const Color(0xFFE6A96B);
      case WorkoutKind.rest:
        return theme.dividerColor;
    }
  }

  static const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String _monthLabel(int m) {
    const labels = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return labels[m];
  }

  static String _toIso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  /// Build the 6-row × 7-col cell grid for the given month, padded with
  /// trailing days from the previous and following months. Monday-first.
  List<_Cell> _buildGrid(int year, int month) {
    final first = DateTime(year, month + 1, 1); // 1-indexed month
    final last = DateTime(year, month + 2, 0); // last day of this month
    final lastDay = last.day;
    // Monday-first: first.weekday is Mon=1..Sun=7 → leadDow 0..6
    final leadDow = (first.weekday - 1) % 7;

    final cells = <_Cell>[];
    final prevLast = DateTime(year, month + 1, 0).day;
    for (var i = leadDow; i > 0; i--) {
      final d = prevLast - i + 1;
      final pm = month == 0 ? 11 : month - 1;
      final py = month == 0 ? year - 1 : year;
      cells.add(_Cell(
        iso: _isoFromYmd(py, pm, d),
        day: d,
        inMonth: false,
      ));
    }
    for (var d = 1; d <= lastDay; d++) {
      cells.add(_Cell(
        iso: _isoFromYmd(year, month, d),
        day: d,
        inMonth: true,
      ));
    }
    final remainder = cells.length % 7;
    if (remainder != 0) {
      final trail = 7 - remainder;
      for (var d = 1; d <= trail; d++) {
        final nm = month == 11 ? 0 : month + 1;
        final ny = month == 11 ? year + 1 : year;
        cells.add(_Cell(
          iso: _isoFromYmd(ny, nm, d),
          day: d,
          inMonth: false,
        ));
      }
    }
    return cells;
  }

  static String _isoFromYmd(int y, int monthZero, int d) {
    final mm = (monthZero + 1).toString().padLeft(2, '0');
    final dd = d.toString().padLeft(2, '0');
    final yy = y.toString().padLeft(4, '0');
    return '$yy-$mm-$dd';
  }
}

class _Cell {
  final String iso;
  final int day;
  final bool inMonth;
  const _Cell({required this.iso, required this.day, required this.inMonth});
}

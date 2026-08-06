// Source-scan guard for issue #666 C8: there is ONE run row.
//
// The same run had rendered two ways on adjacent surfaces. Fitness -> Runs drew
// a `Card` + `ListTile` with a 72x40 track thumbnail, a signature-coloured
// activity icon, a bold `titleMedium` distance, a `date - duration - activity -
// vert` subtitle and a stacked pace value in the trailing slot. Profile -> Runs
// drew no card, `Divider(height: 1)` separators, a 56x40 thumbnail, an
// `outline`-grey icon at 16 rather than 18, an unstyled distance, no vert chip
// and the pace crammed into the subtitle — beneath a comment claiming it
// *mirrors* the other one. A stale claim of parity is worse than none, because
// the next author reads it and believes it.
//
// Following §509's method: the set of row-shaped widgets is closed against a map
// whose VALUES are the reason each residual one is not a run row, so a third
// shape has to argue for itself rather than appear.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Surfaces that list runs. Each must draw the shared row.
const _runListSurfaces = <String>[
  'lib/screens/runs_screen.dart',
  'lib/screens/profile_screen.dart',
  'lib/screens/period_summary_screen.dart',
];

/// Files allowed to mount a run thumbnail outside the shared row, mapped to the
/// reason. Anything else doing it is the drift this closed.
///
/// Re-measuring C8 found a FOURTH shape the audit had not counted —
/// `period_summary_screen`'s own `_RunTile`, a Card + ListTile with a
/// CircleAvatar, an unstyled distance, a bullet separator where the others use a
/// middot, and a plain bodySmall trailing. It was migrated rather than excused.
const _thumbnailOutsideTheRow = <String, String>{
  'lib/screens/feed_screen.dart':
      'a feed post, not a list row: a full-width map above the actor, the '
          'kudos and the comment count. It shares the thumbnail widget, not '
          'the row.',
};

/// The one surface that lists activities and must NOT take the run row, and why
/// — pinned in both directions, so neither adopting it nor forking a run list
/// out of it can happen quietly.
const _crossModalList = 'lib/widgets/activity_timeline_list.dart';

/// The leading-slot width the shared row owns. A literal one anywhere else is
/// how the two lists came to show the same thumbnail at two sizes.
final _leadingSizedBox = RegExp(r'width:\s*(56|72)\s*,\s*$');

Iterable<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('every run list draws the shared row', () {
    for (final path in _runListSurfaces) {
      expect(File(path).existsSync(), isTrue,
          reason: '$path is guarded but missing — if it moved, move the entry');
      expect(File(path).readAsStringSync(), contains('RunListTile.'),
          reason: '$path lists runs but builds its own row');
    }
  });

  test('no surface mounts a run thumbnail outside the shared row', () {
    final found = <String>{};
    for (final file in _dartFiles()) {
      if (file.path.endsWith('run_list_tile.dart')) continue;
      if (file.path.endsWith('run_track_preview.dart')) continue;
      if (file.readAsStringSync().contains('RunTrackPreview(')) {
        found.add(file.path);
      }
    }
    expect(found, _thumbnailOutsideTheRow.keys.toSet(),
        reason: 'a run thumbnail outside the shared row is how the two lists '
            'came to size it differently. Take RunListTile, or add the file to '
            '_thumbnailOutsideTheRow with the reason it is a different '
            'surface.');
  });

  test('the cross-modal activity list stays cross-modal', () {
    final source = File(_crossModalList).readAsStringSync();
    expect(source.contains('RunListTile'), isFalse,
        reason: '$_crossModalList renders runs, lifts and meals off the '
            'activities view\'s thin summary jsonb, which carries no '
            'track_url for a thumbnail to read, and its tinted avatar is what '
            'names the modality. Adopting the run row here would delete the '
            'cross-modal axis (§509\'s deliberately-left set).');
    expect(source.contains('_ActivityRowTile'), isTrue,
        reason: 'and forking a run list out of it would reopen C8');
  });

  test('no surface re-declares the shared row', () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      if (file.path.endsWith('run_list_tile.dart')) continue;
      if (file.readAsStringSync().contains('class RunListTile')) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'a local shadow satisfies every other rule here while '
            'reopening the drift: ${offenders.join(', ')}');
  });

  test('the leading-slot width lives in one place', () {
    final offenders = <String>[];
    for (final file in _dartFiles()) {
      if (file.path.endsWith('run_list_tile.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!_leadingSizedBox.hasMatch(lines[i])) continue;
        final window = lines.sublist(i, (i + 3).clamp(0, lines.length));
        if (window.any((l) =>
            l.contains('RunTrackPreview') || l.contains('TrackPreview('))) {
          offenders.add('${file.path}:${i + 1} ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a run thumbnail sized outside the shared row is how the same '
            'run came to render at 72x40 on one list and 56x40 on the next — '
            'take kRunTileLeadingWidth:\n${offenders.join('\n')}');
  });
}

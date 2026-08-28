// Parity-matrix audit. Walks `docs/product/parity.md`, parses every data row,
// and fails on the drift patterns that come up most often:
//
//   1. Row column count wrong (not 7 = Feature + 5 platforms + Notes).
//   2. Platform cell uses a symbol outside the legal set
//      `✓ | ✗ | Partial | N/A`.
//   3. Cell marked `Partial` with an empty Notes column, in any column
//      but iOS. (`N/A` cells are exempt — most "wrist can't render KML"
//      rows are self-evident from the feature title; require Notes for
//      `Partial` where the reader genuinely can't guess what shipped.
//      The iOS column is exempt because its cells are derived rather
//      than observed and the document explains the whole column once —
//      see decisions § 739; a per-row restatement there is the habit
//      that sweep removed, not a missing explanation.)
//   4. A line that opens with a pipe and belongs to no table. It renders
//      as raw pipes in a paragraph, so a reader sees it is broken, but
//      every row under it had stopped existing in silence.
//
// None of the four can be evaded by writing a row differently: rows come
// from a GFM-faithful table walk, `scripts/markdown_lines.mjs`'s
// `markdownTables` in Dart, and the two must agree — they read the same
// file in the same job. decisions § 779.
//
// The whole iOS column — its derivation, its one prose statement, and the
// marker a departing cell carries — is `scripts/check_parity_ios_column.mjs`,
// which runs beside this in the same job. This file used to carry a fourth
// rule about it ("iOS `✓` while Android isn't"); that rule is subsumed, since
// the derivation now forbids a bare iOS `✓` outright.
//
// Wired into CI via the `parity-matrix` job in `.github/workflows/ci.yml`,
// where it runs AFTER `check_parity_ios_column.mjs` — so it is not a
// backstop for that guard, and a defect the two share is reported there
// first or not at all (decisions § 774).
// Run locally with `dart run scripts/check_parity_matrix.dart`.
// Unit tests: `node --test scripts/check_parity_matrix.test.mjs` (they
// drive this script over fixture files; there is no Dart test package at
// the repo root and the guard is a bare `dart:io` script).
//
// Out of scope (v1): cross-checking that a `✓` cell corresponds to a real
// file in the codebase. The Notes column is free-form prose — extracting
// every screen path from it deterministically is fragile, and the cost
// of a wrong-path false positive in CI would dwarf the bug-catch yield.
// Revisit if the codebase grows a per-feature manifest.

import 'dart:io';

const _legalCellValues = {'✓', '✗', 'Partial', 'N/A'};
const _platforms = ['Android', 'iOS', 'Web', 'Wear OS', 'Apple Watch'];

class _Row {
  final int lineNumber;
  final String feature;
  final List<String> platformCells; // 5 cells: Android, iOS, Web, Wear OS, Apple Watch
  final String notes;

  _Row({
    required this.lineNumber,
    required this.feature,
    required this.platformCells,
    required this.notes,
  });
}

class _Issue {
  final int lineNumber;
  final String rowFeature;
  final String message;
  _Issue(this.lineNumber, this.rowFeature, this.message);

  @override
  String toString() =>
      'docs/product/parity.md:$lineNumber — [$rowFeature] $message';
}

void main(List<String> args) {
  final path = args.isEmpty ? 'docs/product/parity.md' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('check_parity_matrix: $path not found.');
    exit(2);
  }

  final issues = <_Issue>[];
  final rows = _parseRows(file.readAsLinesSync(), issues);
  if (rows.isEmpty && issues.isEmpty) {
    stderr.writeln('check_parity_matrix: no data rows parsed from $path. '
        'Did the table format change?');
    exit(2);
  }

  for (final row in rows) {
    // (2) Legal cell values.
    for (var i = 0; i < row.platformCells.length; i++) {
      final cell = row.platformCells[i];
      if (!_legalCellValues.contains(cell)) {
        issues.add(_Issue(
          row.lineNumber,
          row.feature,
          '${_platforms[i]} cell "$cell" is not one of $_legalCellValues. '
              'Use `✓`, `✗`, `Partial`, or `N/A` — see the Legend at the '
              'top of the doc.',
        ));
      }
    }

    // (3) Partial-without-Notes sanity gate. The Legend says "Expand
    // in the Notes column" — empty notes hide what makes the row
    // partial. N/A rows are exempt because most "wrist can't render
    // KML" cases are obvious from the feature title, and the iOS cell is
    // exempt because the whole column is derived from Android by a rule
    // the document states once (decisions § 739).
    final nonIosCells = [
      row.platformCells[0],
      ...row.platformCells.sublist(2),
    ];
    if (nonIosCells.contains('Partial') && row.notes.trim().isEmpty) {
      issues.add(_Issue(
        row.lineNumber,
        row.feature,
        'has `Partial` cell(s) but the Notes column is empty. Expand '
            'in Notes — explain what part shipped and what is still '
            'missing.',
      ));
    }
  }

  if (issues.isEmpty) {
    stdout.writeln(
        'check_parity_matrix: ${rows.length} rows parsed, no issues.');
    return;
  }

  stderr.writeln('check_parity_matrix: ${issues.length} issue(s) '
      'across ${rows.length} parsed rows.\n');
  for (final issue in issues) {
    stderr.writeln('  $issue');
  }
  exit(1);
}

/// One GFM table: the header row's cells and every row a renderer draws
/// under it.
class _Table {
  final int headerLine;
  final List<String> header;
  final List<_RawRow> rows = [];

  _Table({required this.headerLine, required this.header});
}

class _RawRow {
  final int lineNumber;
  final String text;
  final List<String> cells;

  _RawRow(this.lineNumber, this.text, this.cells);
}

/// Split one row on unescaped `|` only. Markdown rows look like
/// `| a | b | c |` — but a cell may carry a literal pipe written as `\|`
/// (the GFM escape), which must NOT start a new column. GFM makes BOTH
/// wrapping pipes optional, so an empty end is dropped only where a pipe
/// actually produced one.
List<String> _splitRow(String line) {
  final parts = line
      .trim()
      .split(RegExp(r'(?<!\\)\|'))
      .map((s) => s.replaceAll(r'\|', '|').trim())
      .toList();
  if (parts.isNotEmpty && line.trim().startsWith('|')) parts.removeAt(0);
  if (parts.isNotEmpty && line.trim().endsWith('|')) parts.removeLast();
  return parts;
}

bool _isDelimiter(String line) {
  if (!line.contains('|')) return false;
  final cells = _splitRow(line);
  return cells.isNotEmpty &&
      cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c));
}

/// A line that opens a new markdown block rather than continuing the
/// table above it.
final _blockStart = RegExp(r'^\s*(?:[-*+] |\d+[.)] |#{1,6} |>|\||```|~~~|<!--)');

/// Every GFM table in the document.
///
/// This is `scripts/markdown_lines.mjs`'s `markdownTables` in Dart, and the
/// two have to agree — they read the same file in the same CI job. The rule
/// is GFM's own and it is STATEFUL: a table opens on a header plus a
/// delimiter row of the SAME width, and every line after it is a row until a
/// blank line or another block. Detecting a row as `line.startsWith('|')`
/// instead made a row written without its leading pipe — which GFM renders
/// identically — invisible to this guard and to the iOS-column guard beside
/// it, so no cell of it was ever checked. decisions § 779.
List<_Table> _markdownTables(List<String> lines) {
  final tables = <_Table>[];
  _Table? open;
  String? fence;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final edge = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(line);
    if (edge != null) {
      final glyph = edge.group(1)![0];
      if (fence == null) {
        fence = glyph;
      } else if (fence == glyph) {
        fence = null;
      }
      open = null;
      continue;
    }
    if (fence != null) continue;

    if (open != null) {
      // A blank line or another block ends the table — but a leading pipe
      // is what makes a row look like a block to `_blockStart`.
      if (line.trim().isNotEmpty &&
          (!_blockStart.hasMatch(line) || line.trimLeft().startsWith('|'))) {
        open.rows.add(_RawRow(i + 1, line, _splitRow(line)));
        continue;
      }
      open = null;
    }

    if (line.trim().isEmpty || !line.contains('|') || i + 1 >= lines.length) {
      continue;
    }
    final next = lines[i + 1];
    if (!_isDelimiter(next)) continue;
    final header = _splitRow(line);
    if (header.length != _splitRow(next).length) continue;
    open = _Table(headerLine: i + 1, header: header);
    tables.add(open);
    i++;
  }
  return tables;
}

/// Every parity-table data row, plus the lines that look like a row and
/// landed in no table.
///
/// A parity table is one whose header names all five platforms — structure,
/// not a `parts[0] == 'Feature'` guess, so the Legend and the iOS derivation
/// table drop out because they have different columns rather than because
/// they are pattern-matched out. Nothing is skipped for being the wrong
/// shape: a row of a parity table that is not seven cells wide is the whole
/// point of rule 1, and a pipe-leading line in no table at all is a row a
/// reader sees as raw pipes in a paragraph.
List<_Row> _parseRows(List<String> lines, List<_Issue> issues) {
  final rows = <_Row>[];
  final claimed = <int>{};
  final fenced = <int>{};
  String? fence;
  for (var i = 0; i < lines.length; i++) {
    final edge = RegExp(r'^\s*(`{3,}|~{3,})').firstMatch(lines[i]);
    if (edge != null) {
      final glyph = edge.group(1)![0];
      if (fence == null) {
        fence = glyph;
      } else if (fence == glyph) {
        fence = null;
      }
      fenced.add(i + 1);
      continue;
    }
    if (fence != null) fenced.add(i + 1);
  }

  for (final table in _markdownTables(lines)) {
    claimed.add(table.headerLine);
    claimed.add(table.headerLine + 1);
    for (final row in table.rows) {
      claimed.add(row.lineNumber);
    }
    if (!_platforms.every(table.header.contains)) continue;

    for (final row in table.rows) {
      final parts = row.cells;
      // (1) Column count.
      if (parts.length != 7) {
        issues.add(_Issue(
          row.lineNumber,
          parts.isEmpty ? '?' : parts.first,
          'row has ${parts.length} columns (expected 7: Feature, '
              'Android, iOS, Web, Wear OS, Apple Watch, Notes). The whole '
              'row was: ${row.text.trim()}',
        ));
        continue;
      }
      rows.add(_Row(
        lineNumber: row.lineNumber,
        feature: parts[0],
        platformCells: [
          for (final p in _platforms) parts[table.header.indexOf(p)],
        ],
        notes: parts[6],
      ));
    }
  }

  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].trimLeft().startsWith('|')) continue;
    if (claimed.contains(i + 1) || fenced.contains(i + 1)) continue;
    issues.add(_Issue(
      i + 1,
      '?',
      'this line opens with a pipe but belongs to no table, so a reader '
          'sees raw pipes in a paragraph and this guard sees no row. A '
          'table needs a header and a delimiter row of the SAME width, '
          'and a blank line inside one ends it. The whole line was: '
          '${lines[i].trim()}',
    ));
  }

  return rows;
}

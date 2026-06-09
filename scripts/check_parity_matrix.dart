// Parity-matrix audit. Walks `docs/product/parity.md`, parses every data row,
// and fails on the drift patterns that come up most often:
//
//   1. Row column count wrong (not 7 = Feature + 5 platforms + Notes).
//   2. Platform cell uses a symbol outside the legal set
//      `✓ | ✗ | Partial | N/A`.
//   3. iOS marked `✓` while Android isn't `✓` — impossible per
//      decisions.md § 39 (the Dart codebase is byte-identical).
//   4. Cell marked `Partial` with an empty Notes column. (`N/A` cells
//      are exempt — most "wrist can't render KML" rows are self-evident
//      from the feature title; require Notes for `Partial` where the
//      reader genuinely can't guess what shipped.)
//
// Wired into CI via the `parity-matrix` job in `.github/workflows/ci.yml`.
// Run locally with `dart run scripts/check_parity_matrix.dart`.
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

    // (3) iOS-ahead-of-Android sanity gate. Mobile_ios shares a byte-
    // identical Dart codebase with mobile_android (decisions § 39).
    // iOS can be equal-or-less than Android (the gap is Mac-build
    // runtime verification) but never strictly ahead.
    final android = row.platformCells[0];
    final ios = row.platformCells[1];
    if (ios == '✓' && android != '✓') {
      issues.add(_Issue(
        row.lineNumber,
        row.feature,
        'iOS is `✓` while Android is `$android`. Impossible per '
            'decisions § 39 — the Dart codebase is byte-identical, so '
            'iOS cannot be strictly ahead. Either the matrix is stale '
            '(re-mirror?) or the iOS cell is a mis-edit.',
      ));
    }

    // (4) Partial-without-Notes sanity gate. The Legend says "Expand
    // in the Notes column" — empty notes hide what makes the row
    // partial. N/A rows are exempt because most "wrist can't render
    // KML" cases are obvious from the feature title.
    if (row.platformCells.contains('Partial') && row.notes.trim().isEmpty) {
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

/// Walk the markdown lines, pull out every parity-table data row.
///
/// Heuristic: a parity row is a markdown table row (starts with `|`) that
/// (a) has at least 7 cells when split on `|`, and (b) is NOT a header
/// or separator row. Header / separator detection: any cell containing
/// only `:` / `-` / whitespace is a separator; a row whose feature cell
/// is literally "Feature" is the table header. Other tables in the doc
/// (Legend, Notes-style summaries) have different column counts and
/// drop out naturally.
List<_Row> _parseRows(List<String> lines, List<_Issue> issues) {
  final rows = <_Row>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('|')) continue;
    // Split on unescaped `|` only. Markdown rows look like `| a | b | c |`
    // — but a cell may carry a literal pipe written as `\|` (the GFM
    // escape), which must NOT start a new column. Split on `|` not
    // preceded by a backslash, then unescape and trim each cell.
    final parts = line
        .split(RegExp(r'(?<!\\)\|'))
        .map((s) => s.replaceAll(r'\|', '|').trim())
        .toList();
    // Drop empties at both ends (artefacts of the wrapping pipes).
    if (parts.isNotEmpty && parts.first.isEmpty) parts.removeAt(0);
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();

    // Separator row (`|---|---|...`)? Every cell is dashes / colons /
    // whitespace.
    final isSeparator = parts.every((p) =>
        p.isNotEmpty && RegExp(r'^[:\-\s]+$').hasMatch(p));
    if (isSeparator) continue;

    // Header rows for parity-style tables: the first column is the
    // human label (Feature, Key, …) and the rest are the platform
    // names. Skip anything whose first cell is "Feature" or "Key" with
    // the right column count.
    if (parts.length >= 7 &&
        (parts[0] == 'Feature' || parts[0] == 'Key')) {
      continue;
    }

    // Wrong column count — only flag when it looks like *somebody*
    // tried to make a parity row (>= 5 cells). Other tables in the
    // doc (Legend) have 2 cells and just drop out silently.
    if (parts.length < 5) continue;
    if (parts.length != 7) {
      // Skip if this is a multi-column header for an unrelated table.
      // Heuristic: contains the legend symbols, treat as legend.
      final joined = parts.join(' ');
      if (joined.contains('Meaning') || joined.contains('Symbol')) continue;
      issues.add(_Issue(
        i + 1,
        parts.first,
        'row has ${parts.length} columns (expected 7: Feature, '
            'Android, iOS, Web, Wear OS, Apple Watch, Notes). The whole '
            'row was: $line',
      ));
      continue;
    }

    rows.add(_Row(
      lineNumber: i + 1,
      feature: parts[0],
      platformCells: parts.sublist(1, 6),
      notes: parts[6],
    ));
  }
  return rows;
}

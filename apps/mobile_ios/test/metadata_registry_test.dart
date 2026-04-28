// Guard-rail: every `runs.metadata` key used anywhere in the mobile-side
// Dart codebase must be registered in `docs/metadata.md`.
//
// `runs.metadata` is a jsonb bag with no type-level protection. Cross-client
// drift (mobile writes `activity_type`, web reads `activityType`) is the
// exact failure mode the registry was created to prevent. This test keeps
// the registry and the code from diverging silently — if you add a key in
// Dart without adding a row to `docs/metadata.md`, CI fails here.
//
// Scope: Dart-only. Equivalent tests should exist for TypeScript (web),
// Kotlin (watch_wear), and Swift (watch_ios) — tracked as a TODO so the
// cross-platform story is symmetrical. Today the registry itself is the
// coordination point for those platforms.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keys that are written by the generator itself, so adding them would be
/// circular. Keep this list empty unless there's a genuine reason to
/// exclude a key from the discipline.
const _exemptKeys = <String>{};

/// Heuristics that pick up non-key matches we want to ignore. For example:
/// some helper extracts keys *from* `metadata` in a loop using
/// `metadata[entry.key]` — `entry` isn't a string literal and the regex
/// already skips that case. Keep this empty until proven necessary.
const _exemptReferences = <String>{};

void main() {
  test(
    'every `runs.metadata` key referenced in Dart source is registered in docs/metadata.md',
    () {
      final registry = _parseRegistry(
        File('../../docs/metadata.md').readAsStringSync(),
      );

      final roots = <Directory>[
        Directory('lib'),
        Directory('../../packages/api_client/lib'),
        Directory('../../packages/run_recorder/lib'),
      ].where((d) => d.existsSync());

      final referenced = <String, List<String>>{};
      for (final root in roots) {
        for (final entity in root.listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('/generated/')) continue;
          final src = entity.readAsStringSync();
          for (final k in _extractMetadataKeys(src)) {
            referenced.putIfAbsent(k, () => []).add(entity.path);
          }
        }
      }

      final unknown = referenced.keys.toSet()
        ..removeAll(registry)
        ..removeAll(_exemptKeys)
        ..removeAll(_exemptReferences);

      if (unknown.isNotEmpty) {
        final lines = <String>[
          'Unregistered metadata key(s) referenced in Dart source:',
          '',
          for (final k in unknown.toList()..sort()) ...[
            '  $k',
            ...referenced[k]!.map((p) => '      at $p'),
          ],
          '',
          'Either:',
          '  1) Register the key in docs/metadata.md (preferred) — use '
              'snake_case, describe the shape, writers, readers. See the '
              'top of that doc for the rule.',
          '  2) If the match is spurious (pattern matched a non-metadata '
              "reference), add the key to _exemptReferences in this test "
              'with a one-line comment explaining why.',
          '',
          'Drift in `runs.metadata` is invisible to the DB type system '
              '— this registry IS the coordination point across mobile, '
              'web, watch_wear, and watch_ios.',
        ];
        fail(lines.join('\n'));
      }
    },
  );

  test(
    'every registered metadata key is referenced in Dart source (dead-key check)',
    () {
      final registry = _parseRegistry(
        File('../../docs/metadata.md').readAsStringSync(),
      );

      final referenced = <String>{};
      final roots = <Directory>[
        Directory('lib'),
        Directory('../../packages/api_client/lib'),
        Directory('../../packages/run_recorder/lib'),
      ].where((d) => d.existsSync());
      for (final root in roots) {
        for (final entity in root.listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('/generated/')) continue;
          referenced.addAll(_extractMetadataKeys(entity.readAsStringSync()));
        }
      }

      // A registered key that no Dart client references may still be
      // legitimately written by the web / watches / an Edge Function. So
      // we only flag keys declared in `docs/metadata.md` as being written
      // BY a mobile-side writer but not actually referenced in Dart source
      // — a true dead key.
      //
      // Since the registry doesn't mark "Dart-written" separately from
      // "any client writes this", this test errs on the side of caution
      // and only warns in the reason string. To make it a hard failure,
      // scope by writer in a follow-up.
      final unused = registry.difference(referenced);
      // Intentionally NOT failing on unused — just surfacing so the next
      // session has a starting list. Converted to a hard failure once the
      // writer column in docs/metadata.md is machine-readable.
      if (unused.isNotEmpty) {
        // Intentional: printed, not failed. Upgrade to `fail(...)` once
        // the writer column is structured enough to exclude non-Dart-only
        // keys automatically.
        // ignore: avoid_print
        print(
          'INFO: these registered keys are not referenced in Dart source '
          '(may be web/watch/EF-only): ${(unused.toList()..sort()).join(', ')}',
        );
      }
    },
  );
}

/// Extract registered key names from the markdown registry. Each row in
/// each table starts with `| \`key\` |`. Match the first backticked token.
Set<String> _parseRegistry(String doc) {
  final out = <String>{};
  final re = RegExp(r'^\|\s*`([a-z_][a-z0-9_]*)`\s*\|', multiLine: true);
  for (final m in re.allMatches(doc)) {
    out.add(m.group(1)!);
  }
  return out;
}

/// Find every metadata-key reference in a single Dart source file. Covers:
///
///   * subscript access:  `metadata['xxx']`, `metadata!['xxx']`,
///                        `metadata?['xxx']`, `run.metadata!['xxx']`,
///                        `.metadata?['xxx']`
///   * map-literal writes: `metadata: { 'xxx': ..., 'yyy': ... }` — extracts
///                        every string-literal key inside the balanced `{}`
///
/// Does NOT cover:
///   * dynamic keys (`metadata[someVar]`) — by design
///   * non-literal nested access (`metadata['a']['b']`) — flagged as 'a' only
Set<String> _extractMetadataKeys(String source) {
  final keys = <String>{};

  // Subscript pattern — accepts either quote, allows !/? after metadata.
  final subscript = RegExp(
    r"""(?<![A-Za-z0-9_])metadata\s*[!?]?\s*\[\s*(['"])([a-z_][a-z0-9_]*)\1\s*\]""",
  );
  for (final m in subscript.allMatches(source)) {
    keys.add(m.group(2)!);
  }

  // Map-literal pattern — `metadata: {` or `metadata = {` or `metadata: <T>{`.
  // After matching, walk balanced braces and extract every `'xxx':` at
  // depth 1.
  final mapStart = RegExp(r"""(?<![A-Za-z0-9_])metadata\s*[:=]\s*(?:<[^>]+>\s*)?\{""");
  for (final m in mapStart.allMatches(source)) {
    final start = m.end; // just past the `{`
    int depth = 1;
    int i = start;
    while (i < source.length && depth > 0) {
      final c = source[i];
      if (c == '{') depth++;
      if (c == '}') depth--;
      if (depth == 1) {
        final rest = source.substring(i);
        final entry = RegExp(r"""^\s*(['"])([a-z_][a-z0-9_]*)\1\s*:""").matchAsPrefix(rest);
        if (entry != null) {
          keys.add(entry.group(2)!);
          i += entry.end;
          continue;
        }
      }
      i++;
    }
  }

  return keys;
}

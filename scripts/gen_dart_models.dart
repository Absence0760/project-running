// Parses apps/backend/supabase/migrations/*.sql and emits Dart row DTOs +
// column-name constants into
// packages/core_models/lib/src/generated/db_rows.dart.
//
// Run from the repo root: `dart run scripts/gen_dart_models.dart`.
//
// Why: before this existed, api_client hand-coded snake_case column names as
// string literals. Renaming a column in a migration silently broke the Dart
// client. Now every column is a const — the generator regenerates on every
// schema change, old consts disappear, consumer code fails to compile.
//
// Supported SQL subset (intentionally small — grow as the schema needs it):
//   create table NAME ( col type [constraints], ... );
//   alter table NAME add column COL TYPE [constraints];
//   alter table NAME drop column COL;
// Other statements (indexes, functions, RLS, storage, policies) are ignored.

import 'dart:io';

const _pgToDart = <String, String>{
  'uuid': 'String',
  'text': 'String',
  'varchar': 'String',
  'character varying': 'String',
  'integer': 'int',
  'int': 'int',
  'int4': 'int',
  'bigint': 'int',
  'int8': 'int',
  'smallint': 'int',
  'numeric': 'double',
  'decimal': 'double',
  'real': 'double',
  'double precision': 'double',
  'float8': 'double',
  'boolean': 'bool',
  'bool': 'bool',
  'timestamptz': 'DateTime',
  'timestamp': 'DateTime',
  'timestamp with time zone': 'DateTime',
  'timestamp without time zone': 'DateTime',
  'date': 'DateTime',
  'jsonb': 'Map<String, dynamic>',
  'json': 'Map<String, dynamic>',
};

// Tables to emit. Internal auth / storage tables are referenced via FKs but
// we don't own them. Materialized views are excluded — the `views` section
// of `Database` in TypeScript covers them and mobile doesn't query them.
const _tables = <String>{'runs', 'routes', 'integrations', 'user_profiles', 'route_reviews'};

class _Column {
  _Column(this.name, this.pgType, this.nullable, this.waypointJsonb);
  final String name;
  final String pgType;
  bool nullable;
  // `routes.waypoints` is jsonb of TrackPoint[] — special-case it to
  // List<Map<String, dynamic>> so callers don't have to downcast.
  bool waypointJsonb;
}

void main(List<String> args) {
  final repoRoot = _findRepoRoot();
  final migrationsDir = Directory('$repoRoot/apps/backend/supabase/migrations');
  if (!migrationsDir.existsSync()) {
    stderr.writeln('No migrations directory at ${migrationsDir.path}');
    exit(1);
  }

  final files = migrationsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final schema = <String, Map<String, _Column>>{};
  for (final f in files) {
    _applyMigration(f.readAsStringSync(), schema);
  }

  final outFile = File(
    '$repoRoot/packages/core_models/lib/src/generated/db_rows.dart',
  );
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(_emit(schema));
  stdout.writeln('Wrote ${outFile.path}');
}

String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (Directory('${dir.path}/apps/backend/supabase').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      stderr.writeln('Could not find repo root from ${Directory.current.path}');
      exit(1);
    }
    dir = parent;
  }
}

void _applyMigration(String sql, Map<String, Map<String, _Column>> schema) {
  // Strip line comments first so they can't swallow statement terminators.
  final cleaned = sql
      .split('\n')
      .map((l) {
        final idx = l.indexOf('--');
        return idx >= 0 ? l.substring(0, idx) : l;
      })
      .join('\n');

  // Split on ; at paren depth 0 so `numeric(10, 2)` and function bodies stay
  // intact.
  final statements = _splitTopLevel(cleaned, ';');
  for (final raw in statements) {
    final stmt = raw.trim();
    if (stmt.isEmpty) continue;
    final lower = stmt.toLowerCase();

    if (lower.startsWith('create table')) {
      _parseCreateTable(stmt, schema);
    } else if (lower.startsWith('alter table')) {
      _parseAlterTable(stmt, schema);
    }
    // All other statements (create index, create function, insert,
    // alter ... enable rls, create policy, $$ ... $$) are ignored.
  }
}

List<String> _splitTopLevel(String source, String delimiter) {
  final out = <String>[];
  var depth = 0;
  var dollarDepth = 0; // tracks $$ ... $$ function bodies
  final buf = StringBuffer();
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (i + 1 < source.length && source.substring(i, i + 2) == r'$$') {
      dollarDepth = dollarDepth == 0 ? 1 : 0;
      buf.write(r'$$');
      i++;
      continue;
    }
    if (dollarDepth > 0) {
      buf.write(c);
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == delimiter && depth == 0) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

void _parseCreateTable(String stmt, Map<String, Map<String, _Column>> schema) {
  // `create table [if not exists] NAME ( body )`
  final match = RegExp(
    r'create\s+table\s+(?:if\s+not\s+exists\s+)?(\w+)\s*\(',
    caseSensitive: false,
  ).firstMatch(stmt);
  if (match == null) return;
  final table = match.group(1)!.toLowerCase();
  if (!_tables.contains(table)) return;

  final bodyStart = match.end;
  final body = _extractParens(stmt, bodyStart - 1);
  final cols = <String, _Column>{};
  for (final part in _splitTopLevel(body, ',')) {
    final line = part.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.startsWith('primary key') ||
        lower.startsWith('unique') ||
        lower.startsWith('foreign key') ||
        lower.startsWith('check') ||
        lower.startsWith('constraint')) {
      continue;
    }
    final col = _parseColumn(line);
    if (col != null) {
      cols[col.name] = col;
    }
  }
  schema[table] = cols;
}

/// Given a string and the index of an opening `(`, return the content between
/// that paren and its matching close paren.
String _extractParens(String source, int openIdx) {
  assert(source[openIdx] == '(');
  var depth = 0;
  for (var i = openIdx; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) {
        return source.substring(openIdx + 1, i);
      }
    }
  }
  throw StateError('Unmatched ( in $source');
}

void _parseAlterTable(String stmt, Map<String, Map<String, _Column>> schema) {
  final match = RegExp(
    r'alter\s+table\s+(\w+)\s+(.*)',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(stmt);
  if (match == null) return;
  final table = match.group(1)!.toLowerCase();
  if (!_tables.contains(table)) return;
  final rest = match.group(2)!.trim();
  final lower = rest.toLowerCase();

  if (lower.startsWith('add column')) {
    final colPart = rest.substring('add column'.length).trim();
    final col = _parseColumn(colPart);
    if (col != null) {
      schema.putIfAbsent(table, () => {})[col.name] = col;
    }
  } else if (lower.startsWith('drop column')) {
    final name = rest
        .substring('drop column'.length)
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    schema[table]?.remove(name);
  }
  // `alter table ... enable row level security` and other forms ignored.
}

/// Parse a single column definition: `name type [constraints]`.
_Column? _parseColumn(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final firstSpace = trimmed.indexOf(RegExp(r'\s'));
  if (firstSpace < 0) return null;
  final name = trimmed.substring(0, firstSpace).toLowerCase();
  if (name.isEmpty || !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(name)) return null;

  final remainder = trimmed.substring(firstSpace).trim();

  // Extract the type token. Types with parameters like `numeric(10, 2)` need
  // the whole parenthesized group. Types with two words like `double
  // precision` or `timestamp with time zone` need a longest-match lookup.
  final pgType = _extractType(remainder);
  if (pgType == null) return null;

  final hasNotNull = RegExp(r'\bnot\s+null\b', caseSensitive: false)
      .hasMatch(remainder);
  // Primary keys are implicitly NOT NULL in Postgres.
  final isPrimaryKey = RegExp(r'\bprimary\s+key\b', caseSensitive: false)
      .hasMatch(remainder);
  final nullable = !hasNotNull && !isPrimaryKey;

  final waypointJsonb = name == 'waypoints' && pgType == 'jsonb';
  return _Column(name, pgType, nullable, waypointJsonb);
}

String? _extractType(String remainder) {
  final lower = remainder.toLowerCase();
  // Multi-word types — check first, longest first.
  const multiWord = [
    'timestamp with time zone',
    'timestamp without time zone',
    'character varying',
    'double precision',
  ];
  for (final t in multiWord) {
    if (lower.startsWith(t)) return t;
  }
  // Single-word type, optionally followed by (precision, scale).
  final match = RegExp(r'^([a-z_]+)(\s*\([^)]*\))?', caseSensitive: false)
      .firstMatch(remainder);
  if (match == null) return null;
  return match.group(1)!.toLowerCase();
}

String _emit(Map<String, Map<String, _Column>> schema) {
  final out = StringBuffer()
    ..writeln('// GENERATED FILE — DO NOT EDIT.')
    ..writeln('//')
    ..writeln('// Regenerated by `dart run scripts/gen_dart_models.dart`')
    ..writeln('// from apps/backend/supabase/migrations/*.sql.')
    ..writeln('//')
    ..writeln('// Do not hand-edit. To add a column, add it to the SQL')
    ..writeln('// migration, rerun the generator, and commit both files.')
    ..writeln();

  final tableOrder = _tables.toList()..sort();
  for (final table in tableOrder) {
    final cols = schema[table];
    if (cols == null || cols.isEmpty) continue;
    _emitClass(out, table, cols);
    out.writeln();
  }
  return out.toString();
}

void _emitClass(StringBuffer out, String table, Map<String, _Column> cols) {
  final className = '${_pascal(_singular(table))}Row';

  out.writeln('/// Row shape for the `$table` table. Mirrors the Supabase schema');
  out.writeln('/// exactly — field names are snake_case to match the JSON wire format.');
  out.writeln('class $className {');
  out.writeln("  static const String table = '$table';");
  for (final c in cols.values) {
    out.writeln(
      "  static const String col${_pascal(c.name)} = '${c.name}';",
    );
  }
  out.writeln();

  // Fields
  for (final c in cols.values) {
    final dartType = _dartType(c);
    // `dynamic` is already nullable — adding `?` triggers a warning.
    final nullable = c.nullable && dartType != 'dynamic' ? '?' : '';
    out.writeln('  final $dartType$nullable ${_camel(c.name)};');
  }
  out.writeln();

  // Constructor
  out.writeln('  const $className({');
  for (final c in cols.values) {
    final prefix = c.nullable ? '' : 'required ';
    out.writeln('    ${prefix}this.${_camel(c.name)},');
  }
  out.writeln('  });');
  out.writeln();

  // fromJson
  out.writeln('  factory $className.fromJson(Map<String, dynamic> json) => $className(');
  for (final c in cols.values) {
    out.writeln('    ${_camel(c.name)}: ${_fromJsonExpr(c)},');
  }
  out.writeln('  );');
  out.writeln();

  // toJson — emits every column, including nulls, so upserts are explicit.
  out.writeln('  Map<String, dynamic> toJson() => <String, dynamic>{');
  for (final c in cols.values) {
    out.writeln('    col${_pascal(c.name)}: ${_toJsonExpr(c)},');
  }
  out.writeln('  };');

  out.writeln('}');
}

String _dartType(_Column c) {
  if (c.waypointJsonb) return 'List<Map<String, dynamic>>';
  return _pgToDart[c.pgType] ?? 'dynamic';
}

String _fromJsonExpr(_Column c) {
  final key = "json['${c.name}']";
  final dart = _dartType(c);
  final nullCast = c.nullable ? '?' : '';
  switch (dart) {
    case 'String':
      return '$key as String$nullCast';
    case 'int':
      return c.nullable
          ? '($key as num?)?.toInt()'
          : '($key as num).toInt()';
    case 'double':
      return c.nullable
          ? '($key as num?)?.toDouble()'
          : '($key as num).toDouble()';
    case 'bool':
      return '$key as bool$nullCast';
    case 'DateTime':
      return c.nullable
          ? '$key == null ? null : DateTime.parse($key as String)'
          : 'DateTime.parse($key as String)';
    case 'Map<String, dynamic>':
      return '$key as Map<String, dynamic>$nullCast';
    case 'List<Map<String, dynamic>>':
      final body = '($key as List<dynamic>).cast<Map<String, dynamic>>()';
      return c.nullable ? '$key == null ? null : $body' : body;
  }
  return key;
}

String _toJsonExpr(_Column c) {
  final field = _camel(c.name);
  final dart = _dartType(c);
  switch (dart) {
    case 'DateTime':
      return c.nullable
          ? '$field?.toIso8601String()'
          : '$field.toIso8601String()';
  }
  return field;
}

String _pascal(String s) => s
    .split('_')
    .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
    .join();

String _camel(String s) {
  final parts = s.split('_');
  return parts.first +
      parts.skip(1).map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join();
}

String _singular(String table) {
  if (table.endsWith('ies')) return '${table.substring(0, table.length - 3)}y';
  if (table.endsWith('s')) return table.substring(0, table.length - 1);
  return table;
}

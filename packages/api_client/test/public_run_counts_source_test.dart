import 'dart:io';

import 'package:test/test.dart';

/// Pins where `_hydratePeopleSuggestions` gets a candidate's public-run count.
///
/// It used to tally the base `runs` table client-side. Migration
/// `20260701_001` dropped the public-anyone SELECT policy on `runs` (decisions
/// §33 — non-owner reads go through the `public_runs` view), and states the
/// outcome verbatim: that query "returns zero rows" for a non-owner. So People
/// search and "Suggested for you" showed "0 public runs" for everyone, and
/// `comparePeopleRank`'s PRIMARY sort key was a constant — the anti-bot
/// ranking it exists for was inert. Migration `20270118_001` added the
/// SECURITY DEFINER `public_run_counts` RPC to replace exactly this query and
/// web moved to it; mobile did not.
///
/// A source guard rather than a wire test because the failure is static — the
/// old query is well-formed and succeeds, it just reads a relation RLS empties.
/// A live-stack test would need two accounts with public runs and a viewer who
/// owns neither, which `api_client_integration_test.dart` has no fixture for.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();
  final start = src.indexOf(
      'Future<List<PeopleSuggestion>> _hydratePeopleSuggestions(');
  final end = start < 0 ? -1 : src.indexOf('\n  /// ', start);
  final hydrate =
      start < 0 ? '' : src.substring(start, end == -1 ? src.length : end);

  test('_hydratePeopleSuggestions is where the count is built', () {
    expect(hydrate, isNotEmpty, reason: 'the method moved or was renamed');
  });

  test('public-run counts come from the public_run_counts RPC', () {
    expect(
      hydrate.contains("rpc('public_run_counts'"),
      isTrue,
      reason: 'the count must come from the SECURITY DEFINER RPC — base-table '
          'RLS blocks a non-owner from reading another user\'s public runs',
    );
    expect(
      hydrate.contains("'p_user_ids': ids"),
      isTrue,
      reason: 'the RPC takes the candidate id array',
    );
  });

  test('the dead base-table tally is gone', () {
    expect(
      hydrate.contains('RunRow.colIsPublic'),
      isFalse,
      reason: 'filtering `runs` on is_public from a non-owner returns zero '
          'rows since 20260701_001 — it can only ever report 0',
    );
    expect(
      hydrate.contains('.from(RunRow.table)'),
      isFalse,
      reason: 'no read of the base runs table belongs in the hydrate path',
    );
  });

  test('the RPC the client calls is the one the migration defines', () {
    final migration = File('../../apps/backend/supabase/migrations/'
            '20270118_001_public_run_counts.sql')
        .readAsStringSync();
    expect(
      migration.contains('create or replace function '
          'public_run_counts(p_user_ids uuid[])'),
      isTrue,
      reason: 'the RPC name / parameter name the client posts must match the '
          'definition — PostgREST resolves the overload by argument NAME',
    );
    expect(migration.contains('security definer'), isTrue,
        reason: 'without SECURITY DEFINER the RPC inherits the same RLS that '
            'made the client tally return zero');
    expect(migration.contains('r.is_public = true'), isTrue,
        reason: 'the is_public filter is the hard gate that keeps a private '
            'run out of a count anyone may read');
  });

  test('the row shape the client unpacks is the one the RPC returns', () {
    final migration = File('../../apps/backend/supabase/migrations/'
            '20270118_001_public_run_counts.sql')
        .readAsStringSync();
    expect(
      migration.contains('returns table (user_id uuid, public_run_count '),
      isTrue,
    );
    expect(hydrate.contains("row['user_id']"), isTrue);
    expect(hydrate.contains("row['public_run_count']"), isTrue);
  });
}

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geocoding.dart';
import 'race_match.dart';

/// A discoverable race calendar entry (the `search_race_listings` projection:
/// listing cols + `distance_m_away` when a center was supplied). Mirrors the
/// web `RaceListingResult`.
class RaceListingView {
  final String id;
  final String provider;
  final String? providerRaceId;
  final String name;
  final String raceDate;
  final int? distanceM;
  final String? locationLabel;
  final String? entryUrl;
  final String? resultsUrl;
  final bool isVerified;
  final double? distanceMAway;

  const RaceListingView({
    required this.id,
    required this.provider,
    required this.providerRaceId,
    required this.name,
    required this.raceDate,
    required this.distanceM,
    required this.locationLabel,
    required this.entryUrl,
    required this.resultsUrl,
    required this.isVerified,
    required this.distanceMAway,
  });

  factory RaceListingView.fromJson(Map<String, dynamic> j) => RaceListingView(
        id: j['id'] as String,
        provider: j['provider'] as String,
        providerRaceId: j['provider_race_id'] as String?,
        name: j['name'] as String,
        raceDate: j['race_date'] as String,
        distanceM: (j['distance_m'] as num?)?.toInt(),
        locationLabel: j['location_label'] as String?,
        entryUrl: j['entry_url'] as String?,
        resultsUrl: j['results_url'] as String?,
        isVerified: j['is_verified'] as bool? ?? false,
        distanceMAway: (j['distance_m_away'] as num?)?.toDouble(),
      );
}

/// The matched-race view for a run: the run's owner-only race metadata + its
/// linked listing. Mirrors the web `RaceResultForRun`.
class RaceResultForRun {
  final RaceListingView? listing;
  final String? raceName;
  final String? bib;
  final String? chipTime;
  final String? gunTime;
  final int? overallPlace;
  final int? ageGroupPlace;
  final String? ageGroup;

  const RaceResultForRun({
    required this.listing,
    required this.raceName,
    required this.bib,
    required this.chipTime,
    required this.gunTime,
    required this.overallPlace,
    required this.ageGroupPlace,
    required this.ageGroup,
  });

  bool get hasResult =>
      chipTime != null || gunTime != null || overallPlace != null || raceName != null;
}

/// A single result row pasted by the runner (the manual import path).
class PastedRaceResult {
  final String? bib;
  final String? chipTime;
  final String? gunTime;
  final int? overallPlace;

  const PastedRaceResult({this.bib, this.chipTime, this.gunTime, this.overallPlace});

  Map<String, dynamic> toJson() => {
        if (bib != null) 'bib': bib,
        if (chipTime != null) 'chip_time': chipTime,
        if (gunTime != null) 'gun_time': gunTime,
        if (overallPlace != null) 'overall_place': overallPlace,
      };
}

class ImportRaceResultOutcome {
  final int imported;
  final int skipped;
  final int enriched;

  const ImportRaceResultOutcome({
    required this.imported,
    required this.skipped,
    required this.enriched,
  });
}

/// Thrown when the RunSignUp leg is unconfigured server-side (503), so the UI
/// can show the unavailable explainer rather than a generic failure.
class RunSignUpUnavailable implements Exception {
  const RunSignUpUnavailable();
}

/// Thrown when the UltraSignup leg is unconfigured server-side (503), so the UI
/// can show the unavailable explainer rather than a generic failure.
class UltraSignUpUnavailable implements Exception {
  const UltraSignUpUnavailable();
}

/// Thrown when the ChronoTrack leg is unconfigured server-side (503), so the UI
/// can show the unavailable explainer rather than a generic failure.
class ChronoTrackUnavailable implements Exception {
  const ChronoTrackUnavailable();
}

/// The one scoping value a provider's leg needs before it may be called.
enum RaceImportScope {
  /// The runner's bib narrows the finisher field to their own row. An unscoped
  /// pull returns the whole field and every row of it is inserted as the
  /// caller's own run (issue #360), so the client refuses one too.
  bib,

  /// The runner's own athlete id IS the upstream endpoint, so the pull is
  /// already scoped. An UltraSignup listing carries it as `provider_race_id`,
  /// which makes the field a fallback rather than a gate.
  athleteId,
}

/// One race-results provider with a built leg in `race-results-import`, keyed
/// by the token that function takes.
///
/// This list is the only provider vocabulary the app holds: the probe, the
/// fail-closed exception and what a caller must supply all hang off it, so a
/// leg added server-side reaches every mobile surface by being named here once.
///
/// `paste` is deliberately absent — it is the universal manual fallback rather
/// than a listing provider, needs no credential and no probe, and stays offered
/// beside every entry here. So are `parkrun`, `manual` and `raceresult`, which
/// are listing providers with no bib-import leg at all.
class RaceImportProvider {
  final String provider;
  final RaceImportScope scope;

  /// Thrown on the 503 `provider_not_configured` so a surface shows THIS
  /// provider's explainer and never a peer's.
  final Exception unavailable;

  final String probeFunction;
  final Map<String, dynamic> probeBody;

  const RaceImportProvider({
    required this.provider,
    required this.scope,
    required this.unavailable,
    required this.probeFunction,
    required this.probeBody,
  });
}

const List<RaceImportProvider> raceImportProviders = [
  RaceImportProvider(
    provider: 'runsignup',
    scope: RaceImportScope.bib,
    unavailable: RunSignUpUnavailable(),
    probeFunction: 'race-listings-sync',
    probeBody: <String, dynamic>{},
  ),
  RaceImportProvider(
    provider: 'ultrasignup',
    scope: RaceImportScope.athleteId,
    unavailable: UltraSignUpUnavailable(),
    probeFunction: 'race-listings-sync',
    probeBody: <String, dynamic>{'provider': 'ultrasignup'},
  ),
  RaceImportProvider(
    provider: 'chronotrack',
    scope: RaceImportScope.bib,
    unavailable: ChronoTrackUnavailable(),
    probeFunction: 'race-results-import',
    probeBody: <String, dynamic>{'provider': 'chronotrack', 'probe': true},
  ),
];

final Map<String, RaceImportProvider> _providerByToken = {
  for (final p in raceImportProviders) p.provider: p,
};

/// The spec for a listing's provider, or null when that provider has no import
/// leg. A null is not a gap: manual paste still applies to every listing.
RaceImportProvider? raceImportProviderFor(String provider) =>
    _providerByToken[provider];

/// All Supabase calls for the race calendar + results import (race_calendar.md).
/// Mirrors the web `data.ts` race helpers; wire-level methods are exercisable
/// against a real local Supabase via the `withClient` seam.
class RaceService extends ChangeNotifier {
  final SupabaseClient? _override;

  RaceService() : _override = null;

  @visibleForTesting
  RaceService.withClient(SupabaseClient client) : _override = client;

  SupabaseClient get _c {
    final override = _override;
    if (override != null) return override;
    if (!ApiClient.isInitialized) {
      throw StateError('RaceService called before Supabase.initialize() resolved.');
    }
    return Supabase.instance.client;
  }

  bool get isReady => _override != null || ApiClient.isInitialized;

  String? get _uid => _c.auth.currentUser?.id;

  /// Race discovery (security invoker, public listings). Mirrors
  /// `searchRaceListings` — proximity by the listing's geocoded location.
  Future<List<RaceListingView>> searchRaceListings({
    String? query,
    String? distance,
    String? from,
    String? to,
    String? nearPlace,
    String? mapTilerKey,
    Future<GeocodedPlace?> Function(String)? geocoder,
    int limit = 60,
  }) async {
    final params = <String, dynamic>{'p_limit': limit};
    final term = query?.trim();
    if (term != null && term.isNotEmpty) params['p_query'] = term;
    if (distance != null && distance.isNotEmpty) params['p_distance'] = distance;
    if (from != null) params['p_from'] = from;
    if (to != null) params['p_to'] = to;

    final place = nearPlace?.trim();
    if (place != null && place.isNotEmpty && mapTilerKey != null) {
      final geo = await (geocoder ?? (q) => geocodePlace(q, apiKey: mapTilerKey))(place);
      if (geo != null) {
        params['p_center_lng'] = geo.lng;
        params['p_center_lat'] = geo.lat;
        params['p_radius_m'] = geo.radiusM;
      }
    }

    try {
      final raw = await _c.rpc('search_race_listings', params: params);
      return ((raw ?? <dynamic>[]) as List)
          .whereType<Map<String, dynamic>>()
          .map(RaceListingView.fromJson)
          .toList();
    } catch (e, s) {
      debugPrint('RaceService.searchRaceListings RPC failed: $e\n$s');
      return const [];
    }
  }

  /// Submit a crowd-sourced manual listing. `is_verified` is forced false by
  /// the DB trigger; `submitted_by` is stamped to the caller (RLS requires it).
  Future<RaceListingView> submitRaceListing({
    required String name,
    required String raceDate,
    int? distanceM,
    String? locationLabel,
    String? entryUrl,
    String? resultsUrl,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final row = await _c
        .from('race_listings')
        .insert({
          'provider': 'manual',
          'name': name.trim(),
          'race_date': raceDate,
          'distance_m': distanceM,
          'location_label': _blankToNull(locationLabel),
          'entry_url': _blankToNull(entryUrl),
          'results_url': _blankToNull(resultsUrl),
          'submitted_by': uid,
        })
        .select()
        .single();
    return RaceListingView.fromJson(row);
  }

  /// The owner-only race metadata + linked listing for a run. Mirrors
  /// `fetchRaceResultForRun`.
  Future<RaceResultForRun?> fetchRaceResultForRun(String runId) async {
    final row = await _c
        .from('runs')
        .select('metadata, race_listing_id')
        .eq('id', runId)
        .maybeSingle();
    if (row == null) return null;
    final meta = (row['metadata'] as Map<String, dynamic>?) ?? const {};
    RaceListingView? listing;
    final listingId = row['race_listing_id'] as String?;
    if (listingId != null) {
      final l = await _c
          .from('public_race_listings')
          .select()
          .eq('id', listingId)
          .maybeSingle();
      if (l != null) listing = RaceListingView.fromJson(l);
    }
    return RaceResultForRun(
      listing: listing,
      raceName: meta['race_name'] as String?,
      bib: meta['bib'] as String?,
      chipTime: meta['chip_time'] as String?,
      gunTime: meta['gun_time'] as String?,
      overallPlace: (meta['overall_place'] as num?)?.toInt(),
      ageGroupPlace: (meta['age_group_place'] as num?)?.toInt(),
      ageGroup: meta['age_group'] as String?,
    );
  }

  /// The auto-match seam: same-day listings to offer "Is this your race?".
  /// The caller scores them by proximity + distance band via [raceMatchScore].
  Future<List<RaceListingView>> findRaceMatchCandidates(String runId) async {
    final run = await _c
        .from('runs')
        .select('started_at')
        .eq('id', runId)
        .maybeSingle();
    final startedAt = run?['started_at'] as String?;
    if (startedAt == null) return const [];
    final day = startedAt.substring(0, 10);
    return searchRaceListings(from: day, to: day, limit: 20);
  }

  /// Invoke `race-results-import`. Throws the provider's own
  /// [RaceImportProvider.unavailable] on the 503 `provider_not_configured` so
  /// the UI can show that provider's explainer.
  Future<ImportRaceResultOutcome> importRaceResult({
    required String provider, // a [raceImportProviders] token, or 'paste'
    required String listingId,
    String? bib,
    String? ultraSignUpAthleteId,
    String? matchRunId,
    PastedRaceResult? result,
  }) async {
    try {
      final res = await _c.functions.invoke('race-results-import', body: {
        'provider': provider,
        'listingId': listingId,
        if (bib != null) 'bib': bib,
        if (ultraSignUpAthleteId != null)
          'ultraSignUpAthleteId': ultraSignUpAthleteId,
        if (matchRunId != null) 'matchRunId': matchRunId,
        if (result != null) 'result': result.toJson(),
      });
      final data = (res.data as Map<String, dynamic>?) ?? const {};
      return ImportRaceResultOutcome(
        imported: (data['imported'] as num?)?.toInt() ?? 0,
        skipped: (data['skipped'] as num?)?.toInt() ?? 0,
        enriched: (data['enriched'] as num?)?.toInt() ?? 0,
      );
    } on FunctionException catch (e) {
      final spec = raceImportProviderFor(provider);
      if (spec != null && e.status == 503 && _isProviderNotConfigured(e.details)) {
        throw spec.unavailable;
      }
      rethrow;
    }
  }

  /// Probe whether [provider]'s import leg is configured server-side, over the
  /// probe that provider's [RaceImportProvider] names. Returns false on a 503
  /// `provider_not_configured` — and false without a call for a listing
  /// provider that has no import leg at all, so a caller can ask about any
  /// listing and get an honest answer rather than a peer provider's.
  ///
  /// Anything else answers true: a probe that could not reach the server has
  /// not shown the provider to be unconfigured, and disabling a live leg on a
  /// dropped connection would be its own dishonesty.
  Future<bool> isProviderConfigured(String provider) async {
    final spec = raceImportProviderFor(provider);
    if (spec == null) return false;
    try {
      await _c.functions.invoke(spec.probeFunction, body: spec.probeBody);
      return true;
    } on FunctionException catch (e) {
      if (e.status == 503 && _isProviderNotConfigured(e.details)) return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Probe whether the RunSignUp leg is configured server-side.
  Future<bool> isRunSignUpConfigured() => isProviderConfigured('runsignup');

  /// Probe whether the ChronoTrack leg is configured server-side.
  Future<bool> isChronoTrackConfigured() => isProviderConfigured('chronotrack');

  bool _isProviderNotConfigured(dynamic details) {
    if (details is Map && details['error'] == 'provider_not_configured') return true;
    return details.toString().contains('provider_not_configured');
  }

  String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

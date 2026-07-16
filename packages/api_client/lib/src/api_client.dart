import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'segments_rank.dart';

// Column-level grant lockdowns: see migrations 20260801_001 +
// 20260818_001 (clubs.invite_token) and 20260723_001 + 20260806_001 +
// 20260818_001 (events.meet_lat / meet_lng). PostgREST `select('*')`
// raises 42501 because the role lacks SELECT on the revoked columns.
// Every read site enumerates the safe columns. The mobile arch-guard
// test grep-asserts no `from('clubs').select()` / `from('events').select()`.
const String _clubSafeCols =
    'id, owner_id, name, slug, description, avatar_url, location_label, '
    'is_public, join_policy, created_at, updated_at';

const String _eventSafeCols =
    'id, club_id, title, description, starts_at, duration_min, '
    'meet_label, route_id, distance_m, pace_target_sec, capacity, '
    'author_id, created_at, updated_at, recurrence_freq, '
    'recurrence_byday, recurrence_until, recurrence_count';

/// Log-safe projection of a caught exception: runtime type + SQLSTATE
/// code only. A `PostgrestException`'s message/details/hint can echo
/// the offending row's values (a safety contact's email on the
/// safety_contacts paths), and Flutter's default `debugPrint` writes to
/// logcat/os_log in every build mode — so raw `$e` interpolation is a
/// device-log PII leak. Mirrors the `.code`/`.message` scrub on the web
/// and Edge Function tiers. /audit/pii-in-logs.
String safeErrorLabel(Object e) {
  if (e is PostgrestException) {
    return 'PostgrestException(code: ${e.code ?? 'unknown'})';
  }
  return e.runtimeType.toString();
}

/// Typed client for the Supabase REST API.
///
/// Must call [initialize] before using any methods.
///
/// In production every callsite uses the unnamed `ApiClient()`
/// constructor and the instance reads through the global
/// `Supabase.instance.client`. Tests can use [ApiClient.withClient]
/// to inject a fake `SupabaseClient` so the wire-level methods can
/// be driven without booting a real Supabase backend.
class ApiClient {
  /// Custom-scheme deep link GoTrue redirects the signup-confirmation /
  /// magic-link auth mail to on mobile. supabase_flutter's app_links
  /// listener catches it and completes the PKCE session inside the app.
  /// Distinct from the `threkir://` scheme (owned by flutter_web_auth_2
  /// for Strava OAuth). Must be registered as an intent-filter (Android
  /// manifest) + CFBundleURLTypes (iOS Info.plist) AND allow-listed in
  /// Supabase Auth -> URL Configuration -> Redirect URLs. See
  /// docs/features/web_app_auth.md.
  static const String kAuthDeepLinkRedirect = 'com.threkir.app://login-callback';

  /// Test-only override. When non-null, [_client] returns this
  /// instead of `Supabase.instance.client`. Always null on the
  /// production code path.
  final SupabaseClient? _overrideClient;

  /// Whether Supabase is initialized and reachable. The default
  /// [ApiClient] constructor refuses to build while this is `false`
  /// because `Supabase.instance.client` is backed by a `late` field
  /// inside the SDK — reading it before `Supabase.initialize` resolves
  /// throws `LateInitializationError` from deep inside the call stack
  /// and surfaces as a cryptic save / sync failure at the UI layer.
  /// Bootstrappers should gate construction on this flag and leave
  /// `ApiClient`-shaped state null when Supabase init fails. See
  /// [main.dart] for the canonical wiring.
  ///
  /// The flag is set by [initialize] but also probes
  /// `Supabase.instance.client` lazily so that tests which call
  /// `Supabase.initialize` directly (instead of routing through
  /// [ApiClient.initialize]) still see the correct state. The probe
  /// is the canonical check — if it throws, Supabase is not ready,
  /// regardless of which init path the caller used.
  static bool _initialized = false;
  static bool get isInitialized {
    if (_initialized) return true;
    try {
      // Reading `.client` triggers the SDK's `late` field. If init
      // hasn't resolved, this throws and the catch-all returns false.
      // ignore: unnecessary_statements
      Supabase.instance.client;
      _initialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Default constructor — uses the global `Supabase.instance.client`.
  /// Every production callsite uses this form.
  ///
  /// The constructor deliberately does **not** guard on
  /// [isInitialized] because `HomeScreen` falls back to a default
  /// `ApiClient()` via `widget.apiClient ?? ApiClient()` when
  /// Supabase init failed silently, and the [userId] / [userEmail]
  /// getters already wrap `_client` access in try/catch so callers
  /// can degrade to "signed out" semantics. The real defence is the
  /// [_client] getter further down, which throws a typed [StateError]
  /// instead of letting `Supabase.instance.client` surface its private
  /// `LateInitializationError`.
  ApiClient() : _overrideClient = null;

  /// Test-only constructor. Inject a fake `SupabaseClient` so wire-
  /// level methods can be driven without booting a real backend or
  /// touching `Supabase.initialize`. Production code must not use
  /// this.
  @visibleForTesting
  ApiClient.withClient(SupabaseClient client) : _overrideClient = client;

  SupabaseClient get _client {
    final override = _overrideClient;
    if (override != null) return override;
    // Same probe semantics as the constructor — see [isInitialized].
    if (!isInitialized) {
      throw StateError(
        'ApiClient method called before Supabase.initialize() resolved — '
        'this is a bootstrap bug. Construct ApiClient only when '
        'ApiClient.isInitialized is true.',
      );
    }
    return Supabase.instance.client;
  }

  /// Initialize Supabase and flip [isInitialized] on success. Call
  /// once at app startup. If Supabase init throws, [isInitialized]
  /// stays `false` and the caller should leave [ApiClient]-shaped
  /// state null so the app falls through to offline mode.
  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
    _initialized = true;
  }

  /// Reset the static [_initialized] flag. Test-only — production
  /// code never wants Supabase to "uninitialize" mid-session.
  @visibleForTesting
  static void debugResetInitialized() {
    _initialized = false;
  }

  /// Sign in with email/password. Returns the user ID.
  Future<String> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user!.id;
  }

  /// Send a password-reset email to [email]. The link in the email
  /// lands the user in the web app's `/auth/reset` page where they
  /// can pick a new password (mobile doesn't host the reset form —
  /// see decisions / docs/features/flows.md). Idempotent + privacy-preserving:
  /// the underlying Supabase call returns success whether or not
  /// the email is registered, so the caller's UI should say something
  /// like "If that email is registered, we've sent a reset link."
  /// rather than leaking account existence.
  /// [redirectTo] is the web `/auth/reset` URL the caller builds from
  /// `WEB_BASE_URL` — mobile doesn't host the reset form, so the link
  /// points at web. Without it GoTrue falls back to the project Site
  /// URL (a fresh project's default is `http://localhost:3000`), which
  /// produces a dead link in prod. The URL must be on the Auth ->
  /// Redirect URLs allow-list. See docs/features/web_app_auth.md.
  Future<void> sendPasswordResetEmail({
    required String email,
    String? redirectTo,
  }) async {
    await _client.auth.resetPasswordForEmail(email.trim(), redirectTo: redirectTo);
  }

  /// Submit a user-content report. [targetKind] is one of 'user' /
  /// 'club' / 'route'; [reason] is one of 'spam' / 'harassment' /
  /// 'inappropriate' / 'impersonation' / 'other'. Notes is an
  /// optional free-text field — trimmed to null if blank.
  ///
  /// Returns the new report's id on success. PostgrestException
  /// 23505 indicates the user already has a pending report against
  /// this content (the migration's unique(reporter_id, target_kind,
  /// target_id) constraint); callers should surface a "you already
  /// reported this" message. P0001 is the rate-limit signature —
  /// callers route through `rateLimitErrorMessage` for the friendly
  /// wording.
  ///
  /// Mirrors `apps/web/src/lib/data.ts:submitReport`.
  Future<String> submitReport({
    required String targetKind,
    required String targetId,
    required String reason,
    String? notes,
  }) async {
    final trimmed = notes?.trim();
    final result = await _client.rpc(
      'submit_report',
      params: {
        'p_target_kind': targetKind,
        'p_target_id': targetId,
        'p_reason': reason,
        'p_notes':
            (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      },
    );
    return result as String;
  }

  /// Fetch heatmap-friendly point set within a bbox. Backed by the
  /// `heatmap_points_in_bbox` PostGIS RPC (migration 20260828_001),
  /// capped at [maxPoints] (default 5000) regardless of bbox size —
  /// a continent-wide pan returns the same point count as a city
  /// pan, just spread thinner. Returns an empty list on RPC error
  /// so the caller's map layer renders blank rather than throwing.
  ///
  /// Mirrors `apps/web/src/lib/data.ts:fetchHeatmapPoints`.
  Future<List<HeatmapPoint>> fetchHeatmapPoints({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int maxPoints = 5000,
  }) async {
    try {
      final data = await _client.rpc(
        'heatmap_points_in_bbox',
        params: {
          'p_min_lng': minLng,
          'p_min_lat': minLat,
          'p_max_lng': maxLng,
          'p_max_lat': maxLat,
          'p_max_points': maxPoints,
        },
      );
      if (data is! List) return const [];
      return data.map<HeatmapPoint>((row) {
        final r = row as Map<String, dynamic>;
        return HeatmapPoint(
          lat: (r['lat'] as num).toDouble(),
          lng: (r['lng'] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      // Caller's map layer stays blank on RPC failure.
      return const [];
    }
  }

  /// Register a new account with email/password. Returns the user ID.
  ///
  /// Throws if the address is already registered or the password is too weak.
  ///
  /// [ageConfirmedAt] and [termsAcceptedAt] capture the moment the
  /// user ticked the consent checkboxes on the sign-up screen. They
  /// are stored in `raw_user_meta_data` at the auth layer AND
  /// re-stamped on `user_profiles` via the `confirm_age_and_terms`
  /// RPC immediately after signUp succeeds. Server-side enforcement
  /// of GDPR Art 8 — see migration `20260929_001` and audit/gdpr
  /// (2026-05-25) Critical.
  Future<String> signUp({
    required String email,
    required String password,
    DateTime? ageConfirmedAt,
    DateTime? termsAcceptedAt,
  }) async {
    final ageIso = (ageConfirmedAt ?? DateTime.now().toUtc()).toIso8601String();
    final termsIso =
        (termsAcceptedAt ?? DateTime.now().toUtc()).toIso8601String();
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      // Land the confirmation link back in the app via the custom-scheme
      // deep link, not the project Site URL (which a mobile signup can't
      // pass). Without this GoTrue falls back to the Site URL and the
      // link opens a browser instead of returning to the app.
      emailRedirectTo: kAuthDeepLinkRedirect,
      data: {
        'age_confirmed_at': ageIso,
        'terms_accepted_at': termsIso,
      },
    );
    // Server-side stamp on user_profiles. Fire-and-forget — when
    // Supabase email-confirmation is enabled the JWT isn't live yet
    // and the RPC will 401; the sign-in path after confirmation
    // re-runs the stamp via confirmAgeAndTerms().
    try {
      await _client.rpc('confirm_age_and_terms');
    } catch (_) {
      // Tolerated — sign-in path retries.
    }
    return response.user!.id;
  }

  /// Stamps `age_confirmed_at` + `terms_accepted_at` on the caller's
  /// user_profiles row. Idempotent — existing timestamps are
  /// preserved (first-stamp wins). Call this on every post-OAuth
  /// session refresh whose profile still has either column null,
  /// once the user has been re-prompted.
  Future<void> confirmAgeAndTerms() async {
    await _client.rpc('confirm_age_and_terms');
  }

  /// Exchange a Google ID token (obtained by the host app via the native
  /// Android `google_sign_in` flow) for a Supabase session. Returns the
  /// user ID.
  ///
  /// Host app is responsible for driving the Google Sign-In UI and
  /// capturing the ID token — this keeps `api_client` platform-agnostic.
  /// See `mobile_android/lib/screens/sign_in_screen.dart` for the caller
  /// and `apps/mobile_android/local_testing.md` for Google Cloud Console +
  /// Supabase dashboard setup instructions.
  Future<String> signInWithGoogleIdToken({
    required String idToken,
    String? accessToken,
  }) async {
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    return response.user!.id;
  }

  /// Exchange an Apple ID token (obtained by the host app via the native
  /// `sign_in_with_apple` flow on iOS, or a web-fallback on Android) for
  /// a Supabase session. Returns the user ID.
  ///
  /// Symmetric counterpart to [signInWithGoogleIdToken]. The mobile
  /// sign-in / sign-up screens currently call
  /// `Supabase.instance.client.auth.signInWithIdToken` directly for
  /// Apple — they should route through this method instead so the
  /// ApiClient abstraction stays uniform for both providers.
  Future<String> signInWithAppleIdToken({
    required String idToken,
  }) async {
    final response = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
    );
    return response.user!.id;
  }

  /// Ensure the signed-in user has a `user_profiles` row, creating one
  /// with defaults (`preferred_unit: 'km'`, `subscription_tier: 'free'`)
  /// if missing. Mirrors web's `fetchUser` upsert-when-null path in
  /// `apps/web/src/lib/stores/auth.svelte.ts`.
  ///
  /// Before this method existed, mobile-only users (signed up via
  /// mobile and never visited web) had no `user_profiles` row at all —
  /// any RLS-protected feature that joined on the row silently returned
  /// nothing, and the dashboard preferred-unit fell back to whichever
  /// default the readers hard-coded. Now the profile is materialised
  /// on first sign-in.
  ///
  /// Idempotent — safe to call on every sign-in. The body is the same
  /// shape web uses, so a user whose row already exists is unchanged
  /// (the upsert on a present `id` is a no-op for the default columns).
  Future<void> ensureMyProfile() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    // Use the SECURITY DEFINER read so the column-revoked fields
    // (`subscription_tier`, `subscription_at`, `parkrun_number`) don't
    // make the SELECT silently return null when the row exists.
    final existing = await _client.rpc('get_my_profile');
    if (existing != null) return;
    await _client.from('user_profiles').upsert(
      buildDefaultProfileRow(viewerId),
      onConflict: 'id',
    );
  }

  /// Pure helper: the default `user_profiles` row inserted on first
  /// sign-in. Lifted to a `@visibleForTesting` static so the row shape
  /// can be unit-tested without a live Supabase.
  @visibleForTesting
  static Map<String, dynamic> buildDefaultProfileRow(String userId) {
    return <String, dynamic>{
      'id': userId,
      'preferred_unit': 'km',
      'subscription_tier': 'free',
    };
  }

  /// The current user ID, or null if not signed in.
  /// Current user id, or null when signed-out. Also null when
  /// Supabase wasn't initialised (offline-mode boot, dev without
  /// `.env.local` SUPABASE_URL/ANON_KEY) — `_client` resolves
  /// `Supabase.instance` lazily and that getter asserts when init
  /// hasn't happened. Callers (RoutesScreen, FeedScreen, every
  /// "are we signed in?" guard) expect a tristate of "signed in" /
  /// "signed out" — throwing is a fail-closed bug they can't react
  /// to. Catch the assertion and degrade to "signed out".
  String? get userId {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// The current Supabase session's access token (JWT), or null when
  /// not signed in. Used by [LiveBroadcaster] / [LiveHubClient] to
  /// Bearer the live-hub push requests. Same offline-safety as
  /// [userId] — never throws when Supabase isn't initialised.
  /// /audit/livehub May 2026 C1.
  String? get currentAccessToken {
    try {
      return _client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// The current user's email, or null if not signed in. Same
  /// offline-safety as [userId] — returns null when Supabase
  /// hasn't been initialised rather than throwing.
  String? get userEmail {
    try {
      return _client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  /// Auth transitions as a stream of the signed-in user id (null =
  /// signed out), one event per underlying `onAuthStateChange` event.
  /// Identity-bearing screens subscribe (via the mobile apps'
  /// `AuthChangeAware` mixin) and refetch when the id differs from
  /// what they rendered; the payload is advisory — [userId] stays the
  /// authoritative read, so test fakes that override [userId] remain
  /// consistent. Same offline-safety as [userId]: when Supabase isn't
  /// initialised this returns an empty stream rather than throwing,
  /// degrading to "never notified" exactly as the getters degrade to
  /// "signed out".
  Stream<String?> get authUserChanges {
    try {
      return _client.auth.onAuthStateChange
          .map((state) => state.session?.user.id);
    } catch (_) {
      return const Stream<String?>.empty();
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Delete the signed-in user's account. Invokes the `delete-account`
  /// Edge Function which cascades the deletion through every public
  /// FK to `auth.users` (decisions.md §56). The caller is responsible
  /// for the confirmation dialog and the post-delete sign-out + nav.
  ///
  /// Mirrors `apps/web/src/routes/settings/account/+page.svelte`'s
  /// `handleDeleteAccount` — same EF, same auth header derived from
  /// the session. The settings screen previously called
  /// `Supabase.instance.client.functions.invoke('delete-account')`
  /// directly, bypassing the ApiClient abstraction; this method
  /// keeps every auth / account flow on the same surface.
  Future<void> deleteAccount() async {
    final res = await _client.functions.invoke('delete-account');
    // The EF returns 2xx on success and embeds an `error` field on
    // failure paths. Surface that as a typed exception so the
    // caller can show a friendly message — matches how web reads
    // `body.error` off a non-2xx response.
    final body = res.data;
    if (body is Map && body['error'] is String) {
      throw Exception(body['error'] as String);
    }
  }

  // -- Safety contacts (decisions §131) --
  //
  // Mirrors the web `apps/web/src/lib/core/data.ts` safety-contact functions.
  // A safety contact is emailed when the owner finishes a run — even a private
  // one — via a double opt-in: the owner adds an email (this never reveals
  // whether the address is a registered user), and the contact opts in either
  // by an email link or, when they're an app user, in-app via the pending-
  // request flow.

  /// The owner's own safety-contact list (RLS scopes to `owner_id = me`).
  /// Returns an empty list on read failure so the settings screen renders an
  /// empty state rather than throwing.
  Future<List<SafetyContact>> fetchMySafetyContacts() async {
    try {
      final data = await _client
          .from(SafetyContactRow.table)
          .select(
            'id, contact_email, contact_user_id, confirmed_at, created_at',
          )
          .order(SafetyContactRow.colCreatedAt, ascending: false);
      return (data as List)
          .map<SafetyContact>(
              (row) => SafetyContact.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchMySafetyContacts failed: ${safeErrorLabel(e)}');
      return const [];
    }
  }

  /// Add a safety contact by email. The address is stored as-is; the confirm
  /// email is sent by the AFTER INSERT trigger. `confirmed_at` /
  /// `contact_user_id` are forced null server-side (the contact must opt in),
  /// so we never set them here. Throws on RLS / unique / format failure for
  /// the caller to surface.
  Future<SafetyContact> addSafetyContact(String email) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final data = await _client
        .from(SafetyContactRow.table)
        .insert(<String, dynamic>{
          SafetyContactRow.colOwnerId: userId,
          SafetyContactRow.colContactEmail: email,
        })
        .select('id, contact_email, contact_user_id, confirmed_at, created_at')
        .single();
    return SafetyContact.fromJson(data);
  }

  /// Publish (or re-publish) a Year-in-Running recap as a public, OG-
  /// unfurlable snapshot and return its share id (the uuid in the
  /// /recap/share/[id] web link). Owner-only via RLS. The snapshot is FROZEN
  /// aggregate data only (totals / badges / monthly strip) — no GPS, no
  /// per-run rows. Upserts on (user_id, period_kind, period_key) so a
  /// re-publish refreshes the same link instead of minting a new one.
  /// Returns null when signed-out or the write fails (the caller surfaces it).
  /// `periodKind` is 'year' or 'month'; `periodKey` is '2026' or '2026-03'.
  Future<String?> publishRecap({
    required String periodKind,
    required String periodKey,
    required Map<String, dynamic> snapshot,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final data = await _client
          .from('public_recaps')
          .upsert(
            <String, dynamic>{
              'user_id': userId,
              'period_kind': periodKind,
              'period_key': periodKey,
              'snapshot': snapshot,
            },
            onConflict: 'user_id,period_kind,period_key',
          )
          .select('id')
          .single();
      return data['id'] as String?;
    } catch (e) {
      debugPrint('publishRecap failed: $e');
      return null;
    }
  }

  /// Remove a safety contact the owner added (RLS gates to `owner_id = me`).
  Future<void> removeSafetyContact(String id) async {
    await _client
        .from(SafetyContactRow.table)
        .delete()
        .eq(SafetyContactRow.colId, id);
  }

  /// Pending requests where the signed-in user is the named contact (matched
  /// by their account email via the `my_pending_safety_requests` SECURITY
  /// DEFINER RPC — the pending row isn't directly readable until they link by
  /// confirming). Fails soft to an empty list.
  Future<List<PendingSafetyRequest>> fetchPendingSafetyRequests() async {
    try {
      final data = await _client.rpc('my_pending_safety_requests');
      if (data is! List) return const [];
      return data
          .map<PendingSafetyRequest>((row) =>
              PendingSafetyRequest.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchPendingSafetyRequests failed: ${safeErrorLabel(e)}');
      return const [];
    }
  }

  /// Confirm a pending request addressed to my account email (links my
  /// account). Returns whether a row was confirmed.
  Future<bool> confirmSafetyRequest(String id) async {
    final result =
        await _client.rpc('confirm_safety_contact', params: {'p_id': id});
    return result == true;
  }

  /// Decline a pending request / withdraw from a confirmed one. Returns
  /// whether a row was removed.
  Future<bool> declineSafetyRequest(String id) async {
    final result =
        await _client.rpc('decline_safety_contact', params: {'p_id': id});
    return result == true;
  }

  /// Save a completed [Run] to the backend.
  ///
  /// The GPS track is uploaded as a gzipped JSON file to the `runs` Storage
  /// bucket at `{user_id}/{run_id}.json.gz` and a reference to it is stored
  /// in `runs.track_url`. The dashboard list never loads the track — it's
  /// fetched on demand by [fetchTrack] when a run detail page is opened.
  ///
  /// The upsert body is built from a generated [RunRow], so renaming a column
  /// in a migration forces `scripts/gen_dart_models.dart` to regenerate the
  /// row class — any stale field reference fails to compile here.
  Future<void> saveRun(Run run, {bool? isPublic}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    String? trackUrl;
    final existingTrackUrl = run.metadata?['track_url'] as String?;
    if (run.track.isNotEmpty) {
      trackUrl = await _uploadTrack(userId: userId, runId: run.id, track: run.track);
    } else if (existingTrackUrl != null && existingTrackUrl.isNotEmpty) {
      trackUrl = existingTrackUrl;
    }

    // `startedAt` is captured as `DateTime.now()` — a local-tz DateTime.
    // `toIso8601String()` on a local DateTime emits a naive string with no
    // Z or offset, which PostgreSQL's `timestamptz` column interprets as
    // UTC — off by the user's offset and potentially a full calendar day.
    // Force UTC here so the stored instant is unambiguous.
    final row = RunRow(
      id: run.id,
      userId: userId,
      startedAt: run.startedAt.toUtc(),
      durationS: run.duration.inSeconds,
      distanceM: run.distanceMetres,
      // Round-trip the route link. Omitting it makes the upsert write
      // route_id = null, wiping a `linkRunToRoute` on the next sync.
      routeId: run.routeId,
      source: run.source.name,
      activityType: (run.metadata?['activity_type'] as String?) ?? 'run',
      isDnf: run.metadata?['is_dnf'] == true,
      fastest5kS: _embeddedBestSeconds(run.metadata, 'fastest_5k_s'),
      fastest10kS: _embeddedBestSeconds(run.metadata, 'fastest_10k_s'),
      fastestHalfMarathonS:
          _embeddedBestSeconds(run.metadata, 'fastest_half_marathon_s'),
      fastestMarathonS:
          _embeddedBestSeconds(run.metadata, 'fastest_marathon_s'),
      externalId: run.externalId,
      metadata: _metadataWithoutPromotedColumns(run.metadata),
      trackUrl: trackUrl,
      isPublic: isPublic,
    );
    final json = row.toJson();
    if (run.externalId != null && run.externalId!.isNotEmpty) {
      await _client.from(RunRow.table).upsert(json,
          onConflict: '${RunRow.colUserId},${RunRow.colExternalId}');
    } else {
      await _client.from(RunRow.table).upsert(json);
    }
    // L4 — best-effort plan-workout link. Mirrors `apps/web/src/lib/core/data.ts`
    // `saveRun` / `createManualRun`. A match failure must not break the core
    // upsert above (layered-resilience contract).
    try {
      await autoMatchRunToPlanWorkout(
          run.id, run.startedAt.toUtc(), run.distanceMetres);
    } catch (e) {
      debugPrint('autoMatchRunToPlanWorkout failed: $e');
    }
  }

  /// Patch the editable columns of a run row in place — duration, distance,
  /// the promoted `is_dnf` flag, and the metadata bag — WITHOUT re-uploading
  /// the track. The web run-detail `saveEdit` writes these columns directly;
  /// the mobile edit dialog mirrors it so a DNF / title / notes / stat edit
  /// is reflected on other clients immediately instead of waiting for the
  /// next batch sync (which would re-gzip + re-upload the whole track for a
  /// one-flag change). Owner-only by RLS. Best-effort caller — a failure
  /// just leaves the change to land on the next batch sync.
  Future<void> updateRunFields(Run run) async {
    await _client.from(RunRow.table).update({
      RunRow.colDurationS: run.duration.inSeconds,
      RunRow.colDistanceM: run.distanceMetres,
      RunRow.colIsDnf: run.metadata?['is_dnf'] == true,
      RunRow.colMetadata: _metadataWithoutPromotedColumns(run.metadata),
    }).eq(RunRow.colId, run.id);
  }

  /// Mark a run as publicly visible so it can be viewed at
  /// `/share/run/{id}` without authentication.
  Future<void> makeRunPublic(String runId) async {
    await _client
        .from(RunRow.table)
        .update({RunRow.colIsPublic: true})
        .eq(RunRow.colId, runId);
  }

  /// Batch-save a list of runs. Uploads tracks in parallel groups of
  /// [uploadConcurrency] and upserts rows in chunks of [rowChunkSize].
  ///
  /// [onProgress] is called after each row chunk is saved, with the number
  /// of runs saved so far.
  /// Returns the set of run ids whose track upload failed and which
  /// were therefore SKIPPED from the row upsert. Callers (sync /
  /// background-sync / runs-screen "Sync all" / import screen) should
  /// mark only the runs NOT in this set as synced so the failed ones
  /// retry on the next cycle. Empty set on full success.
  Future<Set<String>> saveRunsBatch(
    List<Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    if (runs.isEmpty) return const <String>{};

    // Upload tracks in parallel groups. A failure on ANY single
    // upload used to bubble through `Future.wait` and poison the
    // entire batch — one corrupted local track meant the sync stalled
    // until the user manually found + deleted the bad run. Now each
    // upload runs inside its own try/catch and any failures are
    // collected; the row upsert below skips those runs entirely so
    // they stay unsynced for the next retry cycle while the rest of
    // the batch makes progress.
    final trackUrls = <String, String>{};
    final trackFailures = <String, Object>{};
    final runsWithTracks = runs.where((r) => r.track.isNotEmpty).toList();
    for (var i = 0; i < runsWithTracks.length; i += uploadConcurrency) {
      final batch = runsWithTracks.skip(i).take(uploadConcurrency);
      final futures = batch.map((r) async {
        try {
          final url = await _uploadTrack(
              userId: userId, runId: r.id, track: r.track);
          trackUrls[r.id] = url;
        } catch (e) {
          trackFailures[r.id] = e;
          debugPrint(
            'saveRunsBatch: track upload failed for ${r.id}: $e — '
            'leaving run unsynced for retry, continuing with batch.',
          );
        }
      });
      await Future.wait(futures);
    }

    // Drop runs whose track upload failed — their row upsert would
    // otherwise write a `track_url = null` row that masks the failure
    // and loses the GPS data forever. Leaving the row unsynced means
    // the next cycle retries the track upload too.
    final eligibleRuns = runs.where((r) {
      if (r.track.isEmpty) return true;
      return !trackFailures.containsKey(r.id);
    }).toList();
    if (eligibleRuns.isEmpty) {
      if (trackFailures.isNotEmpty) {
        throw Exception(
          'saveRunsBatch: every run\'s track upload failed '
          '(${trackFailures.length} runs). First error: '
          '${trackFailures.values.first}',
        );
      }
      return const <String>{};
    }

    // Build rows and upsert in chunks.
    final rows = eligibleRuns.map((r) {
      final trackUrl = trackUrls[r.id] ??
          (r.metadata?['track_url'] as String?) ??
          '';
      return RunRow(
        id: r.id,
        userId: userId,
        // Same UTC-normalisation as saveRun — see comment there.
        startedAt: r.startedAt.toUtc(),
        durationS: r.duration.inSeconds,
        distanceM: r.distanceMetres,
        // Round-trip the route link — see saveRun.
        routeId: r.routeId,
        source: r.source.name,
        activityType: (r.metadata?['activity_type'] as String?) ?? 'run',
        isDnf: r.metadata?['is_dnf'] == true,
        fastest5kS: _embeddedBestSeconds(r.metadata, 'fastest_5k_s'),
        fastest10kS: _embeddedBestSeconds(r.metadata, 'fastest_10k_s'),
        fastestHalfMarathonS:
            _embeddedBestSeconds(r.metadata, 'fastest_half_marathon_s'),
        fastestMarathonS:
            _embeddedBestSeconds(r.metadata, 'fastest_marathon_s'),
        externalId: r.externalId,
        metadata: _metadataWithoutPromotedColumns(r.metadata),
        trackUrl: trackUrl.isEmpty ? null : trackUrl,
      ).toJson();
    }).toList();

    int saved = 0;
    for (var i = 0; i < rows.length; i += rowChunkSize) {
      final chunk = rows.skip(i).take(rowChunkSize).toList();
      // Split each chunk by whether a row carries an external_id.
      // Rows with an external_id upsert on that column so re-imports
      // of Strava / Health Connect runs dedup correctly. Rows without
      // an external_id (app-recorded) upsert on the primary key `id`,
      // which is always set and is the correct dedup key for live runs.
      // Using a single onConflict spec for a mixed batch would apply
      // the external_id conflict clause to null-external_id rows,
      // bypassing the partial unique index and creating duplicates.
      final withExtId = chunk
          .where((r) =>
              (r[RunRow.colExternalId] as String?) != null &&
              (r[RunRow.colExternalId] as String).isNotEmpty)
          .toList();
      final withoutExtId = chunk
          .where((r) {
            final id = r[RunRow.colExternalId] as String?;
            return id == null || id.isEmpty;
          })
          .toList();
      if (withExtId.isNotEmpty) {
        await _client.from(RunRow.table).upsert(withExtId,
            onConflict: '${RunRow.colUserId},${RunRow.colExternalId}');
      }
      if (withoutExtId.isNotEmpty) {
        await _client.from(RunRow.table).upsert(withoutExtId);
      }
      saved += chunk.length;
      onProgress?.call(saved);
    }
    // L4 — best-effort plan-workout link for batch ingest (Strava ZIP,
    // Health Connect, etc.). Same auto-match the web `saveRun` path
    // uses; a per-row match failure must not break the batch upsert.
    // Skip auto-match for runs whose track upload failed — their row
    // wasn't upserted, so the link would dangle.
    // The plan/week scope is identical for every run in the batch, so
    // fetch it once here instead of once per run (a bulk import used to
    // re-query training_plans N times). If the prefetch itself fails,
    // fall back to the per-run fetch so a transient error can't silence
    // matching for the whole batch.
    List<String>? batchWeekIds;
    try {
      batchWeekIds = await _planWeekIdsForUser(userId);
    } catch (e) {
      debugPrint('saveRunsBatch: plan week prefetch failed: $e');
    }
    if (batchWeekIds == null || batchWeekIds.isNotEmpty) {
      for (final run in eligibleRuns) {
        try {
          await autoMatchRunToPlanWorkout(
              run.id, run.startedAt.toUtc(), run.distanceMetres,
              planWeekIds: batchWeekIds);
        } catch (e) {
          debugPrint('autoMatchRunToPlanWorkout failed: $e');
        }
      }
    }
    return trackFailures.keys.toSet();
  }

  /// Delete a run from the backend, including its gzipped track file
  /// and every attached photo's bytes in Storage.
  ///
  /// The DB cascade kills `run_photos` rows when the run is gone, but
  /// the bytes orphan in the `run-photos` bucket and pay for storage
  /// indefinitely. Visibility-wise the orphans become unreachable
  /// (the Storage SELECT policy joins through `run_photos` — without
  /// a matching row the policy denies access), but the bucket-cost
  /// concern stays. Sweep them here. Audit/storage Medium fix.
  Future<void> deleteRun(Run run) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final trackPath = run.metadata?['track_url'] as String?;
    if (trackPath != null && trackPath.isNotEmpty) {
      try {
        await _client.storage.from(StorageBuckets.runs).remove([trackPath]);
      } catch (e) {
        // Best-effort — the row delete is more important than the file cleanup.
      }
    }

    try {
      // Sweep both the original upload AND the worker-generated
      // 512-wide thumbnail. Until the audit/storage pass landed,
      // the sweep only removed `storage_path`; the thumbnail blob
      // persisted in the bucket indefinitely (the run_photos row
      // cascade-deleted, so the Storage SELECT policy gates the
      // bytes, but the storage cost + latent footprint remained).
      final photoRows = await _client
          .from(RunPhotoRow.table)
          .select(
            '${RunPhotoRow.colStoragePath}, ${RunPhotoRow.colThumb512Path}',
          )
          .eq(RunPhotoRow.colRunId, run.id);
      final paths = <String>[];
      for (final row in photoRows) {
        final storage = row[RunPhotoRow.colStoragePath] as String?;
        final thumb = row[RunPhotoRow.colThumb512Path] as String?;
        if (storage != null && storage.isNotEmpty) paths.add(storage);
        if (thumb != null && thumb.isNotEmpty) paths.add(thumb);
      }
      if (paths.isNotEmpty) {
        await _client.storage.from(StorageBuckets.runPhotos).remove(paths);
      }
    } catch (e) {
      // Same best-effort posture as the track sweep above. Orphan
      // photo bytes don't leak data after the row cascade — the
      // Storage SELECT policy gates them — but they pay for storage
      // until manually swept.
    }

    await _client.from(RunRow.table).delete().eq(RunRow.colId, run.id);
  }

  /// Delete a run from the backend by id only — used by the SyncService
  /// retry path for runs the user already removed locally (so the full
  /// `Run` object is no longer available). Skips the Storage cleanup
  /// because the track url isn't known here; an orphan track file is a
  /// far smaller blast-radius than a phantom row that re-appears on
  /// next sync.
  Future<void> deleteRunById(String runId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from(RunRow.table).delete().eq(RunRow.colId, runId);
  }

  /// Fetch a single owned run by id, as a full domain [Run]. RLS scopes the
  /// `runs` table to the owner, so this only resolves the caller's own runs —
  /// it backs the unified History timeline opening a run-detail screen for a
  /// run that may sit beyond the locally-cached page. Null when missing or
  /// RLS-hidden. (Distinct from [fetchPublicRunById], which reads the redacted
  /// `public_runs` view for non-owner viewers.)
  Future<Run?> fetchRunById(String runId) async {
    final data = await _client
        .from(RunRow.table)
        .select()
        .eq(RunRow.colId, runId)
        .maybeSingle();
    if (data == null) return null;
    return _runFromRow(data);
  }

  /// Delete a route from the backend. Mirrors `apps/web/src/lib/data.ts:
  /// deleteRoute`. RLS gates the delete to the owner; foreign-key
  /// cascades clean up `saved_routes`, `segments`, and `route_reviews`
  /// rows automatically. Throws on RLS rejection or network failure
  /// so the caller can surface the error and avoid the
  /// "deleted-locally-but-cloud-row-persists" silent-divergence bug
  /// that mobile shipped before this method existed — every refresh
  /// would re-pull the route the user thought they'd deleted.
  Future<void> deleteRoute(String routeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    try {
      // Sweep route-photo blobs before the row delete. The FK cascade
      // removes the route_photos rows (so the Storage SELECT join hides
      // the bytes), but the blobs would otherwise orphan in the bucket —
      // the same gap deleteRun closes for run photos. Best-effort.
      final photoRows = await _client
          .from(RoutePhotoRow.table)
          .select(
            '${RoutePhotoRow.colStoragePath}, ${RoutePhotoRow.colThumb512Path}',
          )
          .eq(RoutePhotoRow.colRouteId, routeId);
      final paths = <String>[];
      for (final row in photoRows) {
        final storage = row[RoutePhotoRow.colStoragePath] as String?;
        final thumb = row[RoutePhotoRow.colThumb512Path] as String?;
        if (storage != null && storage.isNotEmpty) paths.add(storage);
        if (thumb != null && thumb.isNotEmpty) paths.add(thumb);
      }
      if (paths.isNotEmpty) {
        await _client.storage.from(StorageBuckets.routePhotos).remove(paths);
      }
    } catch (e) {
      // Best-effort — the row delete matters more than the file cleanup.
    }
    await _client.from(RouteRow.table).delete().eq(RouteRow.colId, routeId);
  }

  /// Course markers for a route, ordered by distance along the line. Reads
  /// through the `route_markers_for_viewer` RPC, which gates visibility and
  /// redacts any marker inside the owner's privacy zones for a non-owner.
  /// Fails closed (empty list) on error so a redaction failure never leaks.
  Future<List<RouteMarkerRow>> fetchRouteMarkers(String routeId) async {
    if (routeId.isEmpty) return const [];
    try {
      final data = await _client.rpc('route_markers_for_viewer', params: {
        'p_route_id': routeId,
      });
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((m) => RouteMarkerRow.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Add a course marker (owner-only at the RLS layer). Returns the inserted
  /// row (with the server-derived `position_m`).
  Future<RouteMarkerRow> addRouteMarker({
    required String routeId,
    required String kind,
    required String label,
    required double lat,
    required double lng,
    Map<String, dynamic> meta = const {},
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final row = await _client
        .from(RouteMarkerRow.table)
        .insert(<String, dynamic>{
          RouteMarkerRow.colRouteId: routeId,
          RouteMarkerRow.colUserId: userId,
          RouteMarkerRow.colKind: kind,
          RouteMarkerRow.colLabel: label.trim(),
          RouteMarkerRow.colLat: lat,
          RouteMarkerRow.colLng: lng,
          RouteMarkerRow.colMeta: meta,
        })
        .select()
        .single();
    return RouteMarkerRow.fromJson(row);
  }

  Future<void> updateRouteMarker(
    String id, {
    String? kind,
    String? label,
    double? lat,
    double? lng,
    Map<String, dynamic>? meta,
  }) async {
    final patch = <String, dynamic>{};
    if (kind != null) patch[RouteMarkerRow.colKind] = kind;
    if (label != null) patch[RouteMarkerRow.colLabel] = label.trim();
    if (lat != null) patch[RouteMarkerRow.colLat] = lat;
    if (lng != null) patch[RouteMarkerRow.colLng] = lng;
    if (meta != null) patch[RouteMarkerRow.colMeta] = meta;
    if (patch.isEmpty) return;
    await _client
        .from(RouteMarkerRow.table)
        .update(patch)
        .eq(RouteMarkerRow.colId, id);
  }

  Future<void> deleteRouteMarker(String id) async {
    await _client.from(RouteMarkerRow.table).delete().eq(RouteMarkerRow.colId, id);
  }

  /// Community condition reports for a route, newest first. Reads through the
  /// `route_conditions_for_viewer` RPC, which gates visibility and nulls the
  /// anchor of any report inside the owner's privacy zones for a non-owner.
  /// Fails closed (empty list) on error so a redaction failure never leaks.
  Future<List<RouteConditionRow>> fetchRouteConditions(String routeId) async {
    if (routeId.isEmpty) return const [];
    try {
      final data = await _client.rpc('route_conditions_for_viewer', params: {
        'p_route_id': routeId,
      });
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((m) => RouteConditionRow.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// File a condition report on a route the caller can see. The RLS
  /// insert-gate enforces route visibility, so any signed-in viewer — not
  /// just the owner — can report. Returns the inserted row (with the
  /// server-derived `position_m` when an anchor was supplied).
  Future<RouteConditionRow> addRouteCondition({
    required String routeId,
    required String condition,
    required String severity,
    String? note,
    double? lat,
    double? lng,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final trimmed = note?.trim();
    final row = await _client
        .from(RouteConditionRow.table)
        .insert(<String, dynamic>{
          RouteConditionRow.colRouteId: routeId,
          RouteConditionRow.colUserId: userId,
          RouteConditionRow.colCondition: condition,
          RouteConditionRow.colSeverity: severity,
          RouteConditionRow.colNote:
              (trimmed != null && trimmed.isNotEmpty) ? trimmed : null,
          RouteConditionRow.colLat: lat,
          RouteConditionRow.colLng: lng,
        })
        .select()
        .single();
    return RouteConditionRow.fromJson(row);
  }

  /// Delete a condition report. RLS allows the author OR the route owner
  /// (spam cleanup on one's own route).
  Future<void> deleteRouteCondition(String id) async {
    await _client
        .from(RouteConditionRow.table)
        .delete()
        .eq(RouteConditionRow.colId, id);
  }

  /// Fetch the user's runs, newest first.
  ///
  /// Returned runs have an empty `track`. Use [fetchTrack] to download the
  /// GPS waypoints for a single run when its detail page is opened.
  ///
  /// [before] paginates backwards — pass the `startedAt` of the oldest
  /// row from a previous page to get the next older batch.
  ///
  /// [updatedSince] enables delta fetches: only rows whose `last_modified_at`
  /// (in metadata) is newer than the supplied timestamp are returned. The
  /// caller stores its `lastFetchedAt` locally and passes it on subsequent
  /// opens so we don't re-fetch the entire history on every Runs tab
  /// visit.
  Future<List<Run>> getRuns({
    int limit = 50,
    DateTime? before,
    DateTime? updatedSince,
  }) async {
    var query = _client.from(RunRow.table).select();

    if (before != null) {
      query = query.lt(RunRow.colStartedAt, before.toIso8601String());
    }
    if (updatedSince != null) {
      // `last_modified_at` lives in metadata as an ISO-8601 string stamped
      // by LocalRunStore on every write. `->>` projects the JSON field as
      // text; Postgres lexicographic-compares ISO-8601 strings correctly.
      query = query.gt(
        "${RunRow.colMetadata}->>'last_modified_at'",
        updatedSince.toIso8601String(),
      );
    }

    final data = await query
        .order(RunRow.colStartedAt, ascending: false)
        .limit(limit);

    return data.map<Run>((row) => _runFromRow(row)).toList();
  }

  /// Download and decode the GPS track for a single run.
  ///
  /// Reads the gzipped JSON from Supabase Storage at the path stored in
  /// `metadata['track_url']` (returned by [getRuns] / [_runFromRow]).
  /// Returns an empty list if the run has no track.
  Future<List<Waypoint>> fetchTrack(Run run) async {
    final url = run.metadata?['track_url'] as String?;
    if (url == null || url.isEmpty) return const [];
    return _downloadTrack(url);
  }

  /// Download a track by its Storage path. Used when a caller has a
  /// raw `RunRow` (e.g. public-share screens) and doesn't want to
  /// shape it into a `Run` first.
  ///
  /// **Owner-only path** — the per-user-folder Storage policy from
  /// `20260410_001` gates access to
  /// `(storage.foldername(name))[1] = auth.uid()::text`. Non-owner
  /// viewers must use [fetchClippedTrackForRun] instead, which routes
  /// through the `clip-public-track` Edge Function so the unclipped
  /// blob never crosses the wire (decisions §33, migration
  /// `20260619_001` dropped the public-runs Storage policy).
  Future<List<Waypoint>> fetchTrackByPath(String path) async {
    if (path.isEmpty) return const [];
    return _downloadTrack(path);
  }

  /// Download the indoor/treadmill HR sidecar
  /// (`metadata['hr_series_url']` -> `{user_id}/{run_id}.hr.json.gz`) and decode
  /// it to `Waypoint`s carrying only bpm + timestamp (lat/lng default to 0;
  /// these never reach a map — they feed the HR-zone breakdown, which reads
  /// only bpm/timestamp). Owner-only, like the track: the sidecar holds no
  /// location and has no clipped/public variant (decisions §116). Empty list
  /// when the run has no sidecar.
  Future<List<Waypoint>> fetchHrSeries(Run run) async {
    final url = run.metadata?['hr_series_url'] as String?;
    if (url == null || url.isEmpty) return const [];
    final bytes = await _client.storage.from(StorageBuckets.runs).download(url);
    final json = utf8.decode(gzip.decode(bytes));
    final list = jsonDecode(json) as List<dynamic>;
    final out = <Waypoint>[];
    for (final e in list) {
      if (e is! Map) continue;
      final bpm = e['bpm'];
      if (bpm is! num) continue;
      final ts = e['ts'];
      out.add(Waypoint(
        lat: 0,
        lng: 0,
        bpm: bpm.round(),
        timestamp: ts is String ? DateTime.tryParse(ts) : null,
      ));
    }
    return out;
  }

  /// Privacy-aware non-owner track fetcher. Calls the
  /// `clip-public-track` Edge Function which downloads the gzipped
  /// track via service-role, passes the points through
  /// `clip_track_for_user`, and returns the clipped result. Use this
  /// on every non-owner surface where the old pattern was
  /// "fetchTrackByPath then clipTrackForUser client-side" — that
  /// pattern leaked the unclipped blob (audit/storage High, closed
  /// by migration `20260619_001`).
  Future<List<Waypoint>> fetchClippedTrackForRun(String runId) async {
    if (runId.isEmpty) return const [];
    final res = await _client.functions.invoke(
      'clip-public-track',
      body: {'run_id': runId},
    );
    final data = res.data;
    if (data is! Map) return const [];
    final points = data['points'];
    if (points is! List) return const [];
    return points
        .whereType<Map>()
        .map((p) => _waypointFromJson(p.cast<String, dynamic>()))
        .toList();
  }

  /// Fetch the map-match state + matched track for a run. Returns null
  /// when the row doesn't exist or is unreadable (RLS gates non-owners
  /// to no-row, so `null` covers both cases). Track download is
  /// best-effort: a row with `status='matched'` whose gz fails to
  /// fetch returns the row state with `track=null` so the caller can
  /// still surface the status badge while falling back to the raw
  /// track on the map.
  Future<RunMatchInfo?> fetchRunMatchedTrack(String runId) async {
    final rows = await _client
        .from('run_matched_tracks')
        .select(
          'status, matched_track_url, algorithm, algorithm_version, matched_at',
        )
        .eq('run_id', runId)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final status = MatchStatus.fromName(row['status'] as String);
    final url = row['matched_track_url'] as String?;
    List<Waypoint>? track;
    var trackUnreachable = false;
    if (status == MatchStatus.matched && url != null && url.isNotEmpty) {
      try {
        track = await _downloadTrack(url);
      } catch (e) {
        track = null;
        trackUnreachable = isMatchUnreachableError(e);
        debugPrint('matched-track gz download failed for $runId: $e');
      }
    }
    return RunMatchInfo(
      status: status,
      algorithm: row['algorithm'] as String?,
      algorithmVersion: row['algorithm_version'] as String?,
      matchedAt: row['matched_at'] == null
          ? null
          : DateTime.tryParse(row['matched_at'] as String),
      track: track,
      trackUnreachable: trackUnreachable,
    );
  }

  /// Force a fresh map-match for a run the caller owns. Resets the
  /// `run_matched_tracks` row to `pending` and queues a fresh
  /// `kind='map_match'` job. The `enqueue_run_rematch` PostgREST RPC
  /// self-gates on `auth.uid() = run.user_id`; non-owner calls raise
  /// `42501` which surfaces as a PostgrestException here. Idempotent
  /// against in-flight jobs (the `jobs_dedupe_map_match` unique index
  /// coalesces a second call while a previous re-match is queued).
  /// Mirrors `enqueueRunRematch` in `apps/web/src/lib/data.ts`.
  Future<void> enqueueRunRematch(String runId) async {
    await _client.rpc('enqueue_run_rematch', params: {'p_run_id': runId});
  }

  /// Escalate a sustained off-route departure to the runner's confirmed
  /// safety contacts (docs/features/safety.md, persona-woman). The
  /// `escalate_run_off_route` SECURITY DEFINER RPC self-gates on
  /// `auth.uid() = run.user_id` + an in-progress live-broadcast stub + the
  /// `safety_off_route_alerts` opt-in pref + ≥1 confirmed contact, stamps the
  /// once-per-run `metadata.safety_escalated_at`, and enqueues the same
  /// `safety_email` (+ additive `safety_sms`) jobs the overdue scan uses, with
  /// an `off_route` template. Idempotent — a re-call on an already-escalated
  /// run no-ops. Returns whether it escalated. Best-effort at the call site
  /// (L4): a failure must never disturb the recording.
  Future<bool> escalateRunOffRoute(String runId) async {
    final result =
        await _client.rpc('escalate_run_off_route', params: {'p_run_id': runId});
    return result == true;
  }

  /// Download the raw gzipped track bytes from Storage without decoding.
  /// Used by the backup flow which wants to archive the gzipped blob
  /// verbatim so restore is a byte-for-byte upload.
  Future<Uint8List> downloadTrackBytes(String path) async {
    return _client.storage.from(StorageBuckets.runs).download(path);
  }

  /// Upload pre-gzipped track bytes to Storage at `{userId}/{runId}.json.gz`.
  /// Used on the restore path to re-home a track without re-encoding.
  Future<void> uploadTrackBytes({
    required String userId,
    required String runId,
    required Uint8List gzippedBytes,
  }) async {
    final path = '$userId/$runId.json.gz';
    await _client.storage.from(StorageBuckets.runs).uploadBinary(
          path,
          gzippedBytes,
          fileOptions: const FileOptions(
            // gzipped JSON bytes — `application/gzip` is the only
            // shape the `runs` bucket MIME allowlist (migration
            // 20260815_001) accepts for tracks. `application/json`
            // would 415 the upload.
            contentType: 'application/gzip',
            upsert: true,
          ),
        );
  }

  /// Re-home a pre-gzipped HR sidecar to `{userId}/{runId}.hr.json.gz`
  /// (decisions §116). Backup-restore twin of [uploadTrackBytes] for the
  /// indoor/treadmill HR series. The caller then stamps the run's
  /// `hr_series_url` to this path.
  Future<void> uploadHrSeriesBytes({
    required String userId,
    required String runId,
    required Uint8List gzippedBytes,
  }) async {
    final path = '$userId/$runId.hr.json.gz';
    await _client.storage.from(StorageBuckets.runs).uploadBinary(
          path,
          gzippedBytes,
          fileOptions: const FileOptions(
            contentType: 'application/gzip',
            upsert: true,
          ),
        );
  }

  /// Raw-row read of the `runs` table. Returns the underlying row
  /// `Map<String, dynamic>` rather than a `Run` domain object — the
  /// backup writer needs every column verbatim so round-trips preserve
  /// source-specific metadata, `event_id`, and anything else added to
  /// the schema later.
  Future<List<Map<String, dynamic>>> fetchRunRowsRaw() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final data = await _client
        .from(RunRow.table)
        .select()
        .eq(RunRow.colUserId, userId)
        .order(RunRow.colStartedAt, ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Upsert a raw run row. The backup restore path builds these
  /// directly from the archive so `metadata`, `source`, and every other
  /// column survive untouched.
  Future<void> upsertRunRowRaw(Map<String, dynamic> row) async {
    await _client.from(RunRow.table).upsert(row);
  }

  // -- Storage helpers --

  Future<String> _uploadTrack({
    required String userId,
    required String runId,
    required List<Waypoint> track,
  }) async {
    final json = jsonEncode(track.map(_waypointToJson).toList());
    final bytes = Uint8List.fromList(gzip.encode(utf8.encode(json)));
    final path = '$userId/$runId.json.gz';
    await _client.storage.from(StorageBuckets.runs).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            // The byte payload IS gzipped (line above), so the MIME
            // must match. `application/gzip` is on the `runs` bucket
            // allowlist (migration 20260815_001); `application/json`
            // is not and would 415 the upload, silently breaking
            // every live-recording save on mobile.
            contentType: 'application/gzip',
            upsert: true,
          ),
        );
    return path;
  }

  Future<List<Waypoint>> _downloadTrack(String path) async {
    final bytes = await _client.storage.from(StorageBuckets.runs).download(path);
    final json = utf8.decode(gzip.decode(bytes));
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((t) => _waypointFromJson(t as Map<String, dynamic>)).toList();
  }

  /// Test-only: exposes the private waypoint codec used by the track
  /// upload/download path. Returns the JSON shape stored inside the
  /// gzipped track blob in the `runs` Storage bucket.
  @visibleForTesting
  static Map<String, dynamic> debugWaypointToJson(Waypoint w) =>
      _waypointToJson(w);

  /// Test-only: inverse of [debugWaypointToJson].
  @visibleForTesting
  static Waypoint debugWaypointFromJson(Map<String, dynamic> m) =>
      _waypointFromJson(m);

  /// Test-only: exposes [_runFromRow] so the row-to-domain conversion can
  /// be exercised without booting Supabase.
  @visibleForTesting
  static Run debugRunFromRow(Map<String, dynamic> row) => _runFromRow(row);

  /// Test-only: exposes the bag-strip that saveRun applies before persisting
  /// a run, so the activity_type / is_dnf promotion (no double-write into the
  /// metadata bag) can be pinned without booting Supabase.
  @visibleForTesting
  static Map<String, dynamic>? debugMetadataWithoutPromotedColumns(
    Map<String, dynamic>? metadata,
  ) =>
      _metadataWithoutPromotedColumns(metadata);

  /// Test-only: exposes [_embeddedBestSeconds] for the same reason.
  @visibleForTesting
  static int? debugEmbeddedBestSeconds(
    Map<String, dynamic>? metadata,
    String key,
  ) =>
      _embeddedBestSeconds(metadata, key);

  /// Test-only: exposes [_routeFromRow] for the same reason.
  @visibleForTesting
  static Route debugRouteFromRow(Map<String, dynamic> row) =>
      _routeFromRow(row);

  static Map<String, dynamic> _waypointToJson(Waypoint w) => {
        'lat': w.lat,
        'lng': w.lng,
        'ele': w.elevationMetres,
        'ts': w.timestamp?.toUtc().toIso8601String(),
        if (w.bpm != null) 'bpm': w.bpm,
      };

  static Waypoint _waypointFromJson(Map<String, dynamic> m) => Waypoint(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        elevationMetres: (m['ele'] as num?)?.toDouble(),
        timestamp: m['ts'] != null ? DateTime.tryParse(m['ts'] as String) : null,
        bpm: (m['bpm'] as num?)?.toInt(),
      );

  /// Auto-link helper: ask the DB which of the user's saved routes
  /// overlap a recorded run's track. Backed by the
  /// `routes_intersecting_track` RPC (migration 20260610_001), which
  /// uses the `routes.geom` GIST index to pre-filter candidates.
  ///
  /// Caller decides the final ranking. The combination "endpoints
  /// close" (`startOffsetM + endOffsetM` under ~2× tolerance) AND
  /// "lengths similar" (`(distanceM - track length)/track length` <
  /// 0.20) is the strong "definitely the same route" signal; either
  /// dimension alone is too noisy. See the matching policy comment in
  /// `apps/web/src/routes/runs/[id]/+page.svelte:suggestRoute`.
  Future<List<RouteMatchCandidate>> fetchRoutesIntersectingTrack(
    List<Waypoint> track, {
    double toleranceMetres = 100,
    int maxResults = 10,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || track.length < 2) return const [];
    final rows = await _client.rpc(
      'routes_intersecting_track',
      params: <String, dynamic>{
        'caller_user_id': userId,
        'track_geojson': <String, dynamic>{
          'type': 'LineString',
          'coordinates': track.map((w) => [w.lng, w.lat]).toList(),
        },
        'tolerance_m': toleranceMetres,
        'max_results': maxResults,
      },
    );
    if (rows is! List) return const [];
    return rows.cast<Map<String, dynamic>>().map(RouteMatchCandidate.fromJson).toList();
  }

  /// Persist `runs.route_id`. Used by the mobile auto-link suggestion
  /// on RunDetailScreen and by any future flow that needs to back-link
  /// a run to a saved route. Idempotent — re-linking to the same id
  /// is a no-op.
  Future<void> linkRunToRoute(String runId, String routeId) async {
    await _client
        .from(RunRow.table)
        .update(<String, dynamic>{RunRow.colRouteId: routeId})
        .eq(RunRow.colId, runId);
  }

  /// Saves a [Route] to the backend.
  /// Persist a new route. Mirrors `apps/web/src/lib/data.ts:saveRoute`:
  /// same column set, same description normalisation (trim → empty
  /// becomes null), same `club_id` handling.
  ///
  /// **Id-handling parity with `saveRun`:** the caller's
  /// client-generated `route.id` is written into the insert and
  /// becomes the canonical row id. The previous implementation
  /// stripped the id and let the server generate one, which left the
  /// local `LocalRouteStore` entry pointing at `clientId` while the
  /// server row had a different `serverId` — any later edit / delete
  /// by id would miss the server row. Routes now follow the same
  /// client-id-is-authoritative model that runs use.
  Future<void> saveRoute(Route route) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final body = buildSaveRouteBody(route, userId);
    await _client.from(RouteRow.table).insert(body);
  }

  /// Pure helper that produces the insert body for [saveRoute]. Lifted
  /// to a static so the row-shape can be unit-tested (description
  /// trimming, client-id preservation, `club_id` pass-through, web
  /// parity) without standing up a Supabase fixture.
  @visibleForTesting
  static Map<String, dynamic> buildSaveRouteBody(Route route, String userId) {
    // Match web's description normalisation: trim, then collapse
    // empty-after-trim to null so the column stays clean for
    // `IS NOT NULL` queries.
    final descriptionRaw = route.description?.trim();
    final description =
        (descriptionRaw == null || descriptionRaw.isEmpty) ? null : descriptionRaw;
    final row = RouteRow(
      id: route.id,
      userId: userId,
      name: route.name,
      waypoints: route.waypoints
          .map((w) => <String, dynamic>{
                'lat': w.lat,
                'lng': w.lng,
                'ele': w.elevationMetres,
              })
          .toList(),
      distanceM: route.distanceMetres,
      elevationM: route.elevationGainMetres,
      isPublic: route.isPublic,
      surface: route.surface,
      tags: route.tags,
      isFeatured: route.featured,
      runCount: route.runCount,
      isStarred: route.isStarred,
      clubId: route.clubId,
      description: description,
      shadowHidden: false,
    );
    // Drop null / server-default columns so Postgres fills them in.
    // `id` is NOT dropped — we want the client UUID to flow through
    // so local and server agree on row identity (matches `saveRun`).
    // `shadow_hidden` is a moderation column owned by the auto-hide
    // trigger — never written from the client.
    return Map<String, dynamic>.from(row.toJson())
      ..remove('shadow_hidden')
      ..removeWhere((k, v) => v == null);
  }

  /// Fetches the user's saved routes, newest first.
  ///
  /// `limit` caps the number of rows returned (default 200 — kept high
  /// to preserve the existing one-shot semantics for unbounded callers
  /// like the routes-screen full-sync path). `before` paginates: pass
  /// the oldest already-loaded route's `created_at` to fetch the next
  /// page. Cursor over offset because routes are append-only-by-time
  /// and a cursor is stable against concurrent inserts/deletes.
  Future<List<Route>> getRoutes({
    int limit = 200,
    DateTime? before,
    bool starredOnly = false,
  }) async {
    var query = _client.from(RouteRow.table).select();
    if (starredOnly) {
      query = query.eq(RouteRow.colIsStarred, true);
    }
    if (before != null) {
      query = query.lt(RouteRow.colCreatedAt, before.toIso8601String());
    }
    final data = await query
        .order(RouteRow.colCreatedAt, ascending: false)
        .limit(limit);

    return data.map<Route>((row) => _routeFromRow(row)).toList();
  }

  /// Search public routes. Supports full-text name search, distance range
  /// filtering, and surface type filtering. Uses the `routes_public` partial
  /// index and `routes_name_search` GIN index.
  Future<List<Route>> searchPublicRoutes({
    String? query,
    double? minDistanceM,
    double? maxDistanceM,
    String? surface,
    List<String>? tags,
    bool featuredOnly = false,
    String sort = 'newest',
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc('search_public_routes', params: {
      'p_query': (query != null && query.trim().isNotEmpty) ? query.trim() : null,
      'p_min_distance_m': minDistanceM,
      'p_max_distance_m': maxDistanceM,
      'p_surface': (surface != null && surface.isNotEmpty) ? surface : null,
      'p_tags': (tags != null && tags.isNotEmpty) ? tags : null,
      'p_featured_only': featuredOnly,
      'p_sort': sort,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (data as List)
        .map<Route>((row) => _routeFromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Cross-club activity discovery. Searches PUBLIC clubs' events across the
  /// typed-events model by category / discipline / cadence / weekday /
  /// time-of-day / paid-or-free. Backs the Social Discover tab. Mirrors
  /// `searchPublicEvents` in `apps/web/src/lib/core/data.ts` + the
  /// `search_public_events` RPC (migrations 20270110_001 + 20270111_001).
  /// `security invoker` + scoped to `clubs.is_public = true`, so it works
  /// logged-out and can only return rows the caller could already read.
  Future<List<PublicEventResult>> searchPublicEvents({
    String? query,
    String? category,
    String? cadence,
    String? byday,
    String? paid,
    String? time,
    int limit = 60,
  }) async {
    final q = query?.trim();
    final data = await _client.rpc('search_public_events', params: {
      'p_query': (q != null && q.isNotEmpty) ? q : null,
      'p_category': category,
      'p_cadence': cadence,
      'p_byday': byday,
      'p_paid': paid,
      'p_time': time,
      'p_limit': limit,
    });
    return (data as List)
        .map<PublicEventResult>(
            (row) => PublicEventResult.fromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// The N most-used tags across public routes, for filter-chip population.
  /// Calls the `popular_route_tags` RPC so aggregation happens in Postgres
  /// (one GIN-indexed scan, returns a few KB) instead of pulling up to
  /// 500 rows down the wire and counting in memory.
  Future<List<String>> fetchPopularRouteTags({int limit = 20}) async {
    final rows = await _client
        .rpc('popular_route_tags', params: {'tag_limit': limit});
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => r['tag'] as String)
        .toList();
  }

  Future<void> updateRouteTags(String routeId, List<String> tags) async {
    await _client.from(RouteRow.table).update({
      'tags': tags,
      RouteRow.colUpdatedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(RouteRow.colId, routeId);
  }

  /// Find public routes near a geographic point, sorted by distance.
  /// Uses the PostGIS-backed `nearby_routes` RPC.
  Future<List<Route>> nearbyPublicRoutes({
    required double lat,
    required double lng,
    double radiusM = 50000,
    int limit = 50,
  }) async {
    final data = await _client.rpc('nearby_routes', params: {
      'lat': lat,
      'lng': lng,
      'radius_m': radiusM,
      'max_results': limit,
    });
    return (data as List)
        .map<Route>((row) => _routeFromRow(row as Map<String, dynamic>))
        .toList();
  }

  /// Discoverable public routes inside the viewport bbox for the route
  /// discovery map. Mirror of the web `fetchDiscoverableRoutesInBbox`.
  /// [filter] is the lens: 'popular' (default) | 'featured' | 'friends' |
  /// 'hidden_gems'. [distMin]/[distMax] are the parallel race-distance
  /// band bounds (a null [distMax] element = open-ended ultra); omit them
  /// for no distance filter. Fails soft to an empty list.
  Future<List<DiscoverableRoutePin>> fetchDiscoverableRoutesInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
    String filter = 'popular',
    List<double>? distMin,
    List<double?>? distMax,
  }) async {
    try {
      final params = <String, dynamic>{
        'p_min_lng': minLng,
        'p_min_lat': minLat,
        'p_max_lng': maxLng,
        'p_max_lat': maxLat,
        'p_limit': limit,
        'p_filter': filter,
      };
      if (distMin != null && distMin.isNotEmpty) {
        params['p_dist_min'] = distMin;
        params['p_dist_max'] = distMax;
      }
      final data = await _client.rpc('discoverable_routes_in_bbox',
          params: params);
      if (data is! List) return const [];
      return data.map<DiscoverableRoutePin>((row) {
        final r = row as Map<String, dynamic>;
        return DiscoverableRoutePin(
          id: r['id'] as String,
          name: (r['name'] as String?) ?? 'Route',
          slug: r['slug'] as String?,
          featured: (r['is_featured'] as bool?) ?? false,
          distanceM: (r['distance_m'] as num?)?.toDouble() ?? 0,
          elevationM: (r['elevation_m'] as num?)?.toDouble(),
          surface: (r['surface'] as String?) ?? '',
          runCount: (r['run_count'] as num?)?.toInt() ?? 0,
          lat: (r['lat'] as num).toDouble(),
          lng: (r['lng'] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Public clubs inside the viewport bbox for the discovery map's club
  /// layer. Mirror of the web `fetchClubsInBbox`. Fails soft.
  Future<List<ClubPin>> fetchClubsInBbox({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
    int limit = 100,
  }) async {
    try {
      final data = await _client.rpc('clubs_in_bbox', params: {
        'p_min_lng': minLng,
        'p_min_lat': minLat,
        'p_max_lng': maxLng,
        'p_max_lat': maxLat,
        'p_limit': limit,
      });
      if (data is! List) return const [];
      return data.map<ClubPin>((row) {
        final r = row as Map<String, dynamic>;
        return ClubPin(
          id: r['id'] as String,
          name: (r['name'] as String?) ?? 'Club',
          slug: r['slug'] as String?,
          avatarUrl: r['avatar_url'] as String?,
          locationLabel: r['location_label'] as String?,
          memberCount: (r['member_count'] as num?)?.toInt() ?? 0,
          lat: (r['lat'] as num).toDouble(),
          lng: (r['lng'] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  // -- Route reviews --

  /// Fetch all reviews for a route, newest first.
  Future<List<RouteReviewRow>> getRouteReviews(String routeId) async {
    final data = await _client
        .from(RouteReviewRow.table)
        .select()
        .eq(RouteReviewRow.colRouteId, routeId)
        .order(RouteReviewRow.colCreatedAt, ascending: false);
    return data
        .map<RouteReviewRow>(
            (row) => RouteReviewRow.fromJson(row))
        .toList();
  }

  /// Submit or update a review for a route (one per user per route).
  Future<void> upsertRouteReview({
    required String routeId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _client.from(RouteReviewRow.table).upsert({
      RouteReviewRow.colRouteId: routeId,
      RouteReviewRow.colUserId: userId,
      RouteReviewRow.colRating: rating,
      RouteReviewRow.colComment: comment,
    }, onConflict: '${RouteReviewRow.colRouteId},${RouteReviewRow.colUserId}');
  }

  /// Delete the current user's review of a route.
  Future<void> deleteRouteReview(String routeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from(RouteReviewRow.table)
        .delete()
        .eq(RouteReviewRow.colRouteId, routeId)
        .eq(RouteReviewRow.colUserId, userId);
  }

  /// Update a route's is_public flag.
  Future<void> setRoutePublic(String routeId, bool isPublic) async {
    await _client
        .from(RouteRow.table)
        .update({RouteRow.colIsPublic: isPublic})
        .eq(RouteRow.colId, routeId);
  }

  // ────────────────── Following + public profiles ──────────────────
  //
  // Mirror of `apps/web/src/lib/data.ts` — the social engagement loop
  // is web-canonical (decisions §31), and the android app needs the
  // same primitives to build feed / profile / notifications screens.
  // Methods are intentionally narrow wrappers over the row classes;
  // any cross-shape (FeedEntry, ProfileSummary) lives in core_models.

  /// Follow `targetUserId`. No-op if already following (composite-PK
  /// duplicate is swallowed by the unique-violation guard).
  Future<void> followUser(String targetUserId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    if (viewerId == targetUserId) return;
    await _client.from(UserFollowRow.table).insert({
      UserFollowRow.colFollowerId: viewerId,
      UserFollowRow.colFolloweeId: targetUserId,
    });
  }

  /// Stop following `targetUserId`.
  Future<void> unfollowUser(String targetUserId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(UserFollowRow.table)
        .delete()
        .eq(UserFollowRow.colFollowerId, viewerId)
        .eq(UserFollowRow.colFolloweeId, targetUserId);
  }

  /// Block `targetUserId` via the `block_user` SECURITY DEFINER RPC.
  /// Mirrors `apps/web/src/lib/data.ts#blockUser`. The RPC also drains
  /// existing follow rows in either direction so a viewer-initiated
  /// block subsumes unfollow on both sides — see migration
  /// `20261012_001_user_blocks.sql`.
  Future<void> blockUser(String targetUserId, {String? reason}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    if (viewerId == targetUserId) return;
    await _client.rpc('block_user', params: {
      'p_target': targetUserId,
      'p_reason': reason,
    });
  }

  /// Unblock `targetUserId` via the `unblock_user` RPC.
  Future<void> unblockUser(String targetUserId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client.rpc('unblock_user', params: {'p_target': targetUserId});
  }

  /// Returns true when the viewer has blocked `targetUserId`. Reads
  /// the `user_blocks` table directly — RLS already gates the read
  /// to rows where the viewer is the blocker.
  Future<bool> isBlockedByViewer(String targetUserId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return false;
    final rows = await _client
        .from('user_blocks')
        .select('blocker_id')
        .eq('blocker_id', viewerId)
        .eq('blocked_id', targetUserId)
        .limit(1);
    return rows.isNotEmpty;
  }

  /// People who follow `userId`. `limit` is a protective cap, not a
  /// pagination cursor — promote to cursor pagination if any user
  /// approaches the ceiling in practice.
  Future<List<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFollowerId)
        .eq(UserFollowRow.colFolloweeId, userId)
        .order(UserFollowRow.colFollowedAt, ascending: false)
        .range(offset, offset + limit - 1);
    final ids = edges
        .map<String>((e) => e[UserFollowRow.colFollowerId] as String)
        .toList();
    if (ids.isEmpty) return const [];
    final profiles = await _client
        .from(UserProfileRow.table)
        .select()
        .inFilter(UserProfileRow.colId, ids);
    return profiles
        .map<UserProfileRow>((row) => UserProfileRow.fromJson(row))
        .toList();
  }

  /// People `userId` follows.
  Future<List<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, userId)
        .order(UserFollowRow.colFollowedAt, ascending: false)
        .range(offset, offset + limit - 1);
    final ids = edges
        .map<String>((e) => e[UserFollowRow.colFolloweeId] as String)
        .toList();
    if (ids.isEmpty) return const [];
    final profiles = await _client
        .from(UserProfileRow.table)
        .select()
        .inFilter(UserProfileRow.colId, ids);
    return profiles
        .map<UserProfileRow>((row) => UserProfileRow.fromJson(row))
        .toList();
  }

  /// Free-text people search. Routes through the
  /// `search_user_profiles` SECURITY DEFINER RPC so the search
  /// honours the `discoverable_in_search` opt-out pref (persona-hunt
  /// Round 3 finding Woman #2 — a runner who's been stalked must be
  /// able to remove themselves from name search; user_settings has
  /// owner-only RLS so the join can't run client-side).
  ///
  /// Display-name search ranked for web parity: public-runs count
  /// desc, then shared-clubs count desc, then display name asc.
  /// Mirrors `apps/web/src/lib/data.ts:searchPeople` +
  /// `apps/web/src/lib/search_ranking.ts:comparePeopleRank`.
  Future<List<PeopleSuggestion>> searchPeople(
    String query, {
    int limit = 20,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final viewerId = _client.auth.currentUser?.id;
    final candidateLimit = limit * 3 > 120 ? 120 : limit * 3;
    final profiles = await _client.rpc('search_user_profiles', params: {
      'p_query': term,
      'p_limit': candidateLimit,
    });
    final ids = (profiles as List<dynamic>)
        .map<String>((p) => (p as Map<String, dynamic>)['id'] as String)
        .where((id) => id != viewerId)
        .toList();
    if (ids.isEmpty) return const [];
    final hydrated =
        await _hydratePeopleSuggestions(ids, viewerId, sharedCounts: const {});
    hydrated.sort(comparePeopleRank);
    return hydrated.take(limit).toList();
  }

  /// Pure comparator mirroring `comparePeopleRank` in
  /// `apps/web/src/lib/search_ranking.ts`. Sorts by:
  ///   1. `publicRunsCount` desc — active users surface above bots
  ///   2. `sharedClubs` desc — co-members tied on activity surface higher
  ///   3. `displayName` asc — stable alphabetical tie-break
  ///
  /// Zero-runs accounts aren't *hidden* — a friend the viewer
  /// searches for by exact name may have posted no runs yet — they
  /// just rank last within the result set. Lifted to a static so
  /// tests can pin the contract against the web equivalent.
  @visibleForTesting
  static int comparePeopleRank(PeopleSuggestion a, PeopleSuggestion b) {
    if (b.publicRunsCount != a.publicRunsCount) {
      return b.publicRunsCount.compareTo(a.publicRunsCount);
    }
    if (b.sharedClubs != a.sharedClubs) {
      return b.sharedClubs.compareTo(a.sharedClubs);
    }
    return (a.displayName ?? '').compareTo(b.displayName ?? '');
  }

  /// Suggested people for the social People surface: members of the
  /// viewer's clubs they don't already follow. Ordered by shared-club
  /// count desc, then by display_name. Mirrors `fetchSuggestedPeople`
  /// in `apps/web/src/lib/data.ts`.
  Future<List<PeopleSuggestion>> fetchSuggestedPeople({int limit = 12}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final myMemberRows = await _client
        .from(ClubMemberRow.table)
        .select(ClubMemberRow.colClubId)
        .eq(ClubMemberRow.colUserId, viewerId)
        .eq(ClubMemberRow.colStatus, 'active');
    final myClubIds = myMemberRows
        .map<String>((r) => r[ClubMemberRow.colClubId] as String)
        .toList();
    if (myClubIds.isEmpty) return const [];

    final coMemberRows = await _client
        .from(ClubMemberRow.table)
        .select('${ClubMemberRow.colUserId}, ${ClubMemberRow.colClubId}')
        .inFilter(ClubMemberRow.colClubId, myClubIds)
        .eq(ClubMemberRow.colStatus, 'active')
        .neq(ClubMemberRow.colUserId, viewerId);
    if (coMemberRows.isEmpty) return const [];

    final shared = <String, int>{};
    for (final row in coMemberRows) {
      final uid = row[ClubMemberRow.colUserId] as String;
      shared[uid] = (shared[uid] ?? 0) + 1;
    }

    final followedRows = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, viewerId)
        .inFilter(UserFollowRow.colFolloweeId, shared.keys.toList());
    for (final r in followedRows) {
      shared.remove(r[UserFollowRow.colFolloweeId] as String);
    }
    if (shared.isEmpty) return const [];

    final hydrated = await _hydratePeopleSuggestions(
      shared.keys.toList(),
      viewerId,
      sharedCounts: shared,
    );
    hydrated.sort((a, b) {
      if (b.sharedClubs != a.sharedClubs) {
        return b.sharedClubs.compareTo(a.sharedClubs);
      }
      return (a.displayName ?? '').compareTo(b.displayName ?? '');
    });
    return hydrated.take(limit).toList();
  }

  Future<List<PeopleSuggestion>> _hydratePeopleSuggestions(
    List<String> ids,
    String? viewerId, {
    required Map<String, int> sharedCounts,
  }) async {
    if (ids.isEmpty) return const [];
    final profilesF = _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, ids);
    final runsF = _client
        .from(RunRow.table)
        .select(RunRow.colUserId)
        .inFilter(RunRow.colUserId, ids)
        .eq(RunRow.colIsPublic, true);
    final followsF = viewerId == null
        ? Future.value(<dynamic>[])
        : _client
            .from(UserFollowRow.table)
            .select(UserFollowRow.colFolloweeId)
            .eq(UserFollowRow.colFollowerId, viewerId)
            .inFilter(UserFollowRow.colFolloweeId, ids);
    final results = await Future.wait([profilesF, runsF, followsF]);
    final profileRows = results[0];
    final runRows = results[1];
    final followRows = results[2];

    final counts = <String, int>{};
    for (final r in runRows) {
      final row = r as Map<String, dynamic>;
      final uid = row[RunRow.colUserId] as String;
      counts[uid] = (counts[uid] ?? 0) + 1;
    }
    final follows = <String>{};
    for (final r in followRows) {
      final row = r as Map<String, dynamic>;
      follows.add(row[UserFollowRow.colFolloweeId] as String);
    }
    return profileRows.map<PeopleSuggestion>((p) {
      final row = p as Map<String, dynamic>;
      final id = row['id'] as String;
      return PeopleSuggestion(
        id: id,
        displayName: row['display_name'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        publicRunsCount: counts[id] ?? 0,
        sharedClubs: sharedCounts[id] ?? 0,
        viewerFollows: follows.contains(id),
      );
    }).toList();
  }

  /// Best-effort auto-link of a freshly-saved run to a plan workout
  /// scheduled for the same calendar date, matched within 25% of the
  /// workout's target distance. Client-side mirror of
  /// `autoMatchRunToPlanWorkout` in `apps/web/src/lib/core/data.ts` —
  /// there is no `auto_match_run_to_plan_workout` RPC; web does this with
  /// direct queries and so do we. Returns the matched workout id, or null
  /// when nothing matches.
  Future<String?> autoMatchRunToPlanWorkout(
    String runId,
    DateTime runDate,
    double runDistanceM, {
    List<String>? planWeekIds,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    final isoDate = '${runDate.year.toString().padLeft(4, '0')}-'
        '${runDate.month.toString().padLeft(2, '0')}-'
        '${runDate.day.toString().padLeft(2, '0')}';

    // [planWeekIds] lets batch callers (saveRunsBatch) fetch the plan/week
    // scope once for the whole batch instead of once per run.
    final weekIds = planWeekIds ?? await _planWeekIdsForUser(userId);
    if (weekIds.isEmpty) return null;

    final candidates = await _client
        .from(PlanWorkoutRow.table)
        .select('${PlanWorkoutRow.colId}, ${PlanWorkoutRow.colTargetDistanceM}, '
            '${PlanWorkoutRow.colCompletedRunId}, ${PlanWorkoutRow.colWeekId}')
        .inFilter(PlanWorkoutRow.colWeekId, weekIds)
        .eq(PlanWorkoutRow.colScheduledDate, isoDate)
        .isFilter(PlanWorkoutRow.colCompletedRunId, null);

    // Closest target distance within 25% wins (mirrors web's sort-by-delta).
    String? bestId;
    double? bestDelta;
    for (final c in candidates as List) {
      final target = (c as Map)[PlanWorkoutRow.colTargetDistanceM];
      if (target is! num || target <= 0) continue;
      final delta = (target.toDouble() - runDistanceM).abs();
      if (delta / target > 0.25) continue;
      if (bestDelta == null || delta < bestDelta) {
        bestId = c[PlanWorkoutRow.colId] as String;
        bestDelta = delta;
      }
    }
    if (bestId == null) return null;

    await _client.from(PlanWorkoutRow.table).update({
      PlanWorkoutRow.colCompletedRunId: runId,
      PlanWorkoutRow.colManuallyCompleted: false,
      PlanWorkoutRow.colCompletedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(PlanWorkoutRow.colId, bestId);
    return bestId;
  }

  /// The caller's plan-week ids, used to constrain the auto-match workout
  /// query with `inFilter(week_id, ...)`. RLS on `plan_workouts` already
  /// chains through `plan_weeks -> training_plans.user_id`, but the explicit
  /// scope is defence in depth: without it a future RLS edit that broke
  /// the chain could match a run to another user's workout. Mirrors the
  /// web client-realtime H2 data-isolation fix.
  Future<List<String>> _planWeekIdsForUser(String userId) async {
    final plans = await _client
        .from(TrainingPlanRow.table)
        .select(
            '${TrainingPlanRow.colId}, ${PlanWeekRow.table}(${PlanWeekRow.colId})')
        .eq(TrainingPlanRow.colUserId, userId);
    return <String>[
      for (final p in plans as List)
        for (final w in ((p as Map)[PlanWeekRow.table] as List? ?? const []))
          (w as Map)[PlanWeekRow.colId] as String,
    ];
  }

  /// Recent public runs from a single user — drives the runs tab on
  /// `/u/[id]`-equivalent profile screens. Capped at `limit`.
  /// Fetch a single run by id. RLS gates access — owners see their own
  /// (public or private), other viewers only see runs where `is_public`
  /// is true.
  /// Reads a public run by id through the `public_runs` view
  /// (decisions §33 wire-leak follow-up, migration `20260626_001`).
  /// The view drops `external_id`, redacts the metadata bag's audit /
  /// sync / training-plan-linkage keys, and nulls `route_id` /
  /// `event_id` when the joined target isn't itself public. The
  /// where clause restricts to `is_public = true` — a private run
  /// is invisible here even to its owner, which matches the
  /// "share page = what your followers see" contract from §33's
  /// trade-off list.
  Future<RunRow?> fetchPublicRunById(String runId) async {
    final row = await _client
        .from('public_runs')
        .select()
        .eq(RunRow.colId, runId)
        .maybeSingle();
    return row == null ? null : RunRow.fromJson(row);
  }

  /// Toggle the owner's `is_starred` flag on a route. Drives the
  /// watch's starred-only route picker (see watch_wear/SupabaseClient).
  /// RLS restricts updates to the owner.
  Future<void> setRouteStar(String routeId, bool starred) async {
    await _client
        .from(RouteRow.table)
        .update({
          RouteRow.colIsStarred: starred,
          RouteRow.colUpdatedAt: DateTime.now().toUtc().toIso8601String(),
        })
        .eq(RouteRow.colId, routeId);
  }

  /// Fetch a single route by id. RLS gates: owners see their own
  /// (public or private), other viewers only see public routes or
  /// routes owned by a club they belong to.
  /// Fetches a route row plus the owner's user id. The owner id is
  /// Read a route by id. Owner-aware:
  ///
  /// 1. First tries the bare `routes` table — RLS lets owners and
  ///    active club members see the full row, which carries the
  ///    unclipped polyline for owners' own surfaces.
  /// 2. If that returns nothing (anon, or non-owner viewing a public
  ///    route), falls back to the `public_routes` view (which strips
  ///    `waypoints` / `geom` / `start_point` / `is_starred` server-
  ///    side) and overlays the polyline from `clip_route_for_viewer`
  ///    so the runner's privacy zones are respected.
  ///
  /// Closes the audit/public-rows + audit/privacy-zones High finding
  /// from /audit/all on 2026-05-03 — see migration
  /// 20260703_001_public_routes_view.sql.
  ///
  /// `ownerId` is peeled out alongside the [Route] domain object so
  /// callers on public-share surfaces can decide whether further
  /// owner-only affordances apply.
  Future<({Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async {
    final viewerId = _client.auth.currentUser?.id;
    final ownerRow = await _client
        .from(RouteRow.table)
        .select()
        .eq(RouteRow.colId, routeId)
        .maybeSingle();
    if (ownerRow != null) {
      final ownerId = ownerRow[RouteRow.colUserId] as String?;
      if (ownerId == viewerId) {
        return (route: _routeFromRow(ownerRow), ownerId: ownerId);
      }
      // RLS also surfaces the base row to an active club member. A
      // non-owner must never receive the unclipped polyline, so route the
      // waypoints through the same server-side privacy clip the public
      // branch below uses.
      final routeRow = Map<String, dynamic>.from(ownerRow);
      routeRow['waypoints'] =
          _waypointsToJson(await _clipRouteForViewer(routeId));
      return (route: _routeFromRow(routeRow), ownerId: ownerId);
    }

    final publicRow = await _client
        .from('public_routes')
        .select()
        .eq(RouteRow.colId, routeId)
        .maybeSingle();
    if (publicRow == null) return (route: null, ownerId: null);

    // public_routes carries no `waypoints`; fetch the clipped polyline
    // separately so the response respects the owner's privacy zones.
    final ownerId = publicRow[RouteRow.colUserId] as String?;
    final routeRow = Map<String, dynamic>.from(publicRow);
    routeRow['waypoints'] =
        _waypointsToJson(await _clipRouteForViewer(routeId));
    return (route: _routeFromRow(routeRow), ownerId: ownerId);
  }

  /// Server-side privacy-zone-clipped waypoints for a route the viewer
  /// does not own. Fails closed (empty polyline) on RPC error rather
  /// than leaking the unclipped track — matches the `clipTrackForUser`
  /// contract. Used by both non-owner read paths in [fetchRouteById].
  Future<List<Waypoint>> _clipRouteForViewer(String routeId) async {
    try {
      final clip = await _client.rpc(
        'clip_route_for_viewer',
        params: {'p_route_id': routeId},
      );
      return (clip as List?)
              ?.map((p) {
                final m = p as Map<String, dynamic>;
                return Waypoint(
                  lat: (m['lat'] as num).toDouble(),
                  lng: (m['lng'] as num).toDouble(),
                  elevationMetres: (m['ele'] as num?)?.toDouble(),
                );
              })
              .toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _waypointsToJson(List<Waypoint> points) =>
      points
          .map((w) => {
                'lat': w.lat,
                'lng': w.lng,
                if (w.elevationMetres != null) 'ele': w.elevationMetres,
              })
          .toList();

  Future<List<RunRow>> fetchPublicRunsByUser(String userId, {int limit = 50}) async {
    // Reads through the public_runs view (decisions §33 wire-leak
    // follow-up, migration 20260626_001) so the redaction applies
    // even when the caller is signed in. The view's where clause
    // restricts to is_public = true so the explicit eq filter is
    // redundant.
    final data = await _client
        .from('public_runs')
        .select()
        .eq(RunRow.colUserId, userId)
        .order(RunRow.colStartedAt, ascending: false)
        .limit(limit);
    return data.map<RunRow>((r) => RunRow.fromJson(r)).toList();
  }

  /// Public profile lookup by user ID. Returns null when the row
  /// doesn't exist or RLS hides it. Returns only the columns that are
  /// column-level granted to `authenticated`/`anon` on `user_profiles`:
  /// `id, display_name, avatar_url, created_at`. `subscription_tier`,
  /// `subscription_at`, `parkrun_number` are revoked (migration
  /// 20260707_001), and `preferred_unit` was dropped from the cross-user
  /// grant by 20260810_001 (it telegraphs rough region). Requesting any
  /// revoked column makes PostgREST reject the whole read with 42501
  /// "permission denied for table user_profiles". Self-reads of revoked
  /// columns go through [fetchMyProfile] (get_my_profile, SECURITY DEFINER).
  Future<UserProfileRow?> fetchPublicProfile(String userId) async {
    final row = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url, created_at')
        .eq(UserProfileRow.colId, userId)
        .maybeSingle();
    if (row == null) return null;
    return UserProfileRow.fromJson(row);
  }

  /// Read the GDPR Art 6(1)(a) coach-consent timestamp on the signed-in
  /// user's `user_profiles` row. Returns null when consent has not yet
  /// been recorded — callers should gate any Coach fan-out behind this.
  /// See audit/gdpr (2026-05-25).
  Future<DateTime?> fetchCoachConsentAt() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return null;
    final row = await _client
        .from('user_profiles')
        .select('coach_consent_at')
        .eq('id', viewerId)
        .maybeSingle();
    final raw = row?['coach_consent_at'];
    if (raw == null) return null;
    return DateTime.tryParse(raw as String);
  }

  /// Record the GDPR Art 6(1)(a) coach-consent acceptance for the signed-
  /// in user via the `record_coach_consent()` SECURITY DEFINER RPC, which
  /// stamps the SERVER's now() first-stamp-wins (not a client-chosen,
  /// backdatable value) and is the only sanctioned writer — direct writes
  /// to `coach_consent_at` are blocked at the DB. Returns the effective
  /// (original-if-already-set) timestamp.
  Future<DateTime?> recordCoachConsent() async {
    if (_client.auth.currentUser?.id == null) {
      throw StateError('not signed in');
    }
    final res = await _client.rpc('record_coach_consent');
    if (res is! String) return null;
    return DateTime.tryParse(res);
  }

  /// Withdraw coach consent (GDPR Art 7(3)) via the
  /// `withdraw_coach_consent()` SECURITY DEFINER RPC — the sanctioned
  /// inverse of [recordCoachConsent]. Clears the server-held stamp; the
  /// coach request gate then re-blocks the Coach until the user
  /// re-consents through [recordCoachConsent].
  ///
  /// Throws on a missing session: a silent return here would let the
  /// caller confirm a withdrawal that never reached the server.
  Future<void> withdrawCoachConsent() async {
    if (_client.auth.currentUser?.id == null) {
      throw StateError('not signed in');
    }
    await _client.rpc('withdraw_coach_consent');
  }

  /// Self-read of the full `user_profiles` row, including
  /// `subscription_tier`, `subscription_at`, `parkrun_number`. Backed by
  /// the `get_my_profile()` SECURITY DEFINER RPC because those columns
  /// are revoked from direct SELECT (migration 20260707_001).
  Future<UserProfileRow?> fetchMyProfile() async {
    final result = await _client.rpc('get_my_profile');
    if (result == null) return null;
    if (result is List) {
      if (result.isEmpty) return null;
      return UserProfileRow.fromJson(result.first as Map<String, dynamic>);
    }
    return UserProfileRow.fromJson(result as Map<String, dynamic>);
  }

  /// Stamp `onboarded_at = now()` and nothing else — the minimum write the
  /// home-screen onboarding gate needs to stop re-showing the setup wizard.
  /// Mirrors web's `skipOnboarding` in `apps/web/src/routes/onboarding`.
  /// Every other field stays at its existing default.
  Future<void> markOnboarded() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client.from(UserProfileRow.table).update({
      UserProfileRow.colOnboardedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(UserProfileRow.colId, uid);
  }

  /// Persist the post-signup setup-wizard answers and stamp `onboarded_at`
  /// so the gate releases. Mirrors web's `finishAndExit`:
  ///
  /// - `display_name`, `preferred_unit`, and (always, when supplied)
  ///   `date_of_birth` write to `user_profiles`. The bare DOB write is
  ///   unconditional — it backs the under-18 minor-exclusion floor in
  ///   people-search (a child-safety purpose distinct from consenting to
  ///   USE the DOB for HR / age-banded leaderboards). A declined consent
  ///   must not leave a NULL DOB that keeps the account discoverable.
  /// - `gender` + the Art 9 consent stamp write only under
  ///   [healthDataConsent]. `health_data_consent_at` is stamped
  ///   server-side by `grant_health_data_consent` (first-stamp-wins); a
  ///   direct write is rejected by the lock trigger (migration
  ///   20261118_001), so it is NOT in the profile update.
  ///
  /// The caller (the wizard) is responsible for the universal-bag writes
  /// (units, privacy default, primary goal, weight, consent-gated DOB
  /// mirror) via [SettingsService.updateUniversal] — the bag write and the
  /// profile write are independent.
  Future<void> completeOnboarding({
    String? displayName,
    required String preferredUnit,
    DateTime? dateOfBirth,
    String? gender,
    required bool healthDataConsent,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    if (healthDataConsent) {
      await grantHealthDataConsent();
    }
    final update = <String, dynamic>{
      UserProfileRow.colPreferredUnit: preferredUnit,
      UserProfileRow.colOnboardedAt:
          DateTime.now().toUtc().toIso8601String(),
    };
    final trimmedName = displayName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      update[UserProfileRow.colDisplayName] = trimmedName;
    }
    if (dateOfBirth != null) {
      update[UserProfileRow.colDateOfBirth] = dateOnly(dateOfBirth);
    }
    if (healthDataConsent) {
      update[UserProfileRow.colGender] =
          (gender != null && gender.isNotEmpty) ? gender : null;
    }
    await _client
        .from(UserProfileRow.table)
        .update(update)
        .eq(UserProfileRow.colId, uid);
  }

  /// `YYYY-MM-DD` for a `date`-typed column. The wizard's DOB picker is a
  /// calendar day, not an instant — store the wall-clock date with no zone
  /// so a user east/west of UTC doesn't roll a day.
  static String dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Upload a profile avatar into the public `avatars` bucket and point
  /// `user_profiles.avatar_url` at it. Mirrors web `uploadAvatar` (data.ts):
  /// the caller strips EXIF/GPS before passing [bytes] (mobile strips in the
  /// UI layer, like run/route photos). We remove-then-insert at the stable
  /// `{uid}/avatar.{ext}` path rather than upsert — the avatars bucket grants
  /// owner INSERT + DELETE but not the upsert WITH-CHECK path (see
  /// decisions.md §157) — and a `?v=` cache-bust keeps an Image off the
  /// previous picture. Returns the new public URL, already written to the row.
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final ext = _avatarMimeToExt[contentType];
    if (ext == null) {
      throw Exception('Unsupported image type — JPEG, PNG, or WebP only');
    }
    if (bytes.length > _avatarMaxBytes) {
      throw Exception('Image too large (2 MB max)');
    }
    // Clear any existing avatar (this ext + the others) so the upload is a
    // clean INSERT, not an upsert. remove() on a missing path is a no-op.
    await _client.storage
        .from(StorageBuckets.avatars)
        .remove(_avatarPaths(userId));
    final path = '$userId/avatar.$ext';
    await _client.storage.from(StorageBuckets.avatars).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    final base = _client.storage.from(StorageBuckets.avatars).getPublicUrl(path);
    final url = '$base?v=${DateTime.now().millisecondsSinceEpoch}';
    await _client
        .from('user_profiles')
        .update({'avatar_url': url}).eq('id', userId);
    return url;
  }

  /// Remove the user's avatar — drops every stored object for them and clears
  /// `user_profiles.avatar_url` to null (renderers fall back to initials).
  Future<void> removeAvatar() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.storage
        .from(StorageBuckets.avatars)
        .remove(_avatarPaths(userId));
    await _client
        .from('user_profiles')
        .update({'avatar_url': null}).eq('id', userId);
  }

  static const _avatarMimeToExt = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
  };
  // Matches the avatars bucket file_size_limit (2 MB, migration 20260927_001).
  static const _avatarMaxBytes = 2 * 1024 * 1024;
  static List<String> _avatarPaths(String userId) =>
      _avatarMimeToExt.values.map((e) => '$userId/avatar.$e').toList();

  /// Follower / following counts via `count: 'exact', head: true`.
  /// Returned as a `(followers, following)` tuple to keep the call
  /// sites readable.
  Future<({int followers, int following})> fetchFollowCounts(
    String userId,
  ) async {
    final followers = await _client
        .from(UserFollowRow.table)
        .count(CountOption.exact)
        .eq(UserFollowRow.colFolloweeId, userId);
    final following = await _client
        .from(UserFollowRow.table)
        .count(CountOption.exact)
        .eq(UserFollowRow.colFollowerId, userId);
    return (followers: followers, following: following);
  }

  /// Whether the current viewer follows `userId`.
  Future<bool> viewerFollows(String userId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null || viewerId == userId) return false;
    final row = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFollowerId)
        .eq(UserFollowRow.colFollowerId, viewerId)
        .eq(UserFollowRow.colFolloweeId, userId)
        .maybeSingle();
    return row != null;
  }

  // ───────────────────── Kudos on runs ─────────────────────

  /// One-tap kudos on a run. The composite PK makes this idempotent —
  /// a duplicate (kudos already given from another tab / session) is a
  /// 23505 no-op, not a duplicate row. Returns `true` only when a NEW
  /// row landed, so the optimistic UI applies the `+1` solely on a real
  /// change — a stale local `viewerHasKudos: false` must not bump the
  /// count above the server's, nor roll the heart back on a 23505.
  Future<bool> giveKudos(String runId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    try {
      await _client.from(RunKudosRow.table).insert({
        RunKudosRow.colUserId: viewerId,
        RunKudosRow.colRunId: runId,
      });
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return false;
      rethrow;
    }
  }

  /// Rescind kudos previously given on a run. Returns `true` when a row
  /// was actually deleted, `false` when there was nothing to remove —
  /// mirror of [giveKudos] so the optimistic `-1` only fires on a real
  /// delete.
  Future<bool> rescindKudos(String runId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return false;
    final deleted = await _client
        .from(RunKudosRow.table)
        .delete()
        .eq(RunKudosRow.colUserId, viewerId)
        .eq(RunKudosRow.colRunId, runId)
        .select(RunKudosRow.colUserId);
    return deleted.isNotEmpty;
  }

  /// Per-run engagement summary (kudos count, comment count, whether
  /// the viewer has given kudos). Mirrors the web `fetchEngagement
  /// Summaries` shape — used by feed cards and run-detail pages.
  Future<Map<String, ({int kudosCount, bool viewerHasKudos, int commentCount})>>
      fetchEngagementSummaries(List<String> runIds) async {
    if (runIds.isEmpty) return const {};
    final viewerId = _client.auth.currentUser?.id;

    final kudos = await _client
        .from(RunKudosRow.table)
        .select('${RunKudosRow.colRunId}, ${RunKudosRow.colUserId}')
        .inFilter(RunKudosRow.colRunId, runIds);
    final comments = await _client
        .from(RunCommentRow.table)
        .select(RunCommentRow.colRunId)
        .inFilter(RunCommentRow.colRunId, runIds);

    final kudosCount = <String, int>{};
    final viewerHas = <String, bool>{};
    for (final row in kudos) {
      final rid = row[RunKudosRow.colRunId] as String;
      kudosCount[rid] = (kudosCount[rid] ?? 0) + 1;
      if (viewerId != null && row[RunKudosRow.colUserId] == viewerId) {
        viewerHas[rid] = true;
      }
    }
    final commentCount = <String, int>{};
    for (final row in comments) {
      final rid = row[RunCommentRow.colRunId] as String;
      commentCount[rid] = (commentCount[rid] ?? 0) + 1;
    }
    return {
      for (final id in runIds)
        id: (
          kudosCount: kudosCount[id] ?? 0,
          viewerHasKudos: viewerHas[id] ?? false,
          commentCount: commentCount[id] ?? 0,
        ),
    };
  }

  // ──────────────────── Comments on runs ────────────────────

  /// Comments on a run, sorted oldest-first. Capped at `limit` rows
  /// (default 200) — promote to cursor pagination if a viral run
  /// regularly hits the cap.
  Future<List<RunCommentRow>> fetchRunComments(
    String runId, {
    int limit = 200,
  }) async {
    final data = await _client
        .from(RunCommentRow.table)
        .select()
        .eq(RunCommentRow.colRunId, runId)
        .order(RunCommentRow.colCreatedAt, ascending: true)
        .limit(limit);
    return data
        .map<RunCommentRow>((row) => RunCommentRow.fromJson(row))
        .toList();
  }

  /// Post a comment on a run. `parentCommentId` is set for replies
  /// (one-level deep — the INSERT policy rejects deeper nesting via
  /// the `_run_comment_parent_is_top_level` helper).
  Future<RunCommentRow> addRunComment({
    required String runId,
    required String body,
    String? parentCommentId,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(RunCommentRow.table)
        .insert({
          RunCommentRow.colRunId: runId,
          RunCommentRow.colAuthorId: viewerId,
          RunCommentRow.colBody: body,
          if (parentCommentId != null)
            RunCommentRow.colParentCommentId: parentCommentId,
        })
        .select()
        .single();
    return RunCommentRow.fromJson(inserted);
  }

  /// Edit your own comment body. The `run_comments_set_updated_at`
  /// trigger keeps `updated_at` honest so consumers can tell edited
  /// comments apart.
  Future<void> editRunComment({
    required String commentId,
    required String body,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(RunCommentRow.table)
        .update({RunCommentRow.colBody: body})
        .eq(RunCommentRow.colId, commentId)
        .eq(RunCommentRow.colAuthorId, viewerId);
  }

  /// Delete a comment. The author can always delete their own; the
  /// run owner can delete any comment on their run (separate DELETE
  /// policy). RLS enforces the rest.
  Future<void> deleteRunComment(String commentId) async {
    await _client
        .from(RunCommentRow.table)
        .delete()
        .eq(RunCommentRow.colId, commentId);
  }

  // ──────────────────── Notifications inbox ────────────────────

  /// The viewer's notifications, newest-first. Capped at `limit`.
  Future<List<NotificationRow>> fetchNotifications({int limit = 100}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final data = await _client
        .from(NotificationRow.table)
        .select()
        .eq(NotificationRow.colUserId, viewerId)
        .order(NotificationRow.colCreatedAt, ascending: false)
        .limit(limit);
    return data
        .map<NotificationRow>((row) => NotificationRow.fromJson(row))
        .toList();
  }

  /// Unread count for the bell badge. Hot read-path so we use
  /// `count: 'exact', head: true` against the partial index
  /// `notifications_user_unread`.
  Future<int> fetchUnreadNotificationCount() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return 0;
    return _client
        .from(NotificationRow.table)
        .count(CountOption.exact)
        .eq(NotificationRow.colUserId, viewerId)
        .isFilter(NotificationRow.colReadAt, null);
  }

  /// Mark one notification read. Optimistic-write friendly — the
  /// bell decrements its badge before this fires.
  Future<void> markNotificationRead(String id) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(NotificationRow.table)
        .update({NotificationRow.colReadAt: DateTime.now().toIso8601String()})
        .eq(NotificationRow.colId, id)
        .eq(NotificationRow.colUserId, viewerId)
        .isFilter(NotificationRow.colReadAt, null);
  }

  /// Bulk mark-all-read for the viewer's unread inbox.
  Future<void> markAllNotificationsRead() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(NotificationRow.table)
        .update({NotificationRow.colReadAt: DateTime.now().toIso8601String()})
        .eq(NotificationRow.colUserId, viewerId)
        .isFilter(NotificationRow.colReadAt, null);
  }

  /// Per-row dismiss.
  Future<void> deleteNotification(String id) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(NotificationRow.table)
        .delete()
        .eq(NotificationRow.colId, id)
        .eq(NotificationRow.colUserId, viewerId);
  }

  // ──────────────────── Run photos (P1.B) ────────────────────
  //
  // Metadata in `run_photos`; bytes in the private `run-photos`
  // Storage bucket at `{owner_id}/{photo_id}.{ext}` (bucket flipped
  // from public to private in 20260712_001 to close the CDN bypass
  // around the visibility gate). Owner gates upload + delete; the
  // Storage SELECT policy joins through `run_photos.storage_path` →
  // `is_run_visible_to(rp.run_id, auth.uid())` so a flip from public
  // to private on the parent run propagates within signed-URL TTL.

  /// Photos for a run, ordered by position then created_at. Capped.
  Future<List<RunPhotoRow>> fetchRunPhotos(
    String runId, {
    int limit = 50,
  }) async {
    final data = await _client
        .from(RunPhotoRow.table)
        .select()
        .eq(RunPhotoRow.colRunId, runId)
        .order(RunPhotoRow.colPositionIdx, ascending: true)
        .order(RunPhotoRow.colCreatedAt, ascending: true)
        .limit(limit);
    return data.map<RunPhotoRow>((r) => RunPhotoRow.fromJson(r)).toList();
  }

  /// Upload bytes to the `run-photos` bucket and insert the metadata
  /// row. The caller passes the storage extension (e.g. 'jpg', 'png').
  /// Trim a caption and collapse whitespace-only / empty to null.
  /// Mirrors web's `input.caption?.trim() || null` so captions stored
  /// from either platform read back identically. Lifted to a static
  /// so the contract can be unit-tested in isolation.
  @visibleForTesting
  static String? normaliseRunPhotoCaption(String? caption) {
    final t = caption?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<RunPhotoRow> addRunPhoto({
    required String runId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    String? caption,
    int positionIdx = 0,
    // When set, the photo joins the event's multi-attendee gallery (#49).
    // The DB INSERT policy requires the uploader can see the event.
    String? eventId,
    DateTime? eventInstanceStart,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final id = _client.auth.currentUser!.id;
    // Storage layout matches web: `{owner_id}/{photo_id}.{ext}`. The
    // photo_id is a fresh uuid generated server-side, so we let the
    // insert return it and *then* upload — keeps the storage path
    // and the row in lockstep without a follow-up update.
    final inserted = await _client
        .from(RunPhotoRow.table)
        .insert({
          RunPhotoRow.colRunId: runId,
          RunPhotoRow.colOwnerId: viewerId,
          RunPhotoRow.colStoragePath: '', // placeholder; updated below
          RunPhotoRow.colCaption: normaliseRunPhotoCaption(caption),
          RunPhotoRow.colPositionIdx: positionIdx,
          RunPhotoRow.colEventId: eventId,
          RunPhotoRow.colEventInstanceStart:
              eventInstanceStart?.toIso8601String(),
        })
        .select()
        .single();
    final photoId = inserted[RunPhotoRow.colId] as String;
    final path = '$id/$photoId.$extension';
    await _client.storage.from(StorageBuckets.runPhotos).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    await _client
        .from(RunPhotoRow.table)
        .update({RunPhotoRow.colStoragePath: path})
        .eq(RunPhotoRow.colId, photoId);
    return RunPhotoRow.fromJson({...inserted, RunPhotoRow.colStoragePath: path});
  }

  /// Update an existing photo's caption. Caption is normalised
  /// (trim → empty becomes null) to match web's contract — a
  /// whitespace-only edit clears the caption rather than leaving an
  /// empty-looking-but-non-null row that breaks `IS NOT NULL`
  /// queries.
  Future<void> updateRunPhotoCaption({
    required String photoId,
    String? caption,
  }) async {
    await _client
        .from(RunPhotoRow.table)
        .update({RunPhotoRow.colCaption: normaliseRunPhotoCaption(caption)})
        .eq(RunPhotoRow.colId, photoId);
  }

  /// Delete a photo. Removes both the metadata row (RLS gates author
  /// / run-owner permissions) and the underlying Storage objects —
  /// the original upload AND the worker-generated 512-wide thumbnail.
  /// Audit/storage Medium fix: the prior shape removed only
  /// `storage_path`, leaving thumbnails orphaned in the bucket.
  Future<void> deleteRunPhoto(RunPhotoRow photo) async {
    await _client
        .from(RunPhotoRow.table)
        .delete()
        .eq(RunPhotoRow.colId, photo.id);
    final paths = <String>[];
    if (photo.storagePath.isNotEmpty) paths.add(photo.storagePath);
    final thumb = photo.thumb512Path;
    if (thumb != null && thumb.isNotEmpty) paths.add(thumb);
    if (paths.isNotEmpty) {
      await _client.storage.from(StorageBuckets.runPhotos).remove(paths);
    }
  }

  /// Event gallery (#49): every photo tagged to this event instance,
  /// across all attendees' runs. RLS lets anyone who can see the event
  /// read these even when the underlying run is private. `run_id` is NOT
  /// selected so a private run's UUID can't leak to an event viewer who
  /// can't see that run — mirrors web `fetchEventPhotos`. Uploader names
  /// come from a second batched query (the run→profile join isn't
  /// expressible when the run may be invisible to the viewer). Returns []
  /// on error (L4 — the gallery is auxiliary to the event detail).
  Future<List<EventPhotoView>> fetchEventPhotos(
    String eventId,
    DateTime instanceStart, {
    int limit = 100,
  }) async {
    try {
      final rows = await _client
          .from(RunPhotoRow.table)
          .select(
            'id, owner_id, storage_path, thumb_512_path, caption, '
            'position_idx, created_at, event_id, event_instance_start',
          )
          .eq(RunPhotoRow.colEventId, eventId)
          .eq(RunPhotoRow.colEventInstanceStart, instanceStart.toIso8601String())
          .order(RunPhotoRow.colCreatedAt, ascending: true)
          .limit(limit);
      if (rows.isEmpty) return const [];
      final ownerIds = <String>{
        for (final r in rows) r['owner_id'] as String,
      }.toList();
      final profiles = await _client
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', ownerIds);
      final nameById = <String, String?>{
        for (final p in profiles)
          p['id'] as String: p['display_name'] as String?,
      };
      return [
        for (final r in rows)
          EventPhotoView.fromJson(r, nameById[r['owner_id'] as String]),
      ];
    } catch (e) {
      debugPrint('fetchEventPhotos failed: $e');
      return const [];
    }
  }

  // ──────────────────── Route photos (backlog C1) ────────────────────
  //
  // The run_photos capability applied to routes. Metadata in
  // `route_photos`; bytes in the private `route-photos` Storage bucket at
  // `{owner_id}/{photo_id}.{ext}`. Owner gates upload + delete; the
  // Storage SELECT policy joins through `route_photos.storage_path` →
  // `private.is_route_visible_to(rp.route_id, auth.uid())` so a route flip
  // from public to private propagates within signed-URL TTL.

  /// Photos for a route, ordered by position then created_at. Capped.
  Future<List<RoutePhotoRow>> fetchRoutePhotos(
    String routeId, {
    int limit = 50,
  }) async {
    final data = await _client
        .from(RoutePhotoRow.table)
        .select()
        .eq(RoutePhotoRow.colRouteId, routeId)
        .order(RoutePhotoRow.colPositionIdx, ascending: true)
        .order(RoutePhotoRow.colCreatedAt, ascending: true)
        .limit(limit);
    return data.map<RoutePhotoRow>((r) => RoutePhotoRow.fromJson(r)).toList();
  }

  /// Trim a caption and collapse whitespace-only / empty to null, matching
  /// web's `input.caption?.trim() || null` so captions stored from either
  /// platform read back identically.
  @visibleForTesting
  static String? normaliseRoutePhotoCaption(String? caption) {
    final t = caption?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<RoutePhotoRow> addRoutePhoto({
    required String routeId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    String? caption,
    int positionIdx = 0,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final id = _client.auth.currentUser!.id;
    final inserted = await _client
        .from(RoutePhotoRow.table)
        .insert({
          RoutePhotoRow.colRouteId: routeId,
          RoutePhotoRow.colOwnerId: viewerId,
          RoutePhotoRow.colStoragePath: '', // placeholder; updated below
          RoutePhotoRow.colCaption: normaliseRoutePhotoCaption(caption),
          RoutePhotoRow.colPositionIdx: positionIdx,
        })
        .select()
        .single();
    final photoId = inserted[RoutePhotoRow.colId] as String;
    final path = '$id/$photoId.$extension';
    await _client.storage.from(StorageBuckets.routePhotos).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    await _client
        .from(RoutePhotoRow.table)
        .update({RoutePhotoRow.colStoragePath: path})
        .eq(RoutePhotoRow.colId, photoId);
    return RoutePhotoRow.fromJson(
        {...inserted, RoutePhotoRow.colStoragePath: path});
  }

  Future<void> updateRoutePhotoCaption({
    required String photoId,
    String? caption,
  }) async {
    await _client
        .from(RoutePhotoRow.table)
        .update({RoutePhotoRow.colCaption: normaliseRoutePhotoCaption(caption)})
        .eq(RoutePhotoRow.colId, photoId);
  }

  /// Delete a photo. Removes the metadata row (RLS gates owner / route-owner
  /// permissions) and the underlying Storage objects — the original upload
  /// AND the worker-generated 512-wide thumbnail.
  Future<void> deleteRoutePhoto(RoutePhotoRow photo) async {
    await _client
        .from(RoutePhotoRow.table)
        .delete()
        .eq(RoutePhotoRow.colId, photo.id);
    final paths = <String>[];
    if (photo.storagePath.isNotEmpty) paths.add(photo.storagePath);
    final thumb = photo.thumb512Path;
    if (thumb != null && thumb.isNotEmpty) paths.add(thumb);
    if (paths.isNotEmpty) {
      await _client.storage.from(StorageBuckets.routePhotos).remove(paths);
    }
  }

  // ──────────────────── Club photos (gallery) ────────────────────
  //
  // The route_photos shape re-keyed to club membership (migration
  // 20270301_001). Metadata in `club_photos`; bytes in the private
  // `club-photos` Storage bucket at `{owner_id}/{photo_id}.{ext}`. Any
  // active member uploads; a photo's owner OR a club admin deletes; the
  // Storage SELECT policy joins through `club_photos` → club visibility so
  // a private club's gallery is members-only and a public club's is open.

  /// Photos for a club, ordered by position then created_at. Capped.
  Future<List<ClubPhotoRow>> fetchClubPhotos(
    String clubId, {
    int limit = 50,
  }) async {
    final data = await _client
        .from(ClubPhotoRow.table)
        .select()
        .eq(ClubPhotoRow.colClubId, clubId)
        .order(ClubPhotoRow.colPositionIdx, ascending: true)
        .order(ClubPhotoRow.colCreatedAt, ascending: true)
        .limit(limit);
    return data.map<ClubPhotoRow>((r) => ClubPhotoRow.fromJson(r)).toList();
  }

  Future<ClubPhotoRow> addClubPhoto({
    required String clubId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    String? caption,
    int positionIdx = 0,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(ClubPhotoRow.table)
        .insert({
          ClubPhotoRow.colClubId: clubId,
          ClubPhotoRow.colOwnerId: viewerId,
          ClubPhotoRow.colStoragePath: '', // placeholder; updated below
          ClubPhotoRow.colCaption: normaliseRoutePhotoCaption(caption),
          ClubPhotoRow.colPositionIdx: positionIdx,
        })
        .select()
        .single();
    final photoId = inserted[ClubPhotoRow.colId] as String;
    final path = '$viewerId/$photoId.$extension';
    await _client.storage.from(StorageBuckets.clubPhotos).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    await _client
        .from(ClubPhotoRow.table)
        .update({ClubPhotoRow.colStoragePath: path})
        .eq(ClubPhotoRow.colId, photoId);
    return ClubPhotoRow.fromJson(
        {...inserted, ClubPhotoRow.colStoragePath: path});
  }

  Future<void> updateClubPhotoCaption({
    required String photoId,
    String? caption,
  }) async {
    await _client
        .from(ClubPhotoRow.table)
        .update({ClubPhotoRow.colCaption: normaliseRoutePhotoCaption(caption)})
        .eq(ClubPhotoRow.colId, photoId);
  }

  /// Delete a photo. Removes the metadata row (RLS gates owner / club-admin
  /// permissions) and the underlying Storage objects — the original upload
  /// AND the worker-generated 512-wide thumbnail.
  Future<void> deleteClubPhoto(ClubPhotoRow photo) async {
    await _client
        .from(ClubPhotoRow.table)
        .delete()
        .eq(ClubPhotoRow.colId, photo.id);
    final paths = <String>[];
    if (photo.storagePath.isNotEmpty) paths.add(photo.storagePath);
    final thumb = photo.thumb512Path;
    if (thumb != null && thumb.isNotEmpty) paths.add(thumb);
    if (paths.isNotEmpty) {
      await _client.storage.from(StorageBuckets.clubPhotos).remove(paths);
    }
  }

  // ──────────────────── Segments (P1.B) ────────────────────
  //
  // Route-anchored segments + per-run efforts. Auto-effort generation
  // is client-side on web (decisions §37); the android equivalent
  // walks the run track in `core_models`/segments and posts efforts
  // through `recordSegmentEffort` below.

  // ─────────────────── Gear tracking (decisions backlog #7) ───────────────────

  /// Fetch every gear item the signed-in user owns plus its rolled-up
  /// total distance. Reads through `gear_with_distance` (a view that
  /// joins `gear` with the runs assigned via `run_gear`); RLS on the
  /// underlying tables keeps the view scoped to the caller. Returns
  /// rows decoded as Maps because the view doesn't have a generated
  /// row class — the consumer (settings_screen.dart's gear list) is
  /// the only reader today.
  Future<List<Map<String, dynamic>>> fetchMyGearWithDistance() async {
    final data = await _client
        .from('gear_with_distance')
        .select()
        .order('retired_at', ascending: true, nullsFirst: true)
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Insert a new gear row and return the persisted shape.
  ///
  /// When [id] is supplied (offline-create path), the client mints a v4
  /// UUID, persists it to [LocalGearStore], then replays the INSERT on
  /// the same id once online. The id column on `gear` defaults to
  /// `gen_random_uuid()` but accepts client-minted values — no temp-id
  /// reconciliation needed since the local id IS the server id.
  Future<GearRow> createGear({
    required String kind,
    required String name,
    String? id,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    int? targetDistanceM,
    String? notes,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final row = await _client
        .from(GearRow.table)
        .insert({
          if (id != null) GearRow.colId: id,
          GearRow.colOwnerId: viewerId,
          GearRow.colKind: kind,
          GearRow.colName: name,
          GearRow.colBrand: brand,
          GearRow.colModel: model,
          GearRow.colPurchasedAt:
              purchasedAt?.toIso8601String().substring(0, 10),
          GearRow.colTargetDistanceM: targetDistanceM,
          GearRow.colNotes: notes,
        })
        .select()
        .single();
    return GearRow.fromJson(row);
  }

  /// Patch any subset of the editable fields. The `updated_at` column
  /// is bumped by a trigger so the caller doesn't pass it.
  Future<void> updateGear(
    String id, {
    String? name,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    DateTime? retiredAt,
    bool clearRetiredAt = false,
    int? targetDistanceM,
    String? notes,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch[GearRow.colName] = name;
    if (brand != null) patch[GearRow.colBrand] = brand;
    if (model != null) patch[GearRow.colModel] = model;
    if (purchasedAt != null) {
      patch[GearRow.colPurchasedAt] =
          purchasedAt.toIso8601String().substring(0, 10);
    }
    if (clearRetiredAt) {
      patch[GearRow.colRetiredAt] = null;
    } else if (retiredAt != null) {
      patch[GearRow.colRetiredAt] =
          retiredAt.toIso8601String().substring(0, 10);
    }
    if (targetDistanceM != null) {
      patch[GearRow.colTargetDistanceM] = targetDistanceM;
    }
    if (notes != null) patch[GearRow.colNotes] = notes;
    if (patch.isEmpty) return;
    await _client.from(GearRow.table).update(patch).eq(GearRow.colId, id);
  }

  /// Mark a gear item retired (cosmetic only — the row stays for
  /// historical mileage roll-ups on past runs). Same shape as the
  /// web's `retireGear`.
  Future<void> retireGear(String id) async {
    await updateGear(id, retiredAt: DateTime.now());
  }

  /// Restore an actively-tracked piece of gear without touching
  /// anything else. Mirrors the web's `unretireGear`.
  Future<void> unretireGear(String id) async {
    await updateGear(id, clearRetiredAt: true);
  }

  /// Hard-delete a gear row (cascades to `run_gear` rows pointing at
  /// it). Surface this only behind a confirm dialog — historical
  /// mileage on past runs drops with the cascade.
  Future<void> deleteGear(String id) async {
    await _client.from(GearRow.table).delete().eq(GearRow.colId, id);
  }

  /// Fetch a gear item's wear log (per-shoe wear-pattern observations),
  /// newest observation first. Owner-scoped by RLS — never another
  /// user's notes. Mirrors the web's `fetchGearWearLogs`.
  Future<List<GearWearLogRow>> fetchGearWearLogs(String gearId) async {
    final data = await _client
        .from(GearWearLogRow.table)
        .select()
        .eq(GearWearLogRow.colGearId, gearId)
        .order(GearWearLogRow.colLoggedOn, ascending: false)
        .order(GearWearLogRow.colCreatedAt, ascending: false);
    return (data as List)
        .map<GearWearLogRow>(
            (r) => GearWearLogRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Log a wear observation against a gear item. RLS gates the insert to
  /// the gear owner. [loggedOn] defaults to the DB's `current_date` when
  /// null. [area] is one of outsole / midsole / upper / other, or null.
  /// Mirrors the web's `addGearWearLog`.
  Future<GearWearLogRow> addGearWearLog({
    required String gearId,
    required String note,
    String? area,
    DateTime? loggedOn,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final row = await _client
        .from(GearWearLogRow.table)
        .insert({
          GearWearLogRow.colGearId: gearId,
          GearWearLogRow.colOwnerId: viewerId,
          GearWearLogRow.colNote: note,
          GearWearLogRow.colArea: area,
          if (loggedOn != null)
            GearWearLogRow.colLoggedOn:
                loggedOn.toIso8601String().substring(0, 10),
        })
        .select()
        .single();
    return GearWearLogRow.fromJson(row);
  }

  /// Delete a single wear observation. RLS scopes to the owner.
  Future<void> deleteGearWearLog(String id) async {
    await _client
        .from(GearWearLogRow.table)
        .delete()
        .eq(GearWearLogRow.colId, id);
  }

  // ─────────────────── Gear rotations (roadmap §7) ───────────────────

  /// Fetch every rotation the signed-in user owns, each paired with the
  /// gear ids it contains. Two owner-scoped reads (rotations + the join)
  /// stitched client-side — both are tiny. Mirrors the web's
  /// `fetchMyGearRotations`. Rotations sit OUTSIDE [LocalGearStore]
  /// (online-only, like the wear-log + backfill sub-flows) — a rotation
  /// is inventory organisation, not a record that must survive offline.
  Future<List<GearRotationWithMembers>> fetchMyGearRotations() async {
    final rotations = await _client
        .from(GearRotationRow.table)
        .select()
        .order(GearRotationRow.colName, ascending: true);
    final members = await _client
        .from(GearRotationMemberRow.table)
        .select(
            '${GearRotationMemberRow.colRotationId}, ${GearRotationMemberRow.colGearId}');
    final byRotation = <String, List<String>>{};
    for (final m in (members as List)) {
      final map = m as Map<String, dynamic>;
      final rid = map[GearRotationMemberRow.colRotationId] as String;
      (byRotation[rid] ??= <String>[])
          .add(map[GearRotationMemberRow.colGearId] as String);
    }
    return (rotations as List).map<GearRotationWithMembers>((r) {
      final row = GearRotationRow.fromJson(r as Map<String, dynamic>);
      return GearRotationWithMembers(
        rotation: row,
        gearIds: byRotation[row.id] ?? const <String>[],
      );
    }).toList();
  }

  /// Create a named rotation. Mirrors the web's `createGearRotation`.
  Future<GearRotationRow> createGearRotation(String name) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final row = await _client
        .from(GearRotationRow.table)
        .insert({
          GearRotationRow.colOwnerId: viewerId,
          GearRotationRow.colName: name,
        })
        .select()
        .single();
    return GearRotationRow.fromJson(row);
  }

  /// Rename a rotation. RLS scopes to the owner.
  Future<void> renameGearRotation(String id, String name) async {
    await _client
        .from(GearRotationRow.table)
        .update({GearRotationRow.colName: name}).eq(GearRotationRow.colId, id);
  }

  /// Delete a rotation. Membership rows cascade via the FK; the gear
  /// itself is untouched. Mirrors the web's `deleteGearRotation`.
  Future<void> deleteGearRotation(String id) async {
    await _client
        .from(GearRotationRow.table)
        .delete()
        .eq(GearRotationRow.colId, id);
  }

  /// Replace the full gear set assigned to a rotation. Delete-then-insert,
  /// mirroring [setRunGear]. RLS gates both halves to the rotation + gear
  /// owner. Mirrors the web's `setGearRotationMembers`.
  Future<void> setGearRotationMembers(
      String rotationId, List<String> gearIds) async {
    await _client
        .from(GearRotationMemberRow.table)
        .delete()
        .eq(GearRotationMemberRow.colRotationId, rotationId);
    if (gearIds.isEmpty) return;
    final rows = gearIds
        .map((g) => {
              GearRotationMemberRow.colRotationId: rotationId,
              GearRotationMemberRow.colGearId: g,
            })
        .toList();
    await _client.from(GearRotationMemberRow.table).insert(rows);
  }

  /// Replace the full gear set assigned to a run. Empty list clears
  /// the assignment. RLS gates both the delete and the insert to the
  /// run + gear owner; a non-owner gets a 42501 PostgREST error.
  /// Mirrors the web's `setRunGear` byte-for-byte (delete-then-insert
  /// over a smarter diff — the join table is tiny per run).
  Future<void> setRunGear(String runId, List<String> gearIds) async {
    await _client
        .from(RunGearRow.table)
        .delete()
        .eq(RunGearRow.colRunId, runId);
    if (gearIds.isEmpty) return;
    final rows = gearIds
        .map((g) => {RunGearRow.colRunId: runId, RunGearRow.colGearId: g})
        .toList();
    await _client.from(RunGearRow.table).insert(rows);
  }

  /// Attach a single piece of gear to many runs at once. Used by the
  /// post-create gear-backfill flow: the user adds shoes they've been
  /// running in for a week, the app proposes the runs since the
  /// purchase date, the user confirms, and this call lands the
  /// `run_gear` rows.
  ///
  /// Duplicates are tolerated — if the user previously attached this
  /// gear to one of the rows by hand, `upsert` with `ignoreDuplicates`
  /// silently skips it. RLS gates the writes to (owner-of-run,
  /// owner-of-gear) so a passing run-id you don't own fails the whole
  /// batch with a 42501 PostgREST error.
  Future<int> addGearToRuns(String gearId, List<String> runIds) async {
    if (runIds.isEmpty) return 0;
    final rows = runIds
        .map((rid) => <String, dynamic>{
              RunGearRow.colRunId: rid,
              RunGearRow.colGearId: gearId,
            })
        .toList();
    await _client.from(RunGearRow.table).upsert(
          rows,
          onConflict: '${RunGearRow.colRunId},${RunGearRow.colGearId}',
          ignoreDuplicates: true,
        );
    return rows.length;
  }

  /// Fetch the gear assigned to a single run. Goes through the
  /// `public_run_gear` SECURITY DEFINER RPC (migration 20261126_001) — the
  /// same path the web `fetchRunGear` uses — NOT a `run_gear -> gear` join.
  /// The `gear` SELECT policy is owner-only, so a join returns NULL gear rows
  /// for any non-owner (the chip would never render on a shared/public run);
  /// the RPC gates on `is_run_visible_to` and projects ONLY the public columns
  /// (id / kind / name / brand / model), so it's leak-free even for a public
  /// run. Drives the gear chip on run-detail screens (decisions §116).
  ///
  /// The non-projected `GearRow` fields (ownerId / dates / isDefault / notes /
  /// target / retired) are owner-private and deliberately absent from the RPC;
  /// they're filled with placeholders here and are NEVER read on the chip path
  /// (run_gear_chips reads only id / kind / name). For the owner's editable
  /// inventory use [fetchMyGear], which returns full rows via the owner policy.
  Future<List<GearRow>> fetchRunGear(String runId) async {
    final data = await _client.rpc('public_run_gear', params: {'p_run_id': runId});
    final rows = (data as List).cast<Map<String, dynamic>>();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return rows
        .map<GearRow>((g) => GearRow(
              id: g['id'] as String,
              ownerId: '',
              kind: g['kind'] as String,
              name: g['name'] as String,
              brand: g['brand'] as String?,
              model: g['model'] as String?,
              createdAt: epoch,
              updatedAt: epoch,
              isDefault: false,
            ))
        .toList();
  }

  /// Segments anchored on a route, sorted by start distance.
  Future<List<SegmentRow>> fetchSegmentsForRoute(
    String routeId, {
    int limit = 100,
  }) async {
    final data = await _client
        .from(SegmentRow.table)
        .select()
        .eq(SegmentRow.colRouteId, routeId)
        .order(SegmentRow.colStartDistanceM, ascending: true)
        .limit(limit);
    return data.map<SegmentRow>((r) => SegmentRow.fromJson(r)).toList();
  }

  /// Define a new segment on a route. The DB computes `length_m` as
  /// a generated column, so we don't pass it.
  /// Create a route segment. Mirrors `apps/web/src/lib/data.ts:createSegment`:
  /// `name` is trimmed at the API layer so any future non-UI caller
  /// (bulk import, automation) can't write whitespace into the DB.
  Future<SegmentRow> createSegment({
    required String routeId,
    required String name,
    required double startDistanceM,
    required double endDistanceM,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(SegmentRow.table)
        .insert({
          SegmentRow.colRouteId: routeId,
          SegmentRow.colName: name.trim(),
          SegmentRow.colStartDistanceM: startDistanceM,
          SegmentRow.colEndDistanceM: endDistanceM,
          SegmentRow.colAuthorId: viewerId,
        })
        .select()
        .single();
    return SegmentRow.fromJson(inserted);
  }

  // ──────────────────── parkrun import ────────────────────

  /// Persist the user's parkrun athlete number on their `user_profiles`
  /// row (matches web). The Edge Function reads this field if no
  /// override is passed; we still pass it explicitly on import.
  Future<void> setParkrunAthleteNumber(String? athleteNumber) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(UserProfileRow.table)
        .update({UserProfileRow.colParkrunNumber: athleteNumber})
        .eq(UserProfileRow.colId, viewerId);
  }

  /// Trigger the `parkrun-import` Edge Function. Returns the count of
  /// new results inserted.
  Future<int> importParkrunResults(String athleteNumber) async {
    final res = await _client.functions.invoke(
      'parkrun-import',
      body: {'athleteNumber': athleteNumber.trim()},
    );
    if (res.status >= 400) {
      final err = res.data is Map<String, dynamic>
          ? res.data['error'] as String?
          : null;
      throw Exception(err ?? 'parkrun-import failed (HTTP ${res.status})');
    }
    final data = res.data;
    if (data is Map<String, dynamic> && data['imported'] is num) {
      return (data['imported'] as num).toInt();
    }
    return 0;
  }

  // ──────────────────── Device list (user_device_settings) ─────────

  /// Every device row the current user has registered. Used by the
  /// Settings → Devices screen to show "where am I signed in".
  Future<List<UserDeviceSettingRow>> fetchMyDevices() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final rows = await _client
        .from(UserDeviceSettingRow.table)
        .select()
        .eq(UserDeviceSettingRow.colUserId, viewerId)
        .order(UserDeviceSettingRow.colLastSeenAt, ascending: false);
    return rows
        .map<UserDeviceSettingRow>(
            (r) => UserDeviceSettingRow.fromJson(r))
        .toList();
  }

  /// Rename a device (the human-readable label shown in Settings).
  Future<void> updateDeviceLabel({
    required String deviceId,
    required String label,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(UserDeviceSettingRow.table)
        .update({UserDeviceSettingRow.colLabel: label})
        .eq(UserDeviceSettingRow.colUserId, viewerId)
        .eq(UserDeviceSettingRow.colDeviceId, deviceId);
  }

  /// Drop a device row (and any per-device prefs it carried). The
  /// device itself isn't signed out — that's a sign-out flow on the
  /// device. This only forgets the per-device preference overrides.
  Future<void> removeDevice(String deviceId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(UserDeviceSettingRow.table)
        .delete()
        .eq(UserDeviceSettingRow.colUserId, viewerId)
        .eq(UserDeviceSettingRow.colDeviceId, deviceId);
  }

  /// Patch a single key in a non-current device's `prefs` bag. Use the
  /// `SettingsService` for the *current* device; this method is the
  /// override-editor write-path on the Settings → Devices screen.
  Future<void> setDeviceOverride({
    required String deviceId,
    required String key,
    required dynamic value,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final row = await _client
        .from(UserDeviceSettingRow.table)
        .select(UserDeviceSettingRow.colPrefs)
        .eq(UserDeviceSettingRow.colUserId, viewerId)
        .eq(UserDeviceSettingRow.colDeviceId, deviceId)
        .maybeSingle();
    final prefs = Map<String, dynamic>.from(
        (row?[UserDeviceSettingRow.colPrefs] as Map?) ?? const <String, dynamic>{});
    if (value == null) {
      prefs.remove(key);
    } else {
      prefs[key] = value;
    }
    await _client
        .from(UserDeviceSettingRow.table)
        .update({
          UserDeviceSettingRow.colPrefs: prefs,
          UserDeviceSettingRow.colUpdatedAt:
              DateTime.now().toUtc().toIso8601String(),
        })
        .eq(UserDeviceSettingRow.colUserId, viewerId)
        .eq(UserDeviceSettingRow.colDeviceId, deviceId);
  }

  // ──────────────────── Push device tokens (device_tokens) ─────────
  //
  // The FCM/APNs registration the native-push channel fans out over
  // (migration 20260506_001 + the native_push channel 20270212_001). The
  // mobile push bridge registers a token on sign-in and on rotation, mirrors
  // the per-device opt-in flag from the push_notifications pref, and removes
  // the token on sign-out so the next user on the device doesn't inherit
  // pushes. The worker reads enabled tokens and prunes dead ones.

  /// Register (or refresh) this device's push token. Upsert on
  /// `(user_id, token)` so a re-register with the same token is a no-op
  /// beyond bumping `last_seen_at` / `app_version` / `locale`. Called by the
  /// push bridge on sign-in and on `onTokenRefresh`.
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
    String? appVersion,
    String? locale,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(DeviceTokenRow.table).upsert(
      {
        DeviceTokenRow.colUserId: viewerId,
        DeviceTokenRow.colPlatform: platform,
        DeviceTokenRow.colToken: token,
        DeviceTokenRow.colAppVersion: appVersion,
        DeviceTokenRow.colLocale: locale,
        DeviceTokenRow.colLastSeenAt:
            DateTime.now().toUtc().toIso8601String(),
      },
      onConflict:
          '${DeviceTokenRow.colUserId},${DeviceTokenRow.colToken}',
    );
  }

  /// Flip this device's push opt-in flag. Tracks the `push_notifications`
  /// preference so the worker's per-device fan-out filter
  /// (`is_notifications_enabled`) matches what the user toggled — the token
  /// row stays so a later opt-in doesn't require re-registering with the
  /// platform.
  Future<void> setDeviceNotificationsEnabled({
    required String token,
    required bool enabled,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(DeviceTokenRow.table)
        .update({DeviceTokenRow.colIsNotificationsEnabled: enabled})
        .eq(DeviceTokenRow.colUserId, viewerId)
        .eq(DeviceTokenRow.colToken, token);
  }

  /// Forget this device's push token (sign-out). Removes only the current
  /// token so the next account on the device starts clean — matches the
  /// device-changed-hands semantics in the `device_tokens` DDL.
  Future<void> removeDeviceToken(String token) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(DeviceTokenRow.table)
        .delete()
        .eq(DeviceTokenRow.colUserId, viewerId)
        .eq(DeviceTokenRow.colToken, token);
  }

  /// Routes owned by a club. Read-gated by RLS to club members; used
  /// by the club home Routes tab and event-editor route pickers.
  Future<List<Route>> fetchClubRoutes(String clubId) async {
    final rows = await _client
        .from(RouteRow.table)
        .select()
        .eq(RouteRow.colClubId, clubId)
        .order(RouteRow.colCreatedAt, ascending: false);
    return rows
        .map<Route>((r) => _routeFromRow(r))
        .toList();
  }

  /// Transfer a route the viewer owns to a club they admin (or detach
  /// it back to personal by passing `null`). Admin-write-gated by RLS.
  Future<void> setRouteClub({
    required String routeId,
    required String? clubId,
  }) async {
    await _client
        .from(RouteRow.table)
        .update({RouteRow.colClubId: clubId})
        .eq(RouteRow.colId, routeId);
  }

  // ──────────────────── Saved (bookmarked) routes ────────────────────

  /// Bookmark a public route via the `saved_routes` reference table
  /// (decisions §30 — never clone the row). Idempotent against the
  /// composite-PK; duplicates resolve as a no-op.
  Future<void> bookmarkRoute(String routeId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    try {
      await _client.from(SavedRouteRow.table).insert({
        SavedRouteRow.colUserId: viewerId,
        SavedRouteRow.colRouteId: routeId,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  }

  /// Drop the bookmark. Idempotent.
  Future<void> unbookmarkRoute(String routeId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client
        .from(SavedRouteRow.table)
        .delete()
        .eq(SavedRouteRow.colUserId, viewerId)
        .eq(SavedRouteRow.colRouteId, routeId);
  }

  /// Whether the current viewer has bookmarked this route.
  Future<bool> isRouteBookmarked(String routeId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return false;
    final row = await _client
        .from(SavedRouteRow.table)
        .select(SavedRouteRow.colRouteId)
        .eq(SavedRouteRow.colUserId, viewerId)
        .eq(SavedRouteRow.colRouteId, routeId)
        .maybeSingle();
    return row != null;
  }

  /// All routes the current viewer has bookmarked, joined to the parent
  /// `routes` row so callers can render full route cards. Sorted by
  /// `saved_at` desc.
  Future<List<Route>> fetchBookmarkedRoutes({int limit = 200}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final rows = await _client
        .from(SavedRouteRow.table)
        .select('saved_at, route:${RouteRow.table}(*)')
        .eq(SavedRouteRow.colUserId, viewerId)
        .order(SavedRouteRow.colSavedAt, ascending: false)
        .limit(limit);
    final out = <Route>[];
    for (final r in rows) {
      final inner = r['route'];
      if (inner is Map<String, dynamic>) {
        out.add(_routeFromRow(inner));
      }
    }
    return out;
  }

  /// Delete a segment. RLS lets the route owner remove segments on
  /// their own route; cascades drop the segment_efforts rows.
  Future<void> deleteSegment(String segmentId) async {
    await _client
        .from(SegmentRow.table)
        .delete()
        .eq(SegmentRow.colId, segmentId);
  }

  /// Leaderboard for a single segment — fastest effort per user
  /// already enforced by `unique(segment_id, run_id)` and the client
  /// further dedupes per user. Capped at `limit` raw rows.
  Future<List<SegmentEffortRow>> fetchSegmentLeaderboard(
    String segmentId, {
    int limit = 200,
  }) async {
    final data = await _client
        .from(SegmentEffortRow.table)
        .select()
        .eq(SegmentEffortRow.colSegmentId, segmentId)
        .order(SegmentEffortRow.colTimeSeconds, ascending: true)
        .limit(limit);
    return data
        .map<SegmentEffortRow>((r) => SegmentEffortRow.fromJson(r))
        .toList();
  }

  /// All segment efforts for a single run (so the run-detail page can
  /// surface "you ranked 3rd on Centennial Hill" pills).
  Future<List<SegmentEffortRow>> fetchEffortsForRun(String runId) async {
    final data = await _client
        .from(SegmentEffortRow.table)
        .select()
        .eq(SegmentEffortRow.colRunId, runId);
    return data
        .map<SegmentEffortRow>((r) => SegmentEffortRow.fromJson(r))
        .toList();
  }

  /// Insert a single segment effort row. Idempotent against the
  /// `unique(segment_id, run_id)` constraint — the upsert with
  /// `ignoreDuplicates: true` swallows reimports of the same run.
  Future<void> recordSegmentEffort({
    required String segmentId,
    required String runId,
    required int timeSeconds,
    required DateTime startedAt,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(SegmentEffortRow.table).upsert(
      {
        SegmentEffortRow.colSegmentId: segmentId,
        SegmentEffortRow.colRunId: runId,
        SegmentEffortRow.colUserId: viewerId,
        SegmentEffortRow.colTimeSeconds: timeSeconds,
        SegmentEffortRow.colStartedAt: startedAt.toIso8601String(),
      },
      onConflict:
          '${SegmentEffortRow.colSegmentId},${SegmentEffortRow.colRunId}',
      ignoreDuplicates: true,
    );
  }

  // ──────────────────── Privacy zones (P1.C) ────────────────────

  /// Server-side privacy-zone clipping. The zones never reach the
  /// client; the RPC reads them with security-definer privileges and
  /// returns the clipped middle of the input track. The RPC is a
  /// no-op (returns the input) when the owner has no zones configured.
  ///
  /// **Fails closed:** on RPC error or unexpected response shape this
  /// returns `[]` rather than the unclipped input. The previous
  /// behaviour (return `points` on error) was the leak this helper
  /// exists to prevent — a transient DB blip that bypassed clipping
  /// was a privacy regression. Callers should guard owner views
  /// *before* calling so an outage doesn't blank the owner's own
  /// map; this function only ever speaks for non-owner viewers.
  Future<List<Map<String, dynamic>>> clipTrackForUser({
    required String targetUserId,
    required List<Map<String, dynamic>> points,
  }) async {
    if (points.isEmpty) return points;
    try {
      final data = await _client.rpc('clip_track_for_user', params: {
        'target_user_id': targetUserId,
        'points': points,
      });
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Server-side privacy-zone-clipped waypoints for a route owned by
  /// someone other than the caller. Routes carry waypoints inline as
  /// a jsonb column (no Storage indirection like runs), so this is a
  /// straight RPC call rather than an Edge Function. The SECURITY
  /// DEFINER function visibility-gates (owner / public / club member)
  /// then returns either unclipped waypoints (owner) or clipped
  /// output (non-owner). Anon callers get public routes only —
  /// private-route reads raise `42501`, which surfaces as a
  /// PostgrestException we swallow into `[]`.
  ///
  /// **Fails closed:** any error or unexpected shape returns `[]`.
  /// Callers that need the unclipped polyline (the owner of the
  /// route) should read `route.waypoints` directly rather than
  /// calling this helper.
  Future<List<Waypoint>> clipRouteForViewer(String routeId) async {
    if (routeId.isEmpty) return const [];
    try {
      final data = await _client.rpc('clip_route_for_viewer', params: {
        'p_route_id': routeId,
      });
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((p) => _waypointFromJson(p.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ──────────────────── Coach messages (P1.C) ────────────────────
  //
  // Active thread is `archived_at IS NULL` filtered by `(user_id,
  // plan_id)`. `plan_id IS NULL` is its own thread. The streaming
  // send path is mounted as a server-only edge function that the
  // android client should hit over fetch/SSE — that's a separate
  // wire concern; the methods below cover the reads + reactions +
  // archiving.

  /// Active-thread messages, oldest-first.
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    var q = _client
        .from(CoachMessageRow.table)
        .select()
        .eq(CoachMessageRow.colUserId, viewerId)
        .isFilter(CoachMessageRow.colArchivedAt, null);
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    final data = await q
        .order(CoachMessageRow.colCreatedAt, ascending: true)
        .limit(500);
    return data
        .map<CoachMessageRow>((r) => CoachMessageRow.fromJson(r))
        .toList();
  }

  /// Set / clear the up/down reaction on an assistant bubble.
  Future<void> setCoachReaction({
    required String messageId,
    String? reaction, // 'up' | 'down' | null to clear
  }) async {
    await _client
        .from(CoachMessageRow.table)
        .update({CoachMessageRow.colReaction: reaction})
        .eq(CoachMessageRow.colId, messageId);
  }

  /// Archive every message in the active thread for the current
  /// `(user_id, plan_id)` scope so a fresh conversation can begin.
  Future<void> archiveCoachThread({String? planId}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    final ts = DateTime.now().toIso8601String();
    var q = _client
        .from(CoachMessageRow.table)
        .update({CoachMessageRow.colArchivedAt: ts})
        .eq(CoachMessageRow.colUserId, viewerId)
        .isFilter(CoachMessageRow.colArchivedAt, null);
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    await q;
  }

  /// Distinct archived_at timestamps (one per archived thread) for
  /// the history sidebar.
  Future<List<DateTime>> listCoachArchives({String? planId}) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    var q = _client
        .from(CoachMessageRow.table)
        .select(CoachMessageRow.colArchivedAt)
        .eq(CoachMessageRow.colUserId, viewerId)
        .not(CoachMessageRow.colArchivedAt, 'is', null);
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    final data = await q.order(CoachMessageRow.colArchivedAt, ascending: false);
    final seen = <String>{};
    final out = <DateTime>[];
    for (final row in data) {
      final raw = row[CoachMessageRow.colArchivedAt] as String?;
      if (raw == null || !seen.add(raw)) continue;
      out.add(DateTime.parse(raw));
    }
    return out;
  }

  /// Fetch a specific archived thread (read-only viewer).
  Future<List<CoachMessageRow>> fetchCoachArchive({
    required DateTime archivedAt,
    String? planId,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    var q = _client
        .from(CoachMessageRow.table)
        .select()
        .eq(CoachMessageRow.colUserId, viewerId)
        .eq(CoachMessageRow.colArchivedAt, archivedAt.toIso8601String());
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    final data =
        await q.order(CoachMessageRow.colCreatedAt, ascending: true);
    return data
        .map<CoachMessageRow>((r) => CoachMessageRow.fromJson(r))
        .toList();
  }

  /// Permanently delete every message in a single archived thread.
  Future<void> deleteCoachArchive({
    required DateTime archivedAt,
    String? planId,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    var q = _client
        .from(CoachMessageRow.table)
        .delete()
        .eq(CoachMessageRow.colUserId, viewerId)
        .eq(CoachMessageRow.colArchivedAt, archivedAt.toIso8601String());
    q = planId == null
        ? q.isFilter(CoachMessageRow.colPlanId, null)
        : q.eq(CoachMessageRow.colPlanId, planId);
    await q;
  }

  /// RPC for the per-user-per-day usage counter. Free tier capped at
  /// 5/day server-side; `is_pro()` lifts the cap.
  Future<int> getCoachUsage() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return 0;
    final value = await _client.rpc(
      'get_coach_usage',
      params: {'p_user_id': viewerId},
    );
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  /// RPC `is_pro` — true when the viewer's active subscription tier
  /// is paid. Used to short-circuit the daily cap and gate Pro UI.
  Future<bool> isPro() async {
    final value = await _client.rpc('is_pro');
    return value == true;
  }

  // ──────────────────── Clubs + events (P1.D) ────────────────────

  /// Create a new club. `joinPolicy` is one of 'open' | 'request' |
  /// 'invite'. The `enroll_club_owner` trigger auto-inserts the
  /// owner's club_members row, so we don't add it here.
  Future<ClubRow> createClub({
    required String name,
    required String slug,
    String? description,
    String? locationLabel,
    bool isPublic = true,
    String joinPolicy = 'open',
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(ClubRow.table)
        .insert({
          ClubRow.colOwnerId: viewerId,
          ClubRow.colName: name,
          ClubRow.colSlug: slug,
          ClubRow.colDescription: description,
          ClubRow.colLocationLabel: locationLabel,
          ClubRow.colIsPublic: isPublic,
          ClubRow.colJoinPolicy: joinPolicy,
        })
        .select(_clubSafeCols)
        .single();
    return ClubRow.fromJson(inserted);
  }

  /// Edit owner-side club fields.
  Future<void> updateClub({
    required String clubId,
    String? name,
    String? description,
    String? locationLabel,
    bool? isPublic,
    String? joinPolicy,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch[ClubRow.colName] = name;
    if (description != null) patch[ClubRow.colDescription] = description;
    if (locationLabel != null) patch[ClubRow.colLocationLabel] = locationLabel;
    if (isPublic != null) patch[ClubRow.colIsPublic] = isPublic;
    if (joinPolicy != null) patch[ClubRow.colJoinPolicy] = joinPolicy;
    if (patch.isEmpty) return;
    await _client.from(ClubRow.table).update(patch).eq(ClubRow.colId, clubId);
  }

  /// Redeem a join token from a public invite link.
  Future<String> joinClubByToken(String token) async {
    final result =
        await _client.rpc('join_club_by_token', params: {'p_token': token});
    return result as String;
  }

  /// Request to join a club whose policy is `request`. Status starts
  /// `pending`; an admin approves via the methods below.
  Future<void> requestJoinClub(String clubId) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(ClubMemberRow.table).insert({
      ClubMemberRow.colClubId: clubId,
      ClubMemberRow.colUserId: viewerId,
      ClubMemberRow.colRole: 'member',
      ClubMemberRow.colStatus: 'pending',
    });
  }

  /// Pending join requests for an admin to action.
  Future<List<ClubMemberRow>> fetchPendingRequests(String clubId) async {
    final data = await _client
        .from(ClubMemberRow.table)
        .select()
        .eq(ClubMemberRow.colClubId, clubId)
        .eq(ClubMemberRow.colStatus, 'pending')
        .order(ClubMemberRow.colJoinedAt, ascending: false);
    return data
        .map<ClubMemberRow>((r) => ClubMemberRow.fromJson(r))
        .toList();
  }

  /// Approve a pending member.
  Future<void> approveJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    await _client
        .from(ClubMemberRow.table)
        .update({ClubMemberRow.colStatus: 'active'})
        .eq(ClubMemberRow.colClubId, clubId)
        .eq(ClubMemberRow.colUserId, userId);
  }

  /// Deny / remove a pending member.
  Future<void> denyJoinRequest({
    required String clubId,
    required String userId,
  }) async {
    await _client
        .from(ClubMemberRow.table)
        .delete()
        .eq(ClubMemberRow.colClubId, clubId)
        .eq(ClubMemberRow.colUserId, userId)
        .eq(ClubMemberRow.colStatus, 'pending');
  }

  /// Create a new event under a club. Recurrence fields are exposed
  /// as raw `recurrence_freq` / `recurrence_byday` strings — the
  /// caller is responsible for the format the backend expects.
  Future<EventRow> createEvent({
    required String clubId,
    required String title,
    required DateTime startsAt,
    String? description,
    int? durationMin,
    String? meetLabel,
    double? meetLat,
    double? meetLng,
    String? routeId,
    double? distanceM,
    int? paceTargetSec,
    int? capacity,
    String? recurrenceFreq,
    String? recurrenceByDay,
    DateTime? recurrenceUntil,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    final inserted = await _client
        .from(EventRow.table)
        .insert({
          EventRow.colClubId: clubId,
          EventRow.colTitle: title,
          EventRow.colDescription: description,
          EventRow.colStartsAt: startsAt.toIso8601String(),
          EventRow.colDurationMin: durationMin,
          EventRow.colMeetLabel: meetLabel,
          EventRow.colMeetLat: meetLat,
          EventRow.colMeetLng: meetLng,
          EventRow.colRouteId: routeId,
          EventRow.colDistanceM: distanceM,
          EventRow.colPaceTargetSec: paceTargetSec,
          EventRow.colCapacity: capacity,
          EventRow.colAuthorId: viewerId,
          if (recurrenceFreq != null) 'recurrence_freq': recurrenceFreq,
          if (recurrenceByDay != null) 'recurrence_byday': recurrenceByDay,
          if (recurrenceUntil != null)
            'recurrence_until': recurrenceUntil.toIso8601String(),
        })
        .select(_eventSafeCols)
        .single();
    return EventRow.fromJson(inserted);
  }

  /// Edit any event field — back-end CHECK constraints validate.
  Future<void> updateEvent({
    required String eventId,
    Map<String, dynamic> patch = const {},
  }) async {
    if (patch.isEmpty) return;
    await _client
        .from(EventRow.table)
        .update(patch)
        .eq(EventRow.colId, eventId);
  }

  /// Cancel an event (cascade-deletes attendees + per-instance
  /// updates).
  Future<void> deleteEvent(String eventId) async {
    await _client.from(EventRow.table).delete().eq(EventRow.colId, eventId);
  }

  /// RSVP to an event for the current viewer. `status` is one of
  /// 'going' | 'maybe' | 'declined'. `instanceStart` is the recurring
  /// instance start; for one-off events, pass the event's `startsAt`.
  Future<void> setEventRsvp({
    required String eventId,
    required DateTime instanceStart,
    required String status,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) throw Exception('Not authenticated');
    await _client.from(EventAttendeeRow.table).upsert(
      {
        EventAttendeeRow.colEventId: eventId,
        EventAttendeeRow.colUserId: viewerId,
        EventAttendeeRow.colStatus: status,
        EventAttendeeRow.colInstanceStart: instanceStart.toIso8601String(),
      },
      onConflict:
          '${EventAttendeeRow.colEventId},${EventAttendeeRow.colUserId},${EventAttendeeRow.colInstanceStart}',
    );
  }

  /// Per-instance attendee list.
  Future<List<EventAttendeeRow>> fetchEventAttendees({
    required String eventId,
    required DateTime instanceStart,
  }) async {
    final data = await _client
        .from(EventAttendeeRow.table)
        .select()
        .eq(EventAttendeeRow.colEventId, eventId)
        .eq(EventAttendeeRow.colInstanceStart, instanceStart.toIso8601String());
    return data
        .map<EventAttendeeRow>((r) => EventAttendeeRow.fromJson(r))
        .toList();
  }

  // ──────────────── Race-director checkpoints (race_director_ops.md) ──────

  /// An event's ordered checkpoints (aid stations / cutoffs). Read directly —
  /// RLS gates the rows to anyone who can see the event. Ordered by `ordinal`.
  Future<List<EventCheckpointRow>> fetchEventCheckpoints(String eventId) async {
    final data = await _client
        .from(EventCheckpointRow.table)
        .select()
        .eq(EventCheckpointRow.colEventId, eventId)
        .order(EventCheckpointRow.colOrdinal, ascending: true);
    return (data as List)
        .map<EventCheckpointRow>(
            (r) => EventCheckpointRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Every crossing logged for one event instance, non-health columns only
  /// (the Art 9 weigh-in fields are column-locked and reachable only via the
  /// organiser RPC). Used to render who's already been stamped.
  Future<List<CheckpointCrossingRow>> fetchCheckpointCrossings(
    String eventId,
    DateTime instanceStart,
  ) async {
    final data = await _client
        .from(CheckpointCrossingRow.table)
        .select(
          'id, event_id, checkpoint_id, instance_start, user_id, bib, '
          'runner_name, in_time, out_time, recorded_at, updated_at',
        )
        .eq(CheckpointCrossingRow.colEventId, eventId)
        .eq(CheckpointCrossingRow.colInstanceStart,
            instanceStart.toIso8601String());
    return (data as List)
        .map<CheckpointCrossingRow>(
            (r) => CheckpointCrossingRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Stamp a runner IN / OUT at a checkpoint through the single-writer RPC. The
  /// server authorises the caller as an organiser and MERGES two volunteers'
  /// stamps (earliest in, latest out), so two phones' client-minted UUIDs
  /// collapse onto one canonical row — no client-side conflict resolution.
  ///
  /// The Art 9 weigh-in fields persist server-side ONLY when the checkpoint
  /// `requires_weigh_in` AND [healthConsent] is true (fail-closed, §150);
  /// otherwise they are dropped even if passed.
  Future<void> upsertCheckpointCrossing({
    required String eventId,
    required String checkpointId,
    required DateTime instanceStart,
    String? userId,
    String? bib,
    String? runnerName,
    DateTime? inTime,
    DateTime? outTime,
    bool healthConsent = false,
    double? bodyWeightKg,
    double? bodyWeightPct,
    bool? medicalHold,
    String? medicalNote,
  }) async {
    await _client.rpc('upsert_checkpoint_crossing', params: {
      'p_event_id': eventId,
      'p_checkpoint_id': checkpointId,
      'p_instance_start': instanceStart.toIso8601String(),
      'p_user_id': userId,
      'p_bib': bib,
      'p_runner_name': runnerName,
      'p_in_time': inTime?.toIso8601String(),
      'p_out_time': outTime?.toIso8601String(),
      'p_health_consent': healthConsent,
      'p_body_weight_kg': bodyWeightKg,
      'p_body_weight_pct': bodyWeightPct,
      'p_medical_hold': medicalHold,
      'p_medical_note': medicalNote,
    });
  }

  // ──────────────────── Plan templates (P1.D) ────────────────────

  /// Plan templates owned by `clubId` — visible to club members.
  Future<List<TrainingPlanRow>> fetchClubTemplates(
    String clubId, {
    int limit = 100,
  }) async {
    final data = await _client
        .from(TrainingPlanRow.table)
        .select()
        .eq('is_template', true)
        .eq('club_id', clubId)
        .order(TrainingPlanRow.colCreatedAt, ascending: false)
        .limit(limit);
    return data
        .map<TrainingPlanRow>((r) => TrainingPlanRow.fromJson(r))
        .toList();
  }

  /// Publish a personal plan as a club template. Server-side RPC
  /// clones the source plan + its weeks + workouts so the source
  /// stays in the user's plan list (decisions §35).
  Future<String> publishPlanAsTemplate({
    required String planId,
    required String clubId,
  }) async {
    final newId = await _client.rpc(
      'publish_plan_as_template',
      params: {'p_source_plan_id': planId, 'p_club_id': clubId},
    );
    return newId as String;
  }

  /// Adopt a club template — clones the template back into a personal
  /// plan for the current viewer.
  Future<String> clonePlanTemplate({
    required String templateId,
    DateTime? startDate,
  }) async {
    final newId = await _client.rpc(
      'clone_plan_template',
      params: {
        'p_template_id': templateId,
        if (startDate != null) 'p_start_date': startDate.toIso8601String(),
      },
    );
    return newId as String;
  }

  /// Club-owned session plans (the club's "session templates"). Visible to
  /// members + writable by admins via RLS. Mirrors [fetchClubTemplates] +
  /// web `fetchClubSessionTemplates` (session_planner.md P3).
  Future<List<SessionPlanRow>> fetchClubSessionTemplates(String clubId) async {
    try {
      final data = await _client
          .from(SessionPlanRow.table)
          .select()
          .eq(SessionPlanRow.colClubId, clubId)
          .order(SessionPlanRow.colUpdatedAt, ascending: false);
      return (data as List)
          .map<SessionPlanRow>(
              (r) => SessionPlanRow.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchClubSessionTemplates failed: $e');
      return const [];
    }
  }

  /// Clone a club session template into a new personal session plan. The
  /// clone_session_template RPC enforces author/member authorisation +
  /// rate-limits server-side. Returns the new plan's id.
  Future<String> cloneSessionTemplate(String templateId) async {
    final newId = await _client.rpc(
      'clone_session_template',
      params: {'template_id': templateId},
    );
    return newId as String;
  }

  // ──────────────────── Phase 2 — domain joins ────────────────────
  //
  // Methods that combine multiple rows into a `core_models/social.dart`
  // shape. Lives here rather than in the screen layer so every
  // consumer (feed, profile, run-detail comments) sees the same
  // typed view.

  /// Profile + follower / following counts + whether the current
  /// viewer follows. Three reads in flight in parallel; null when
  /// the user doesn't exist or RLS hides the row.
  Future<ProfileSummary?> fetchProfileSummary(String userId) async {
    final results = await Future.wait([
      fetchPublicProfile(userId),
      fetchFollowCounts(userId),
      viewerFollows(userId),
    ]);
    final profile = results[0] as UserProfileRow?;
    if (profile == null) return null;
    final counts = results[1] as ({int followers, int following});
    final follows = results[2] as bool;
    return ProfileSummary(
      id: profile.id,
      displayName: profile.displayName,
      avatarUrl: profile.avatarUrl,
      followerCount: counts.followers,
      followingCount: counts.following,
      viewerFollows: follows,
    );
  }

  /// Activity feed: public runs from people the caller follows in the
  /// last `feedWindowDays` (defaults to 14, matching the web cap on
  /// `FEED_WINDOW_DAYS`). Cursor-paginated on `(started_at desc, id
  /// desc)`. Optional filters scope to a single followee or a single
  /// activity type so the feed toolbar can drive them server-side.
  Future<List<FeedEntry>> fetchFollowingFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];

    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, viewerId);
    final followeeIds = edges
        .map<String>((e) => e[UserFollowRow.colFolloweeId] as String)
        .toList();
    if (followeeIds.isEmpty) return const [];

    final filtered = authorId == null
        ? followeeIds
        : followeeIds.where((id) => id == authorId).toList();
    if (filtered.isEmpty) return const [];

    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: feedWindowDays))
        .toIso8601String();

    // Feed reads go through the public_runs view (decisions §33,
    // migration 20260626_001) so the column / metadata-key
    // redaction applies on the wire. The view filters on
    // is_public = true so the explicit eq filter would be
    // redundant.
    var q = _client
        .from('public_runs')
        .select()
        .inFilter(RunRow.colUserId, filtered)
        .gte(RunRow.colStartedAt, cutoff);
    if (activityType != null && activityType != 'all') {
      q = q.eq(RunRow.colActivityType, activityType);
    }
    if (cursor != null) {
      // Stable (started_at desc, id desc) cursor — strictly less than
      // the cursor row.
      final iso = cursor.startedAt.toIso8601String();
      q = q.or(
        'started_at.lt.$iso,and(started_at.eq.$iso,id.lt.${cursor.id})',
      );
    }
    final runs = await q
        .order(RunRow.colStartedAt, ascending: false)
        .order(RunRow.colId, ascending: false)
        .limit(limit);
    if (runs.isEmpty) return const [];

    final authorIds = runs
        .map<String>((r) => r[RunRow.colUserId] as String)
        .toSet()
        .toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, authorIds);
    final profilesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p),
    };

    return runs.map<FeedEntry>((r) {
      final row = RunRow.fromJson(r);
      return FeedEntry(
        run: row,
        author: profilesById[row.userId] ??
            PublicProfile(id: row.userId, displayName: null, avatarUrl: null),
      );
    }).toList();
  }

  /// Cross-modal following feed (multi_modal.md § Social feed): recent public
  /// runs AND public gym workouts from people the caller follows, merged into
  /// one reverse-chronological window.
  ///
  /// Runs go through the redacted `public_runs` view (decisions §33). Lifts
  /// read `gym_workouts` directly — that table's "owner or public read" RLS
  /// scopes a non-owner to public rows, and only the headline columns
  /// (title / set_count / volume_kg) are projected, never notes / per-set
  /// data. `activityType`: 'all' merges both; 'lift' / 'gym' returns lifts
  /// only; any run activity_type returns runs only.
  Future<List<ActivityFeedEntry>> fetchFollowingActivityFeed({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    String? activityType,
    int feedWindowDays = 14,
  }) async {
    final type = activityType ?? 'all';
    final wantsLifts = type == 'all' || type == 'lift' || type == 'gym';
    final wantsRuns = type != 'lift' && type != 'gym';

    final runs = wantsRuns
        ? await fetchFollowingFeed(
            limit: limit,
            cursor: cursor,
            authorId: authorId,
            activityType: activityType,
            feedWindowDays: feedWindowDays,
          )
        : const <FeedEntry>[];
    final lifts = wantsLifts
        ? await _fetchFollowingLifts(
            limit: limit,
            cursor: cursor,
            authorId: authorId,
            feedWindowDays: feedWindowDays,
          )
        : const <LiftFeedEntry>[];

    final merged = <ActivityFeedEntry>[
      for (final r in runs) RunFeedEntry(run: r.run, author: r.author),
      ...lifts,
    ];
    merged.sort((a, b) {
      final c = b.startedAt.compareTo(a.startedAt);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return merged.length > limit ? merged.sublist(0, limit) : merged;
  }

  Future<List<LiftFeedEntry>> _fetchFollowingLifts({
    int limit = 20,
    ({DateTime startedAt, String id})? cursor,
    String? authorId,
    int feedWindowDays = 14,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];

    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, viewerId);
    final followeeIds = edges
        .map<String>((e) => e[UserFollowRow.colFolloweeId] as String)
        .toList();
    if (followeeIds.isEmpty) return const [];

    final filtered = authorId == null
        ? followeeIds
        : followeeIds.where((id) => id == authorId).toList();
    if (filtered.isEmpty) return const [];

    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: feedWindowDays))
        .toIso8601String();

    var q = _client
        .from(GymWorkoutRow.table)
        .select('id, user_id, started_at, title, set_count, volume_kg')
        .eq(GymWorkoutRow.colIsPublic, true)
        .inFilter(GymWorkoutRow.colUserId, filtered)
        .gte(GymWorkoutRow.colStartedAt, cutoff);
    if (cursor != null) {
      final iso = cursor.startedAt.toIso8601String();
      q = q.or(
        'started_at.lt.$iso,and(started_at.eq.$iso,id.lt.${cursor.id})',
      );
    }
    final workouts = await q
        .order(GymWorkoutRow.colStartedAt, ascending: false)
        .order(GymWorkoutRow.colId, ascending: false)
        .limit(limit);
    if (workouts.isEmpty) return const [];

    final authorIds = workouts
        .map<String>((w) => w[GymWorkoutRow.colUserId] as String)
        .toSet()
        .toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, authorIds);
    final profilesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p),
    };

    return workouts.map<LiftFeedEntry>((w) {
      final userId = w[GymWorkoutRow.colUserId] as String;
      return LiftFeedEntry(
        id: w['id'] as String,
        startedAt: DateTime.parse(w['started_at'] as String),
        title: w['title'] as String?,
        setCount: (w['set_count'] as num?)?.toInt() ?? 0,
        volumeKg: (w['volume_kg'] as num?)?.toDouble() ?? 0,
        author: profilesById[userId] ??
            PublicProfile(id: userId, displayName: null, avatarUrl: null),
      );
    }).toList();
  }

  /// Comments on a run with author profiles joined.
  Future<List<RunCommentWithAuthor>> fetchRunCommentsWithAuthors(
    String runId, {
    int limit = 200,
  }) async {
    final comments = await fetchRunComments(runId, limit: limit);
    if (comments.isEmpty) return const [];
    final authorIds =
        comments.map((c) => c.authorId).toSet().toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, authorIds);
    final profilesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p),
    };
    return comments
        .map((c) => RunCommentWithAuthor(
              comment: c,
              author: profilesById[c.authorId] ??
                  PublicProfile(
                      id: c.authorId, displayName: null, avatarUrl: null),
            ))
        .toList();
  }

  /// Notifications with actor profiles + lightweight run / comment /
  /// event metadata joined for the verb line. Notifs, then a parallel
  /// Future.wait over actors / runs / comments / events; events fan
  /// out into a follow-up clubs query for the slug so the inbox can
  /// deep-link `event_rsvp` rows into `/clubs/<slug>/events/<id>`.
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async {
    final rows = await fetchNotifications(limit: limit);
    if (rows.isEmpty) return const [];

    final actorIds = rows
        .where((r) => r.actorId != null)
        .map<String>((r) => r.actorId!)
        .toSet()
        .toList();
    final runIds = rows
        .where((r) => r.runId != null)
        .map<String>((r) => r.runId!)
        .toSet()
        .toList();
    final commentIds = rows
        .where((r) => r.commentId != null)
        .map<String>((r) => r.commentId!)
        .toSet()
        .toList();
    final eventIds = rows
        .where((r) => r.eventId != null)
        .map<String>((r) => r.eventId!)
        .toSet()
        .toList();
    final clubLinkIds = rows
        .where((r) => r.clubId != null)
        .map<String>((r) => r.clubId!)
        .toSet()
        .toList();

    final actorRowsF = actorIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(UserProfileRow.table)
            .select('id, display_name, avatar_url')
            .inFilter(UserProfileRow.colId, actorIds);
    // Two run reads: `runs` resolves the recipient's OWN runs (kudos /
    // comment / reply notifications, where the recipient owns the run
    // and it may be private), and `public_runs` resolves runs owned by
    // someone else (run_completed, where the recipient is a follower —
    // the bare `runs` table has owner-only SELECT since migration
    // 20260701_001 so a follower read returns nothing). Merged below.
    final runRowsF = runIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(RunRow.table)
            .select('${RunRow.colId}, ${RunRow.colDistanceM}')
            .inFilter(RunRow.colId, runIds);
    final publicRunRowsF = runIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from('public_runs')
            .select('${RunRow.colId}, ${RunRow.colDistanceM}')
            .inFilter(RunRow.colId, runIds);
    final commentRowsF = commentIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(RunCommentRow.table)
            .select('${RunCommentRow.colId}, ${RunCommentRow.colBody}')
            .inFilter(RunCommentRow.colId, commentIds);
    final eventRowsF = eventIds.isEmpty
        ? Future.value(<dynamic>[])
        : _client
            .from(EventRow.table)
            .select('${EventRow.colId}, ${EventRow.colTitle}, ${EventRow.colClubId}')
            .inFilter(EventRow.colId, eventIds);

    final results = await Future.wait([
      actorRowsF,
      runRowsF,
      publicRunRowsF,
      commentRowsF,
      eventRowsF,
    ]);
    final actorRows = results[0];
    final runRows = results[1];
    final publicRunRows = results[2];
    final commentRows = results[3];
    final eventRows = results[4];

    final actorsById = <String, PublicProfile>{};
    for (final r in actorRows) {
      final row = r as Map<String, dynamic>;
      actorsById[row['id'] as String] = PublicProfile.fromJson(row);
    }
    final runDistanceById = <String, double>{};
    // Public view first; the owner read overlays it (same columns) so a
    // private own-run the public view omits still resolves a distance.
    for (final r in publicRunRows) {
      final row = r as Map<String, dynamic>;
      final dist = row[RunRow.colDistanceM];
      if (dist is num) runDistanceById[row[RunRow.colId] as String] = dist.toDouble();
    }
    for (final r in runRows) {
      final row = r as Map<String, dynamic>;
      final dist = row[RunRow.colDistanceM];
      if (dist is num) runDistanceById[row[RunRow.colId] as String] = dist.toDouble();
    }
    final commentBodyById = <String, String>{};
    for (final r in commentRows) {
      final row = r as Map<String, dynamic>;
      commentBodyById[row[RunCommentRow.colId] as String] =
          (row[RunCommentRow.colBody] as String?) ?? '';
    }
    final eventById = <String, ({String title, String clubId})>{};
    for (final r in eventRows) {
      final row = r as Map<String, dynamic>;
      eventById[row[EventRow.colId] as String] = (
        title: (row[EventRow.colTitle] as String?) ?? '',
        clubId: (row[EventRow.colClubId] as String?) ?? '',
      );
    }
    // Resolve clubs both for event-linked notifications (need the slug
    // to build the /clubs/<slug>/events/<id> link) and for club_post
    // notifications (linked directly via notifications.club_id — need
    // the slug to navigate and the name for the verb line).
    final clubIds = <String>{
      ...eventById.values.map((e) => e.clubId).where((id) => id.isNotEmpty),
      ...clubLinkIds,
    }.toList();
    final clubById = <String, ({String slug, String name})>{};
    if (clubIds.isNotEmpty) {
      final clubRows = await _client
          .from(ClubRow.table)
          .select('${ClubRow.colId}, ${ClubRow.colSlug}, ${ClubRow.colName}')
          .inFilter(ClubRow.colId, clubIds);
      for (final row in clubRows) {
        clubById[row[ClubRow.colId] as String] = (
          slug: (row[ClubRow.colSlug] as String?) ?? '',
          name: (row[ClubRow.colName] as String?) ?? '',
        );
      }
    }

    String? excerpt(String? id) {
      if (id == null) return null;
      final body = commentBodyById[id];
      if (body == null || body.isEmpty) return null;
      // Cap at 120 visible characters (117 + the ellipsis) to match
      // web's notification-row excerpt
      // (apps/web/src/lib/data.ts:fetchNotifications). Mobile
      // previously capped at 141 — close-enough but visibly longer
      // bubbles in the inbox compared to the same notification
      // viewed on web.
      return body.length > 120 ? '${body.substring(0, 117)}…' : body;
    }

    return rows.map((row) {
      final event = row.eventId == null ? null : eventById[row.eventId!];
      final eventClub = event != null && event.clubId.isNotEmpty
          ? clubById[event.clubId]
          : null;
      final eventClubSlug =
          (eventClub?.slug.isNotEmpty ?? false) ? eventClub!.slug : null;
      final linkedClub = row.clubId == null ? null : clubById[row.clubId!];
      return NotificationView(
        row: row,
        actor: row.actorId == null ? null : actorsById[row.actorId!],
        runDistanceM:
            row.runId == null ? null : runDistanceById[row.runId!],
        commentExcerpt: excerpt(row.commentId),
        eventTitle:
            event != null && event.title.isNotEmpty ? event.title : null,
        eventClubSlug: eventClubSlug,
        clubName: (linkedClub?.name.isNotEmpty ?? false) ? linkedClub!.name : null,
        clubSlug: (linkedClub?.slug.isNotEmpty ?? false) ? linkedClub!.slug : null,
      );
    }).toList();
  }

  /// Segment leaderboard with athlete profiles + ranks. Sorted
  /// by time ascending; dedupes per user (keeps each athlete's
  /// fastest effort). Ranks are standard competition (ties share
  /// a rank; next distinct time skips to its ordinal slot).
  Future<List<SegmentLeaderboardEntry>> fetchSegmentLeaderboardWithAthletes(
    String segmentId, {
    int limit = 200,
  }) async {
    final raw = await fetchSegmentLeaderboard(segmentId, limit: limit);
    if (raw.isEmpty) return const [];

    final byUser = <String, SegmentEffortRow>{};
    for (final eff in raw) {
      final existing = byUser[eff.userId];
      if (existing == null || eff.timeSeconds < existing.timeSeconds) {
        byUser[eff.userId] = eff;
      }
    }
    final efforts = byUser.values.toList()
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final athleteIds = efforts.map((e) => e.userId).toList();
    final profileRows = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, athleteIds);
    final athletesById = {
      for (final p in profileRows)
        p['id'] as String: PublicProfile.fromJson(p),
    };

    final ranks = assignCompetitionRanks(efforts, (e) => e.timeSeconds);
    return [
      for (var i = 0; i < efforts.length; i++)
        SegmentLeaderboardEntry(
          effort: efforts[i],
          athlete: athletesById[efforts[i].userId] ??
              PublicProfile(
                  id: efforts[i].userId, displayName: null, avatarUrl: null),
          rank: ranks[i],
        ),
    ];
  }

  /// v2 tiered leaderboard. Calls `segment_leaderboard_tiered` RPC
  /// (migration 20260829_001) which joins user_profiles server-side
  /// and applies gender + age-band filters there. The RPC returns
  /// already-ordered rows; client assigns standard competition ranks
  /// (ties share a rank; next distinct time skips ordinal positions).
  /// Pass `null` for "any" on either filter; the RPC ignores nulls.
  Future<List<SegmentLeaderboardEntry>> fetchSegmentLeaderboardTiered(
    String segmentId, {
    String? gender,
    String? ageBand,
    int limit = 50,
  }) async {
    final rows = await _client.rpc(
      'segment_leaderboard_tiered',
      params: {
        'p_segment_id': segmentId,
        'p_gender': gender,
        'p_age_band': ageBand,
        'p_limit': limit,
      },
    );
    if (rows is! List || rows.isEmpty) return const [];
    final maps = [
      for (final r in rows) (r as Map).cast<String, dynamic>(),
    ];
    final ranks = assignCompetitionRanks(
      maps,
      (r) => (r['time_seconds'] as num),
    );
    return [
      for (var i = 0; i < maps.length; i++)
        SegmentLeaderboardEntry(
          effort: SegmentEffortRow(
            id: maps[i]['effort_id'] as String,
            segmentId: segmentId,
            runId: maps[i]['run_id'] as String,
            userId: maps[i]['user_id'] as String,
            timeSeconds: (maps[i]['time_seconds'] as num).toDouble(),
            startedAt: DateTime.parse(maps[i]['started_at'] as String),
            createdAt: DateTime.parse(maps[i]['started_at'] as String),
          ),
          athlete: PublicProfile(
            id: maps[i]['user_id'] as String,
            displayName: maps[i]['display_name'] as String?,
            avatarUrl: maps[i]['avatar_url'] as String?,
          ),
          rank: ranks[i],
        ),
    ];
  }

  /// Per-run segment efforts joined to their parent segment + a rank
  /// against the segment's leaderboard. Backs the chips on run-detail.
  Future<List<SegmentEffortWithSegment>> fetchEffortsForRunWithSegments(
    String runId,
  ) async {
    final efforts = await fetchEffortsForRun(runId);
    if (efforts.isEmpty) return const [];

    final segIds = efforts.map((e) => e.segmentId).toSet().toList();
    final segRows = await _client
        .from(SegmentRow.table)
        .select()
        .inFilter(SegmentRow.colId, segIds);
    final segById = {
      for (final s in segRows)
        s['id'] as String: SegmentRow.fromJson(s),
    };

    final out = <SegmentEffortWithSegment>[];
    for (final eff in efforts) {
      final seg = segById[eff.segmentId];
      if (seg == null) continue;
      // Rank = (count of efforts on this segment with strictly faster
      // time) + 1. The (segment_id, time_seconds) index covers it.
      final faster = await _client
          .from(SegmentEffortRow.table)
          .count(CountOption.exact)
          .eq(SegmentEffortRow.colSegmentId, eff.segmentId)
          .lt(SegmentEffortRow.colTimeSeconds, eff.timeSeconds);
      out.add(SegmentEffortWithSegment(
        effort: eff,
        segment: seg,
        rank: faster + 1,
      ));
    }
    return out;
  }

  // -- Row mapping (generated RunRow/RouteRow → domain Run/Route) --
  //
  // These go through the generated row classes so that column renames surface
  // as compile errors on the consuming fields below, not as silent runtime
  // drift.

  // activity_type and is_dnf (migration 20261207_001) plus the four
  // embedded-best fastest_*_s keys (migration 20270325_001) are promoted
  // columns; the `Run` domain object still carries them inside its metadata
  // bag for a single read path, so saveRun lifts them into the columns and
  // strips them from the persisted bag here — the column is the only stored
  // copy.
  static Map<String, dynamic>? _metadataWithoutPromotedColumns(
    Map<String, dynamic>? metadata,
  ) {
    if (metadata == null) return null;
    final out = Map<String, dynamic>.from(metadata)
      ..remove('activity_type')
      ..remove('is_dnf')
      ..remove('fastest_5k_s')
      ..remove('fastest_10k_s')
      ..remove('fastest_half_marathon_s')
      ..remove('fastest_marathon_s');
    return out.isEmpty ? null : out;
  }

  // Bag → column lift for the promoted embedded-best keys. Non-negative
  // integers only — the same domain the old SQL-side `~ '^[0-9]+$'`
  // validation admitted; anything else is dropped, never written.
  static int? _embeddedBestSeconds(Map<String, dynamic>? metadata, String key) {
    final v = metadata?[key];
    final secs = v is int ? v : (v is num ? v.toInt() : null);
    if (secs == null || secs < 0) return null;
    return secs;
  }

  static Run _runFromRow(Map<String, dynamic> row) {
    final r = RunRow.fromJson(row);
    // Stash the storage path on metadata so callers can pass the run back
    // to fetchTrack() to lazy-load the GPS waypoints. The track field itself
    // stays empty until fetched.
    final metadata = Map<String, dynamic>.from(r.metadata ?? const {});
    if (r.trackUrl != null) metadata['track_url'] = r.trackUrl;
    // Same lazy-load stash for the indoor/treadmill HR sidecar
    // ({user_id}/{run_id}.hr.json.gz) so run-detail can fall back to it for the
    // HR-zone chart when the GPS track has no per-point bpm (decisions §116).
    if (r.hrSeriesUrl != null) metadata['hr_series_url'] = r.hrSeriesUrl;
    // activity_type / is_dnf (20261207_001) and the embedded-best
    // fastest_*_s keys (20270325_001) are promoted columns; the column is
    // authoritative. Surface them back onto metadata so the domain readers
    // keep their single access path, the same convenience stash as
    // track_url above. The nullable bests only stash when present, matching
    // the old absent-key bag semantics.
    metadata['activity_type'] = r.activityType;
    metadata['is_dnf'] = r.isDnf;
    if (r.fastest5kS != null) metadata['fastest_5k_s'] = r.fastest5kS;
    if (r.fastest10kS != null) metadata['fastest_10k_s'] = r.fastest10kS;
    if (r.fastestHalfMarathonS != null) {
      metadata['fastest_half_marathon_s'] = r.fastestHalfMarathonS;
    }
    if (r.fastestMarathonS != null) {
      metadata['fastest_marathon_s'] = r.fastestMarathonS;
    }

    return Run(
      id: r.id,
      startedAt: r.startedAt,
      duration: Duration(seconds: r.durationS),
      distanceMetres: r.distanceM,
      track: const [],
      // Carry the route link through the read so a `linkRunToRoute` isn't
      // silently wiped to null on the next newer-wins merge / saveRun.
      routeId: r.routeId,
      source: RunSource.values.firstWhere(
        (s) => s.name == r.source,
        orElse: () => RunSource.app,
      ),
      externalId: r.externalId,
      metadata: metadata.isEmpty ? null : metadata,
      createdAt: r.createdAt,
    );
  }

  static Route _routeFromRow(Map<String, dynamic> row) {
    // Tolerant of rows from the `public_routes` view, which strips
    // `waypoints` / `geom` / `start_point` / `is_starred` to close the
    // wire-leak documented in migration 20260703_001_public_routes_view.sql.
    // Browse / list surfaces (search, nearby, within-box) read through
    // the view and don't render polylines anyway; the caller layers a
    // separate clip_route_for_viewer call for surfaces that need one.
    final waypointsRaw = row['waypoints'];
    final waypoints = waypointsRaw is List
        ? waypointsRaw.map((e) {
            final m = e as Map<String, dynamic>;
            return Waypoint(
              lat: (m['lat'] as num).toDouble(),
              lng: (m['lng'] as num).toDouble(),
              elevationMetres: (m['ele'] as num?)?.toDouble(),
            );
          }).toList()
        : const <Waypoint>[];
    return Route(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      name: row['name'] as String,
      waypoints: waypoints,
      distanceMetres: (row['distance_m'] as num).toDouble(),
      elevationGainMetres: (row['elevation_m'] as num?)?.toDouble() ?? 0,
      isPublic: row['is_public'] as bool? ?? false,
      surface: row['surface'] as String?,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.parse(row['created_at'] as String),
      tags: (row['tags'] as List?)?.cast<String>() ?? const [],
      featured: row['is_featured'] == true,
      runCount: (row['run_count'] as num?)?.toInt() ?? 0,
      isStarred: row['is_starred'] == true,
      clubId: row['club_id'] as String?,
      description: row['description'] as String?,
    );
  }

  // ──────────────────── Integrations ────────────────────

  /// Connected providers for the current user. Mirrors web
  /// `fetchIntegrations` — RLS gates results to the viewer.
  Future<List<IntegrationRow>> fetchIntegrations() async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];
    final data = await _client
        .from(IntegrationRow.table)
        .select()
        .eq(IntegrationRow.colUserId, viewerId)
        .order(IntegrationRow.colCreatedAt, ascending: true);
    return data.map<IntegrationRow>((r) => IntegrationRow.fromJson(r)).toList();
  }

  /// Remove the integration row for the given provider. The Edge
  /// Function does NOT need to be called — Strava revocation happens
  /// when we drop our refresh token.
  Future<void> disconnectIntegration(String provider) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return;
    await _client
        .from(IntegrationRow.table)
        .delete()
        .eq(IntegrationRow.colUserId, viewerId)
        .eq(IntegrationRow.colProvider, provider);
  }

  /// Trigger a manual Strava backfill via the `strava-import` Edge
  /// Function. Mirrors the web `syncStrava` helper. Returns the raw
  /// response payload so the caller can surface
  /// `{imported, skipped, failed}` in a toast.
  Future<Map<String, dynamic>> syncStrava({int lookbackDays = 90}) async {
    final res = await _client.functions.invoke(
      'strava-import',
      body: {'action': 'sync', 'lookbackDays': lookbackDays},
    );
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  /// Complete the in-app Strava OAuth exchange. The caller (Settings)
  /// drives the user through `FlutterWebAuth2.authenticate(...)` and
  /// receives a `threkir://strava-callback?code=...&scope=...` URL;
  /// this method posts the extracted `code` + `scope` + `redirect_uri`
  /// to the `strava-import` EF with `action: 'connect'`. The EF
  /// validates the redirect against `STRAVA_ALLOWED_REDIRECTS`, swaps
  /// the code for a refresh token, and writes the row to `integrations`.
  /// Returns the raw response so callers can surface success/failure.
  Future<Map<String, dynamic>> completeStravaOAuth({
    required String code,
    required String scope,
    required String redirectUri,
  }) async {
    final res = await _client.functions.invoke(
      'strava-import',
      body: {
        'action': 'connect',
        'code': code,
        'scope': scope,
        'redirect_uri': redirectUri,
      },
    );
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  /// Lightweight count of a user's runs, capped by [limit]. The coach
  /// context strip uses this to show how much history the model is
  /// reasoning over — only the count matters, so the column projection
  /// stays at `id` to keep the payload small.
  Future<int> countRunsForUser(String userId, {int limit = 100}) async {
    final rows = await _client
        .from(RunRow.table)
        .select(RunRow.colId)
        .eq(RunRow.colUserId, userId)
        .limit(limit);
    return (rows as List).length;
  }

  /// Universal user-prefs bag (`user_settings.prefs`). Returns null when
  /// the row doesn't exist yet (fresh sign-up). Callers extract specific
  /// keys (`hr_zones`, `weekly_mileage_goal_m`, etc.).
  Future<Map<String, dynamic>?> fetchUserSettingsPrefs(String userId) async {
    final row = await _client
        .from('user_settings')
        .select('prefs')
        .eq('user_id', userId)
        .maybeSingle();
    final prefs = row?['prefs'];
    if (prefs is Map) return Map<String, dynamic>.from(prefs);
    return null;
  }

  /// Live-spectator hydration. Fetches existing `live_run_pings` for a
  /// run in chronological order so a newly-mounted spectator screen can
  /// catch up on the trail before subscribing to realtime inserts.
  Future<List<Map<String, dynamic>>> fetchLiveRunPings(String runId) async {
    final rows = await _client
        .from('live_run_pings')
        .select('lat, lng, ele, distance_m, elapsed_s, at')
        .eq('run_id', runId)
        .order('at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Pre-create a stub `runs` row so live spectator pings can land
  /// before the real save on stop. The `live_run_pings` FK + the
  /// insert RLS both require a parent `runs` row owned by the caller;
  /// this is the cheapest way to satisfy both without restructuring
  /// the recorder's save flow.
  ///
  /// Idempotent — repeated calls (e.g. user re-taps "Share live link")
  /// are no-ops via ignoreDuplicates. The row is created with
  /// `is_public = true` so anyone with the share URL can watch; the
  /// final `saveRun` upsert will overwrite the placeholder fields, so
  /// callers that want the finished run to stay public must re-assert
  /// it via [makeRunPublic] after save.
  Future<void> beginLiveBroadcast({
    required String runId,
    required DateTime startedAt,
    String activityType = 'run',
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    // activity_type is a column (migration 20261207_001); default to `run` —
    // the recorder updates the same row on stop with the user's actual
    // activity choice via saveRun's upsert.
    await _client.from(RunRow.table).upsert(
      {
        RunRow.colId: runId,
        RunRow.colUserId: userId,
        RunRow.colStartedAt: startedAt.toUtc().toIso8601String(),
        RunRow.colDurationS: 0,
        RunRow.colDistanceM: 0,
        RunRow.colSource: 'app',
        RunRow.colIsPublic: true,
        RunRow.colActivityType: activityType,
        RunRow.colMetadata: {
          'in_progress': true,
        },
      },
      ignoreDuplicates: true,
    );
  }

  /// Append one spectator ping for an in-progress run. Intended to be
  /// called from the recorder's per-snapshot hot path, throttled by
  /// the caller to ~5 s (more than that overwhelms the spectator map
  /// and Realtime fanout). Failures are L4 — caller swallows.
  Future<void> insertLivePing({
    required String runId,
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('live_run_pings').insert({
      'run_id': runId,
      'user_id': userId,
      'lat': lat,
      'lng': lng,
      if (distanceM != null) 'distance_m': distanceM,
      if (elapsedS != null) 'elapsed_s': elapsedS,
      if (bpm != null) 'bpm': bpm,
      if (ele != null) 'ele': ele,
    });
  }

  /// Wipe spectator pings for a run. Called after the recorder's
  /// final `saveRun` so the spectator history isn't duplicated by the
  /// completed run's track. The `cleanup-stale-live-run-pings` cron
  /// is a safety net for clients that crash before this fires.
  Future<void> endLiveBroadcast(String runId) async {
    await _client
        .from('live_run_pings')
        .delete()
        .eq('run_id', runId);
  }

  // ─────────────────── Gym (Phase 4 multi-modal, decisions §63) ───────────────────

  /// Recent gym workouts for the signed-in user, newest first.
  Future<List<GymWorkoutRow>> fetchGymWorkouts({int limit = 50}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await _client
        .from(GymWorkoutRow.table)
        .select()
        .eq(GymWorkoutRow.colUserId, uid)
        .order(GymWorkoutRow.colStartedAt, ascending: false)
        .limit(limit);
    return (data as List)
        .map((r) => GymWorkoutRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// A workout plus its sets in `set_index` order. Null when the row is
  /// missing or RLS hides it.
  Future<({GymWorkoutRow workout, List<GymSetRow> sets})?> fetchGymWorkoutWithSets(
      String id) async {
    final w = await _client
        .from(GymWorkoutRow.table)
        .select()
        .eq(GymWorkoutRow.colId, id)
        .maybeSingle();
    if (w == null) return null;
    final s = await _client
        .from(GymSetRow.table)
        .select()
        .eq(GymSetRow.colWorkoutId, id)
        .order(GymSetRow.colSetIndex, ascending: true);
    return (
      workout: GymWorkoutRow.fromJson(w),
      sets: (s as List)
          .map((r) => GymSetRow.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The exercise catalogue visible to the signed-in user: every seeded
  /// global (author_id null) plus their own custom entries (RLS scopes the
  /// read). Migration 20270222_001. Returns the rows ordered by name so the
  /// composer can merge them into its autocomplete + bind a typed name to an
  /// exercise_id. Additive — a user who never picks a catalogue entry logs
  /// exactly as before (exercise_id stays null).
  Future<List<ExerciseRow>> fetchExerciseCatalogue() async {
    final rows = await _client
        .from(ExerciseRow.table)
        .select()
        .order(ExerciseRow.colName, ascending: true);
    return (rows as List)
        .map((r) => ExerciseRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Create an owner-scoped custom catalogue entry (migration 20270222_001).
  /// [nameKey] is `normaliseExerciseName(name)`, stamped by the caller so this
  /// package stays decoupled from the gym_prs helper — it's the frozen identity
  /// a logged set binds by. RLS rejects any author_id other than the caller, so
  /// the returned row is always owned by the signed-in user. Returns null when
  /// signed out or on conflict/error (e.g. a duplicate name_key in the user's
  /// own customs).
  Future<ExerciseRow?> createCustomExercise({
    required String name,
    required String nameKey,
    String category = 'other',
    String modality = 'weight_reps',
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    try {
      final row = await _client
          .from(ExerciseRow.table)
          .insert(<String, dynamic>{
            ExerciseRow.colAuthorId: uid,
            ExerciseRow.colName: trimmed,
            ExerciseRow.colNameKey: nameKey,
            ExerciseRow.colCategory: category,
            ExerciseRow.colModality: modality,
            ExerciseRow.colLastModifiedAt: DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      return ExerciseRow.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  /// The signed-in user's recent workouts each paired with their sets,
  /// newest-started first. Two round-trips (workouts, then every set whose
  /// `workout_id` is in that page) grouped client-side — the shape
  /// [LocalGymStore.replaceFromServer] consumes so the offline cache and
  /// the list screen's volume / PR stats hydrate in one refresh.
  Future<List<({Map<String, dynamic> workout, List<Map<String, dynamic>> sets})>>
      fetchGymWorkoutsWithSets({int limit = 50}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final ws = await _client
        .from(GymWorkoutRow.table)
        .select()
        .eq(GymWorkoutRow.colUserId, uid)
        .order(GymWorkoutRow.colStartedAt, ascending: false)
        .limit(limit);
    final workouts = (ws as List).cast<Map<String, dynamic>>();
    if (workouts.isEmpty) return [];
    final ids = [for (final w in workouts) w[GymWorkoutRow.colId] as String];
    final ss = await _client
        .from(GymSetRow.table)
        .select()
        .inFilter(GymSetRow.colWorkoutId, ids)
        .order(GymSetRow.colSetIndex, ascending: true);
    final byWorkout = <String, List<Map<String, dynamic>>>{};
    for (final raw in (ss as List).cast<Map<String, dynamic>>()) {
      (byWorkout[raw[GymSetRow.colWorkoutId] as String] ??= []).add(raw);
    }
    return [
      for (final w in workouts)
        (
          workout: w,
          sets: byWorkout[w[GymWorkoutRow.colId] as String] ?? const [],
        ),
    ];
  }

  /// Session plans (session_planner.md P1) the caller can see: their own plans
  /// plus any plan owned by a club they belong to (RLS owns the authority).
  /// Read-only on mobile in P1 — the editor lives on web first.
  Future<List<SessionPlanRow>> fetchSessionPlans() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    try {
      final data = await _client
          .from(SessionPlanRow.table)
          .select()
          .order(SessionPlanRow.colUpdatedAt, ascending: false);
      return (data as List)
          .map<SessionPlanRow>(
              (row) => SessionPlanRow.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchSessionPlans failed: $e');
      return const [];
    }
  }

  /// A single session plan with its blocks + items, for the mobile read view.
  /// Null when the plan is absent or not visible to the caller.
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
  })?> fetchSessionPlan(String id) async {
    try {
      final planRow = await _client
          .from(SessionPlanRow.table)
          .select()
          .eq(SessionPlanRow.colId, id)
          .maybeSingle();
      if (planRow == null) return null;
      final blocksData = await _client
          .from(SessionPlanBlockRow.table)
          .select()
          .eq(SessionPlanBlockRow.colPlanId, id)
          .order(SessionPlanBlockRow.colPosition, ascending: true);
      final itemsData = await _client
          .from(SessionPlanItemRow.table)
          .select()
          .eq(SessionPlanItemRow.colPlanId, id)
          .order(SessionPlanItemRow.colPosition, ascending: true);
      return (
        plan: SessionPlanRow.fromJson(planRow),
        blocks: (blocksData as List)
            .map<SessionPlanBlockRow>(
                (r) => SessionPlanBlockRow.fromJson(r as Map<String, dynamic>))
            .toList(),
        items: (itemsData as List)
            .map<SessionPlanItemRow>(
                (r) => SessionPlanItemRow.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      debugPrint('fetchSessionPlan failed: $e');
      return null;
    }
  }

  /// Insert a session plan + its blocks + items. The caller may mint [id] (the
  /// offline-create path) — `session_plans.id` defaults to gen_random_uuid()
  /// but accepts a client value, so the local id IS the server id (no
  /// reconciliation), matching [createGymWorkout] / [createGymRoutine].
  /// Block ids are client-minted too so an item's [SessionPlanItemInput.blockId]
  /// references the block in the same insert without a server round-trip.
  Future<SessionPlanRow> createSessionPlan({
    String? id,
    required String title,
    String? discipline,
    String? equipment,
    int? estDurationMin,
    bool isPublic = false,
    DateTime? updatedAt,
    List<SessionPlanBlockInput> blocks = const [],
    List<SessionPlanItemInput> items = const [],
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final row = await _client
        .from(SessionPlanRow.table)
        .insert({
          if (id != null) SessionPlanRow.colId: id,
          SessionPlanRow.colAuthorId: uid,
          SessionPlanRow.colTitle: title.trim(),
          SessionPlanRow.colDiscipline: discipline,
          SessionPlanRow.colEquipment: equipment,
          SessionPlanRow.colEstDurationMin: estDurationMin,
          SessionPlanRow.colIsPublic: isPublic,
          if (updatedAt != null)
            SessionPlanRow.colUpdatedAt: updatedAt.toIso8601String(),
        })
        .select()
        .single();
    final plan = SessionPlanRow.fromJson(row);
    if (blocks.isNotEmpty) {
      await _client.from(SessionPlanBlockRow.table).insert([
        for (final b in blocks)
          {
            SessionPlanBlockRow.colId: b.id,
            SessionPlanBlockRow.colPlanId: plan.id,
            SessionPlanBlockRow.colPosition: b.position,
            SessionPlanBlockRow.colName: b.name,
          },
      ]);
    }
    if (items.isNotEmpty) {
      await _client.from(SessionPlanItemRow.table).insert([
        for (final it in items)
          {
            SessionPlanItemRow.colId: it.id,
            SessionPlanItemRow.colPlanId: plan.id,
            SessionPlanItemRow.colBlockId: it.blockId,
            SessionPlanItemRow.colPosition: it.position,
            SessionPlanItemRow.colMovementName: it.movementName,
            SessionPlanItemRow.colKind: it.kind,
            SessionPlanItemRow.colDurationS: it.durationS,
            SessionPlanItemRow.colReps: it.reps,
            SessionPlanItemRow.colPerSide: it.perSide,
            SessionPlanItemRow.colTempo: it.tempo,
            SessionPlanItemRow.colCue: it.cue,
          },
      ]);
    }
    return plan;
  }

  /// Delete a session plan; blocks + items cascade via FK. Logged gym_workouts
  /// are untouched (the session→log link is a metadata string, not an FK).
  Future<void> deleteSessionPlan(String id) async {
    await _client.from(SessionPlanRow.table).delete().eq(SessionPlanRow.colId, id);
  }

  /// Flip a session plan's is_public flag (owner-only via RLS). A public plan
  /// is readable logged-out at the web /share/session/[id] page. Mirrors
  /// [setRoutePublic] + web `setSessionPlanPublic`.
  Future<void> setSessionPlanPublic(String id, bool isPublic) async {
    await _client
        .from(SessionPlanRow.table)
        .update({SessionPlanRow.colIsPublic: isPublic})
        .eq(SessionPlanRow.colId, id);
  }

  /// Windowed, reverse-chronological feed across all logged modalities for
  /// the unified History timeline. RLS (`security_invoker` on the `activities`
  /// view) scopes it to the caller. Always bounded — the timeline paginates
  /// like the run list rather than pulling an unbounded history (multi_modal.md
  /// § "activities view at scale"). Mirrors web `fetchActivities`
  /// (core/data.ts).
  Future<List<ActivityRow>> fetchActivities({int limit = 100}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await _client
        .from('activities')
        .select('id, kind, started_at, summary')
        .eq('user_id', uid)
        .order('started_at', ascending: false)
        .limit(limit);
    final out = <ActivityRow>[];
    for (final raw in (data as List).cast<Map<String, dynamic>>()) {
      final row = ActivityRow.fromRow(raw);
      if (row != null) out.add(row);
    }
    return out;
  }

  /// Insert a workout + its sets. The caller may mint [id] (offline-create
  /// path) — `gym_workouts.id` defaults to gen_random_uuid() but accepts a
  /// client value, so the local id IS the server id (no reconciliation),
  /// matching the LocalGearStore pattern (decisions §73).
  Future<GymWorkoutRow> createGymWorkout({
    String? id,
    String? title,
    required DateTime startedAt,
    int? durationS,
    String? notes,
    bool isPublic = false,
    String? externalId,
    DateTime? lastModifiedAt,
    Map<String, dynamic>? metadata,
    List<GymSetInput> sets = const [],
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final row = await _client
        .from(GymWorkoutRow.table)
        .insert({
          if (id != null) GymWorkoutRow.colId: id,
          GymWorkoutRow.colUserId: uid,
          GymWorkoutRow.colTitle: title,
          GymWorkoutRow.colStartedAt: startedAt.toIso8601String(),
          GymWorkoutRow.colDurationS: durationS,
          GymWorkoutRow.colNotes: notes,
          GymWorkoutRow.colIsPublic: isPublic,
          GymWorkoutRow.colExternalId: externalId,
          if (metadata != null && metadata.isNotEmpty)
            GymWorkoutRow.colMetadata: metadata,
          if (lastModifiedAt != null)
            GymWorkoutRow.colLastModifiedAt: lastModifiedAt.toIso8601String(),
        })
        .select()
        .single();
    final workout = GymWorkoutRow.fromJson(row);
    if (sets.isNotEmpty) await _replaceGymSets(workout.id, sets);
    return workout;
  }

  /// Replace a workout's sets wholesale (delete + re-insert in order). The
  /// composer always edits the full set list, so a replace is simpler and
  /// less bug-prone than diffing individual rows.
  Future<void> _replaceGymSets(String workoutId, List<GymSetInput> sets) async {
    await _client.from(GymSetRow.table).delete().eq(GymSetRow.colWorkoutId, workoutId);
    if (sets.isEmpty) return;
    await _client.from(GymSetRow.table).insert([
      for (var i = 0; i < sets.length; i++)
        {
          GymSetRow.colWorkoutId: workoutId,
          GymSetRow.colSetIndex: i,
          GymSetRow.colExerciseName: sets[i].exerciseName,
          GymSetRow.colReps: sets[i].reps,
          GymSetRow.colWeightKg: sets[i].weightKg,
          GymSetRow.colRpe: sets[i].rpe,
          // NOT NULL column — fall back to the working default (20270224_001).
          GymSetRow.colSetType: sets[i].setType ?? 'working',
          GymSetRow.colDurationS: sets[i].durationS,
          GymSetRow.colExerciseId: sets[i].exerciseId,
        },
    ]);
  }

  /// Patch a workout's metadata; pass [sets] to replace the set list too.
  /// Stamps `last_modified_at` (client-controlled, for newer-wins sync).
  Future<void> updateGymWorkout(
    String id, {
    String? title,
    int? durationS,
    String? notes,
    bool? isPublic,
    DateTime? lastModifiedAt,
    Map<String, dynamic>? metadata,
    List<GymSetInput>? sets,
  }) async {
    final patch = <String, dynamic>{
      GymWorkoutRow.colLastModifiedAt:
          (lastModifiedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    if (title != null) patch[GymWorkoutRow.colTitle] = title;
    if (durationS != null) patch[GymWorkoutRow.colDurationS] = durationS;
    if (notes != null) patch[GymWorkoutRow.colNotes] = notes;
    if (isPublic != null) patch[GymWorkoutRow.colIsPublic] = isPublic;
    if (metadata != null) patch[GymWorkoutRow.colMetadata] = metadata;
    await _client.from(GymWorkoutRow.table).update(patch).eq(GymWorkoutRow.colId, id);
    if (sets != null) await _replaceGymSets(id, sets);
  }

  /// Flip a gym workout's visibility. Bidirectional (public ↔ private),
  /// mirroring [setRoutePublic]; stamps `last_modified_at` so the offline
  /// newer-wins reconciliation picks the change up.
  Future<void> setGymWorkoutPublic(String id, bool isPublic) async {
    await _client.from(GymWorkoutRow.table).update({
      GymWorkoutRow.colIsPublic: isPublic,
      GymWorkoutRow.colLastModifiedAt: DateTime.now().toUtc().toIso8601String(),
    }).eq(GymWorkoutRow.colId, id);
  }

  /// Delete a workout. `gym_sets` cascade via the FK.
  Future<void> deleteGymWorkout(String id) async {
    await _client.from(GymWorkoutRow.table).delete().eq(GymWorkoutRow.colId, id);
  }

  // ─────────────────── Gym routines (gym_programming.md P1) ───────────────────
  //
  // A reusable plan: gym_routines parent + gym_routine_exercises + their
  // gym_routine_sets (migration 20270101_001, author-only RLS). Mirrors web
  // core/data.ts (createGymRoutine / fetchGymRoutines / fetchGymRoutineDetail /
  // deleteGymRoutine). last_modified_at + exercise_count are client-stamped
  // (newer-wins sync, non-authoritative count — no server trigger). The plan is
  // NOT a dated activity, so it never feeds the activities view. P1 leaves the
  // superset / progression / periodisation columns at their defaults.

  /// Authored routines for the signed-in user, most-recently-modified first.
  /// Author-only RLS scopes the read; the explicit `author_id` filter is
  /// defence-in-depth, matching the other personal-data reads.
  Future<List<GymRoutineRow>> fetchGymRoutines({int limit = 100}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final data = await _client
        .from(GymRoutineRow.table)
        .select()
        .eq(GymRoutineRow.colAuthorId, uid)
        .order(GymRoutineRow.colLastModifiedAt, ascending: false)
        .limit(limit);
    return (data as List)
        .map((r) => GymRoutineRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// A single routine with its exercises (by position) + their planned sets
  /// (by set_index). Two round-trips (exercises, then every set whose
  /// `routine_exercise_id` is in that list) grouped client-side — the shape
  /// [LocalRoutineStore] consumes. Null when the id doesn't resolve (RLS hides
  /// others').
  /// A public template a non-author previews (the library detail path) misses
  /// on the owner-only base table and falls back to the redacted
  /// public_gym_routines view (migration 20270319_001), which carries no
  /// external_id / last_modified_at — created_at stands in for the model's
  /// required last-modified field.
  Future<({
    GymRoutineRow routine,
    List<({GymRoutineExerciseRow exercise, List<GymRoutineSetRow> sets})> exercises,
  })?> fetchGymRoutineDetail(String id) async {
    var r = await _client
        .from(GymRoutineRow.table)
        .select()
        .eq(GymRoutineRow.colId, id)
        .maybeSingle();
    if (r == null) {
      final pub = await _client
          .from('public_gym_routines')
          .select()
          .eq(GymRoutineRow.colId, id)
          .maybeSingle();
      if (pub == null) return null;
      r = {...pub, GymRoutineRow.colLastModifiedAt: pub[GymRoutineRow.colCreatedAt]};
    }
    final routine = GymRoutineRow.fromJson(r);
    final exRows = await _client
        .from(GymRoutineExerciseRow.table)
        .select()
        .eq(GymRoutineExerciseRow.colRoutineId, id)
        .order(GymRoutineExerciseRow.colPosition, ascending: true);
    final exercises = (exRows as List)
        .map((e) => GymRoutineExerciseRow.fromJson(e as Map<String, dynamic>))
        .toList();
    if (exercises.isEmpty) {
      return (
        routine: routine,
        exercises:
            <({GymRoutineExerciseRow exercise, List<GymRoutineSetRow> sets})>[],
      );
    }
    final setRows = await _client
        .from(GymRoutineSetRow.table)
        .select()
        .inFilter(GymRoutineSetRow.colRoutineExerciseId,
            [for (final e in exercises) e.id])
        .order(GymRoutineSetRow.colSetIndex, ascending: true);
    final byExercise = <String, List<GymRoutineSetRow>>{};
    for (final raw in (setRows as List).cast<Map<String, dynamic>>()) {
      final s = GymRoutineSetRow.fromJson(raw);
      (byExercise[s.routineExerciseId] ??= []).add(s);
    }
    return (
      routine: routine,
      exercises: [
        for (final e in exercises)
          (exercise: e, sets: byExercise[e.id] ?? const []),
      ],
    );
  }

  /// Insert a routine + its exercises + their planned sets. Blank-named
  /// exercises are dropped. `exercise_count` is stamped client-side from the
  /// surviving exercise list (non-authoritative cache). The caller may mint
  /// [id] (offline-create path) — `gym_routines.id` defaults to
  /// gen_random_uuid() but accepts a client value, so the local id IS the
  /// server id (no reconciliation), matching the gym/gear pattern. Child rows
  /// (exercises, sets) always get fresh server ids on insert.
  Future<GymRoutineRow> createGymRoutine({
    String? id,
    required String title,
    String? notes,
    DateTime? lastModifiedAt,
    List<GymRoutineExerciseInput> exercises = const [],
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final kept = exercises
        .where((e) => e.exerciseName.trim().isNotEmpty)
        .toList(growable: false);
    final row = await _client
        .from(GymRoutineRow.table)
        .insert({
          if (id != null) GymRoutineRow.colId: id,
          GymRoutineRow.colAuthorId: uid,
          GymRoutineRow.colTitle: title.trim(),
          GymRoutineRow.colNotes: notes,
          GymRoutineRow.colExerciseCount: kept.length,
          if (lastModifiedAt != null)
            GymRoutineRow.colLastModifiedAt: lastModifiedAt.toIso8601String(),
        })
        .select()
        .single();
    final routine = GymRoutineRow.fromJson(row);
    for (var p = 0; p < kept.length; p++) {
      final ex = kept[p];
      // gym_routine_exercises_superset_chk requires the group + order to be
      // both null or both set, so a standalone exercise clears both.
      final g = ex.supersetGroup;
      final exRow = await _client
          .from(GymRoutineExerciseRow.table)
          .insert({
            GymRoutineExerciseRow.colRoutineId: routine.id,
            GymRoutineExerciseRow.colExerciseName: ex.exerciseName.trim(),
            GymRoutineExerciseRow.colExerciseKey: ex.exerciseKey,
            GymRoutineExerciseRow.colPosition: p,
            GymRoutineExerciseRow.colSupersetGroup: g,
            GymRoutineExerciseRow.colSupersetOrder:
                g == null ? null : (ex.supersetOrder ?? 0),
            GymRoutineExerciseRow.colModality: ex.modality ?? 'weight_reps',
            GymRoutineExerciseRow.colProgression: ex.progression ?? 'none',
            GymRoutineExerciseRow.colProgressionParams:
                ex.progressionParams ?? <String, dynamic>{},
          })
          .select(GymRoutineExerciseRow.colId)
          .single();
      final exId = exRow[GymRoutineExerciseRow.colId] as String;
      if (ex.sets.isNotEmpty) {
        await _client.from(GymRoutineSetRow.table).insert([
          for (var i = 0; i < ex.sets.length; i++)
            {
              GymRoutineSetRow.colRoutineExerciseId: exId,
              GymRoutineSetRow.colSetIndex: i,
              GymRoutineSetRow.colSetType: ex.sets[i].setType ?? 'working',
              GymRoutineSetRow.colTargetRepsMin: ex.sets[i].targetRepsMin,
              GymRoutineSetRow.colTargetRepsMax: ex.sets[i].targetRepsMax,
              GymRoutineSetRow.colTargetWeightKg: ex.sets[i].targetWeightKg,
              GymRoutineSetRow.colTargetRpe: ex.sets[i].targetRpe,
              GymRoutineSetRow.colRestS: ex.sets[i].restS,
              GymRoutineSetRow.colTargetDurationS: ex.sets[i].targetDurationS,
              GymRoutineSetRow.colTargetDistanceM: ex.sets[i].targetDistanceM,
            },
        ]);
      }
    }
    return routine;
  }

  /// Delete a routine; exercises + sets cascade via FK (migration
  /// 20270101_001). Logged gym_workouts are untouched (the plan→log link is a
  /// metadata string, not an FK).
  Future<void> deleteGymRoutine(String id) async {
    await _client.from(GymRoutineRow.table).delete().eq(GymRoutineRow.colId, id);
  }

  /// Club-owned gym routines published as templates (`gym_routines.club_id`
  /// set). RLS exposes these to club members. Mirrors web
  /// `fetchClubGymRoutineTemplates` + the session-template fetch's fail-soft
  /// shape (gym_routine_club_templates, migration 20270109_001).
  Future<List<GymRoutineRow>> fetchClubGymRoutineTemplates(String clubId) async {
    try {
      final data = await _client
          .from(GymRoutineRow.table)
          .select()
          .eq(GymRoutineRow.colClubId, clubId)
          .order(GymRoutineRow.colLastModifiedAt, ascending: false);
      return (data as List)
          .map((r) => GymRoutineRow.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('fetchClubGymRoutineTemplates failed: $e');
      return const [];
    }
  }

  /// Publish a personal gym routine into a club-owned template. The
  /// publish_gym_routine_as_template RPC is author + club-admin gated and
  /// deep-copies the routine + exercises + sets server-side (the personal
  /// original is left untouched). Returns the new club-owned routine's id.
  Future<String> publishGymRoutineAsTemplate({
    required String routineId,
    required String clubId,
  }) async {
    final newId = await _client.rpc(
      'publish_gym_routine_as_template',
      params: {'p_routine_id': routineId, 'p_club_id': clubId},
    );
    return newId as String;
  }

  /// Adopt a club gym-routine template into a new personal routine via the
  /// clone_gym_routine_template RPC (author-or-member gated, rate-limited
  /// server-side). Returns the new personal routine's id.
  Future<String> cloneGymRoutineTemplate(String templateId) async {
    final newId = await _client.rpc(
      'clone_gym_routine_template',
      params: {'p_template_id': templateId},
    );
    return newId as String;
  }

  /// Browse the public gym-routine library — routines published as public
  /// templates that any signed-in user can adopt (migration 20270224_001).
  /// Optional case-insensitive title search. Each entry carries the author's
  /// public display name (handle) joined from user_profiles; no other author
  /// data is exposed. Mirrors web `data.ts#fetchPublicGymRoutineLibrary`.
  Future<List<({GymRoutineRow routine, String? authorHandle})>>
      fetchPublicGymRoutineLibrary({String query = ''}) async {
    // public_gym_routines redacts external_id + last_modified_at (migration
    // 20270319_001); created_at stands in for the model's required field.
    var sel = _client.from('public_gym_routines').select();
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      sel = sel.ilike(GymRoutineRow.colTitle, '%$trimmed%');
    }
    final rows = await sel
        .order(GymRoutineRow.colCreatedAt, ascending: false)
        .limit(100);
    final routines = (rows as List)
        .cast<Map<String, dynamic>>()
        .map((r) => GymRoutineRow.fromJson({
              ...r,
              GymRoutineRow.colLastModifiedAt: r[GymRoutineRow.colCreatedAt],
            }))
        .toList();
    final authorIds = {for (final r in routines) r.authorId}.toList();
    final byId = <String, String?>{};
    if (authorIds.isNotEmpty) {
      final profiles = await _client
          .from('user_profiles')
          .select('id, display_name')
          .inFilter('id', authorIds);
      for (final p in profiles as List) {
        final m = p as Map<String, dynamic>;
        byId[m['id'] as String] = m['display_name'] as String?;
      }
    }
    return [
      for (final r in routines)
        (routine: r, authorHandle: byId[r.authorId]),
    ];
  }

  /// Publish (or unpublish) a personal gym routine to/from the public library.
  /// The set_gym_routine_public RPC is author-gated + refuses a club-owned
  /// routine server-side; publishing flips is_public_template on the routine
  /// itself (the routine IS the template — no deep-copy). Mirrors web
  /// `data.ts#setGymRoutinePublic`.
  Future<void> setGymRoutinePublic({
    required String routineId,
    required bool isPublic,
  }) async {
    await _client.rpc(
      'set_gym_routine_public',
      params: {'p_routine_id': routineId, 'p_public': isPublic},
    );
  }

  // ─────────────────── Nutrition / food log (Phase 4) ───────────────────

  /// Food entries in the half-open day range [from, to), newest first.
  Future<List<FoodLogRow>> fetchFoodLog({
    required DateTime from,
    required DateTime to,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return [];
    final data = await _client
        .from(FoodLogRow.table)
        .select()
        .eq(FoodLogRow.colUserId, uid)
        .gte(FoodLogRow.colStartedAt, from.toIso8601String())
        .lt(FoodLogRow.colStartedAt, to.toIso8601String())
        .order(FoodLogRow.colStartedAt, ascending: false);
    return (data as List)
        .map((r) => FoodLogRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Log one food item. Client may mint [id] (offline-create), same id
  /// semantics as [createGymWorkout].
  Future<FoodLogRow> logFood({
    String? id,
    required DateTime startedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    bool isPublic = false,
    String? externalId,
    DateTime? lastModifiedAt,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final row = await _client
        .from(FoodLogRow.table)
        .insert({
          if (id != null) FoodLogRow.colId: id,
          FoodLogRow.colUserId: uid,
          FoodLogRow.colStartedAt: startedAt.toIso8601String(),
          FoodLogRow.colItemName: itemName,
          FoodLogRow.colMealSlot: mealSlot,
          FoodLogRow.colCalories: calories,
          FoodLogRow.colProteinG: proteinG,
          FoodLogRow.colCarbsG: carbsG,
          FoodLogRow.colFatG: fatG,
          FoodLogRow.colIsPublic: isPublic,
          FoodLogRow.colExternalId: externalId,
          if (lastModifiedAt != null)
            FoodLogRow.colLastModifiedAt: lastModifiedAt.toIso8601String(),
        })
        .select()
        .single();
    return FoodLogRow.fromJson(row);
  }

  /// Patch a food entry. Stamps `last_modified_at` for newer-wins sync.
  Future<void> updateFoodLog(
    String id, {
    String? itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    bool? isPublic,
    DateTime? lastModifiedAt,
  }) async {
    final patch = <String, dynamic>{
      FoodLogRow.colLastModifiedAt:
          (lastModifiedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    if (itemName != null) patch[FoodLogRow.colItemName] = itemName;
    if (mealSlot != null) patch[FoodLogRow.colMealSlot] = mealSlot;
    if (calories != null) patch[FoodLogRow.colCalories] = calories;
    if (proteinG != null) patch[FoodLogRow.colProteinG] = proteinG;
    if (carbsG != null) patch[FoodLogRow.colCarbsG] = carbsG;
    if (fatG != null) patch[FoodLogRow.colFatG] = fatG;
    if (isPublic != null) patch[FoodLogRow.colIsPublic] = isPublic;
    await _client.from(FoodLogRow.table).update(patch).eq(FoodLogRow.colId, id);
  }

  Future<void> deleteFoodLog(String id) async {
    await _client.from(FoodLogRow.table).delete().eq(FoodLogRow.colId, id);
  }

  // ─────────────────── Meal templates (multi_modal.md mid tier) ───────────
  //
  // Saved meals logged with one tap: meal_templates parent + meal_template_items
  // (migration 20270218_001, owner-scoped RLS). last_modified_at + item_count
  // are client-stamped (newer-wins sync, non-authoritative count — no server
  // trigger), mirroring food_log + gym_routines. A template is NOT a dated
  // activity, so it never feeds the activities view. Mirrors web core/data.ts
  // (fetchMealTemplates / fetchMealTemplateDetail / createMealTemplate /
  // deleteMealTemplate).

  /// Saved meal templates for the signed-in user, most-recently-modified first.
  Future<List<MealTemplateRow>> fetchMealTemplates({int limit = 100}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final data = await _client
        .from(MealTemplateRow.table)
        .select()
        .eq(MealTemplateRow.colUserId, uid)
        .order(MealTemplateRow.colLastModifiedAt, ascending: false)
        .limit(limit);
    return (data as List)
        .map((r) => MealTemplateRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// A single template with its items (by position). Null when the id doesn't
  /// resolve (RLS hides others').
  Future<({MealTemplateRow template, List<MealTemplateItemRow> items})?>
      fetchMealTemplateDetail(String id) async {
    final t = await _client
        .from(MealTemplateRow.table)
        .select()
        .eq(MealTemplateRow.colId, id)
        .maybeSingle();
    if (t == null) return null;
    final template = MealTemplateRow.fromJson(t);
    final itemRows = await _client
        .from(MealTemplateItemRow.table)
        .select()
        .eq(MealTemplateItemRow.colTemplateId, id)
        .order(MealTemplateItemRow.colPosition, ascending: true);
    final items = (itemRows as List)
        .map((r) => MealTemplateItemRow.fromJson(r as Map<String, dynamic>))
        .toList();
    return (template: template, items: items);
  }

  /// Insert a template + its items. Blank-named items are dropped. item_count is
  /// stamped client-side from the surviving item list (non-authoritative cache).
  /// The caller may mint [id] (offline-create path) — `meal_templates.id`
  /// accepts a client value, so the local id IS the server id (no
  /// reconciliation), matching the gym/gear/food pattern.
  Future<MealTemplateRow> createMealTemplate({
    String? id,
    required String name,
    String? mealSlot,
    DateTime? lastModifiedAt,
    List<MealTemplateItemInput> items = const [],
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final kept =
        items.where((it) => it.itemName.trim().isNotEmpty).toList(growable: false);
    final row = await _client
        .from(MealTemplateRow.table)
        .insert({
          if (id != null) MealTemplateRow.colId: id,
          MealTemplateRow.colUserId: uid,
          MealTemplateRow.colName: name.trim(),
          MealTemplateRow.colMealSlot: mealSlot,
          MealTemplateRow.colItemCount: kept.length,
          if (lastModifiedAt != null)
            MealTemplateRow.colLastModifiedAt: lastModifiedAt.toIso8601String(),
        })
        .select()
        .single();
    final template = MealTemplateRow.fromJson(row);
    if (kept.isNotEmpty) {
      await _client.from(MealTemplateItemRow.table).insert([
        for (var i = 0; i < kept.length; i++)
          {
            MealTemplateItemRow.colTemplateId: template.id,
            MealTemplateItemRow.colPosition: i,
            MealTemplateItemRow.colItemName: kept[i].itemName.trim(),
            MealTemplateItemRow.colMealSlot: kept[i].mealSlot,
            MealTemplateItemRow.colCalories: kept[i].calories,
            MealTemplateItemRow.colProteinG: kept[i].proteinG,
            MealTemplateItemRow.colCarbsG: kept[i].carbsG,
            MealTemplateItemRow.colFatG: kept[i].fatG,
            MealTemplateItemRow.colExternalId: kept[i].externalId,
          },
      ]);
    }
    return template;
  }

  /// Delete a template; its items cascade via FK (migration 20270218_001).
  /// Logged food_log entries are untouched (the template is a parallel plan,
  /// never linked to the entries it spawned).
  Future<void> deleteMealTemplate(String id) async {
    await _client
        .from(MealTemplateRow.table)
        .delete()
        .eq(MealTemplateRow.colId, id);
  }

  // ─────────────────── Recipes (multi_modal.md mid tier) ──────────────────
  //
  // N ingredients summed into one logged meal (migration 20270221_001,
  // owner-scoped RLS). Sibling of meal templates: same reusable-plan shape, but
  // logging a recipe sums its ingredients into ONE food_log entry (per-serving
  // combined macros) rather than one entry per item — see the recipe.dart
  // parity pair. last_modified_at + ingredient_count are client-stamped. A
  // recipe is NOT a dated activity, so it never feeds the activities view.

  /// Saved recipes for the signed-in user, most-recently-modified first.
  Future<List<RecipeRow>> fetchRecipes({int limit = 100}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final data = await _client
        .from(RecipeRow.table)
        .select()
        .eq(RecipeRow.colUserId, uid)
        .order(RecipeRow.colLastModifiedAt, ascending: false)
        .limit(limit);
    return (data as List)
        .map((r) => RecipeRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// A single recipe with its ingredients (by position). Null when the id
  /// doesn't resolve (RLS hides others').
  Future<({RecipeRow recipe, List<RecipeIngredientRow> ingredients})?>
      fetchRecipeDetail(String id) async {
    final r = await _client
        .from(RecipeRow.table)
        .select()
        .eq(RecipeRow.colId, id)
        .maybeSingle();
    if (r == null) return null;
    final recipe = RecipeRow.fromJson(r);
    final ingredientRows = await _client
        .from(RecipeIngredientRow.table)
        .select()
        .eq(RecipeIngredientRow.colRecipeId, id)
        .order(RecipeIngredientRow.colPosition, ascending: true);
    final ingredients = (ingredientRows as List)
        .map((r) => RecipeIngredientRow.fromJson(r as Map<String, dynamic>))
        .toList();
    return (recipe: recipe, ingredients: ingredients);
  }

  /// Insert a recipe + its ingredients. Blank-named ingredients are dropped;
  /// ingredient_count is stamped client-side from the survivors. The caller may
  /// mint [id] (offline-create path) — `recipes.id` accepts a client value, so
  /// the local id IS the server id, matching the meal-template/gym/food pattern.
  Future<RecipeRow> createRecipe({
    String? id,
    required String name,
    double servings = 1,
    String? mealSlot,
    DateTime? lastModifiedAt,
    List<RecipeIngredientInput> ingredients = const [],
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    final kept = ingredients
        .where((it) => it.itemName.trim().isNotEmpty)
        .toList(growable: false);
    final row = await _client
        .from(RecipeRow.table)
        .insert({
          if (id != null) RecipeRow.colId: id,
          RecipeRow.colUserId: uid,
          RecipeRow.colName: name.trim(),
          RecipeRow.colServings: servings >= 1 ? servings : 1,
          RecipeRow.colMealSlot: mealSlot,
          RecipeRow.colIngredientCount: kept.length,
          if (lastModifiedAt != null)
            RecipeRow.colLastModifiedAt: lastModifiedAt.toIso8601String(),
        })
        .select()
        .single();
    final recipe = RecipeRow.fromJson(row);
    if (kept.isNotEmpty) {
      await _client.from(RecipeIngredientRow.table).insert([
        for (var i = 0; i < kept.length; i++)
          {
            RecipeIngredientRow.colRecipeId: recipe.id,
            RecipeIngredientRow.colPosition: i,
            RecipeIngredientRow.colItemName: kept[i].itemName.trim(),
            RecipeIngredientRow.colQuantity:
                kept[i].quantity >= 0 ? kept[i].quantity : 1,
            RecipeIngredientRow.colCalories: kept[i].calories,
            RecipeIngredientRow.colProteinG: kept[i].proteinG,
            RecipeIngredientRow.colCarbsG: kept[i].carbsG,
            RecipeIngredientRow.colFatG: kept[i].fatG,
            RecipeIngredientRow.colExternalId: kept[i].externalId,
          },
      ]);
    }
    return recipe;
  }

  /// Delete a recipe; its ingredients cascade via FK (migration 20270221_001).
  /// Logged food_log entries are untouched (the recipe is a parallel plan).
  Future<void> deleteRecipe(String id) async {
    await _client.from(RecipeRow.table).delete().eq(RecipeRow.colId, id);
  }

  /// Insert many food_log rows in one round-trip. Used by the one-tap
  /// "log a meal template" path (each template item becomes a food_log entry).
  Future<void> logFoodBatch(List<FoodLogInput> entries) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');
    if (entries.isEmpty) return;
    final now = DateTime.now().toUtc();
    await _client.from(FoodLogRow.table).insert([
      for (final e in entries)
        {
          if (e.id != null) FoodLogRow.colId: e.id,
          FoodLogRow.colUserId: uid,
          FoodLogRow.colStartedAt:
              (e.startedAt ?? now).toIso8601String(),
          FoodLogRow.colItemName: e.itemName,
          FoodLogRow.colMealSlot: e.mealSlot,
          FoodLogRow.colCalories: e.calories,
          FoodLogRow.colProteinG: e.proteinG,
          FoodLogRow.colCarbsG: e.carbsG,
          FoodLogRow.colFatG: e.fatG,
          FoodLogRow.colExternalId: e.externalId,
          FoodLogRow.colLastModifiedAt: now.toIso8601String(),
        },
    ]);
  }

  /// The signed-in user's most recent recorded weight (kg), or null when
  /// none. Owner-only — `body_metrics` has no public-read policy (migration
  /// 20261216_001). Feeds the nutrition BMR target.
  Future<double?> fetchLatestBodyWeightKg() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final data = await _client
        .from(BodyMetricRow.table)
        .select(BodyMetricRow.colWeightKg)
        .eq(BodyMetricRow.colUserId, uid)
        .order(BodyMetricRow.colRecordedAt, ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return (data[BodyMetricRow.colWeightKg] as num?)?.toDouble();
  }

  /// Read the trigger-maintained `personal_records` cache for the signed-in
  /// user (fastest time per distance bracket, embedded best efforts within
  /// longer runs, DNF-excluded). Mirrors web's `fetchPersonalRecords` — the
  /// authoritative all-history source, so the mobile dashboard no longer
  /// recomputes bests from whatever GPS tracks happen to be resident (which
  /// also missed cloud-synced runs whose track lives only in Storage). The
  /// cache is RLS-scoped to the caller; the explicit `user_id` filter is
  /// defence-in-depth, matching the other personal-data reads. Newest brackets
  /// first per the canonical order; returns [] when signed out or empty.
  Future<List<PersonalRecordRow>> fetchPersonalRecords() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final data = await _client
        .from(PersonalRecordRow.table)
        .select()
        .eq(PersonalRecordRow.colUserId, uid);
    return data
        .map<PersonalRecordRow>((r) => PersonalRecordRow.fromJson(r))
        .toList();
  }

  /// Record the GDPR Art 9(2)(a) health-data consent for the signed-in user
  /// via the `grant_health_data_consent()` SECURITY DEFINER RPC — the only
  /// sanctioned writer of `health_data_consent_at` (first-stamp-wins,
  /// server `now()`, insert-or-update since 20270418_001 so a grant before
  /// the profile bootstrap still lands; direct end-user writes setting it
  /// to a non-null value are blocked by the `lock_consent_columns`
  /// trigger, migration 20261118_001). Gate any height / weight write
  /// behind this. Returns the effective (original-if-already-set)
  /// timestamp.
  Future<DateTime?> grantHealthDataConsent() async {
    if (_client.auth.currentUser?.id == null) {
      throw StateError('not signed in');
    }
    final res = await _client.rpc('grant_health_data_consent');
    if (res is! String) return null;
    return DateTime.tryParse(res);
  }

  /// Withdraw health-data consent (GDPR Art 7(3)) via the
  /// `withdraw_health_data_consent()` SECURITY DEFINER RPC — the
  /// sanctioned inverse of [grantHealthDataConsent] (migration
  /// 20270418_001). One transaction nulls the consent stamp + every
  /// Art 9 profile column (height, gender, DOB) and erases the
  /// `body_metrics` weight series. Server-side insert-or-update, so a
  /// missing client-provisioned profile row can't turn the withdrawal
  /// into a 0-row silent no-op; throws on a missing session for the
  /// same reason.
  Future<void> withdrawHealthDataConsent() async {
    if (_client.auth.currentUser?.id == null) {
      throw StateError('not signed in');
    }
    await _client.rpc('withdraw_health_data_consent');
  }

  /// Set (or clear, when null) the signed-in user's height in centimetres
  /// on `user_profiles`. Special-category health data — the caller must have
  /// recorded consent via [grantHealthDataConsent] first. Feeds the
  /// nutrition BMR target ([fetchMyProfile] reads it back).
  /// Row-count-verified: `user_profiles` rows are client-provisioned, so
  /// a plain update against a missing row matches 0 rows and reports
  /// success — the save silently vanishes (issue #233). An upsert can't
  /// close this from the client (PostgREST's ON CONFLICT reads
  /// `excluded.<col>`, needing SELECT on the revoked health columns), so
  /// verify the update landed and insert the row when it didn't.
  Future<void> setMyHeightCm(double? heightCm) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('not signed in');
    final updated = await _client
        .from('user_profiles')
        .update({UserProfileRow.colHeightCm: heightCm})
        .eq(UserProfileRow.colId, uid)
        .select(UserProfileRow.colId);
    if (updated.isEmpty) {
      await _client.from('user_profiles').insert({
        UserProfileRow.colId: uid,
        UserProfileRow.colHeightCm: heightCm,
      });
    }
  }

  /// Append a weight measurement (kg) to the `body_metrics` time-series —
  /// one row per recording, so the series is the history. Owner-only
  /// (no public-read policy). The caller gates on health-data consent.
  Future<void> recordBodyWeightKg(double weightKg) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('not signed in');
    await _client.from(BodyMetricRow.table).insert({
      BodyMetricRow.colUserId: uid,
      BodyMetricRow.colWeightKg: weightKg,
    });
  }

  // ──────────────────── Coach-athlete roster (persona #46) ────────────────
  //
  // Mirror of the web coaching data layer (apps/web/src/lib/core/data.ts):
  // a coach mints a shareable invite token (createCoachInvite); the athlete
  // redeems it (redeemCoachInvite -> redeem_coach_invite RPC) to form an
  // active link. RLS scopes every read/write to the two parties; profiles
  // are joined in a second query, mirroring the followers/following fetches.

  /// Mint a pending invite. The token is client-generated; only the coach
  /// can read their own pending rows (RLS). Returns the token so the caller
  /// can build the `/coaching/accept/<token>` share link.
  Future<String> createCoachInvite({String? note}) async {
    final uid = userId;
    if (uid == null) throw Exception('Not authenticated');
    // 128 bits of secure randomness as 32 hex chars — same shape as web's
    // crypto.randomUUID().replace(/-/g, '') invite token, without adding a
    // uuid dependency to this package.
    final rng = Random.secure();
    final token =
        List.generate(32, (_) => rng.nextInt(16).toRadixString(16)).join();
    await _client.from(CoachAthleteRow.table).insert({
      CoachAthleteRow.colCoachId: uid,
      CoachAthleteRow.colStatus: 'pending',
      CoachAthleteRow.colInviteToken: token,
      CoachAthleteRow.colNote: note?.trim().isEmpty ?? true ? null : note!.trim(),
    });
    return token;
  }

  /// Active athletes on the signed-in coach's roster, newest acceptance first.
  Future<List<CoachAthleteLink>> fetchMyAthletes() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _client
        .from(CoachAthleteRow.table)
        .select('id, status, note, created_at, accepted_at, athlete_id')
        .eq(CoachAthleteRow.colCoachId, uid)
        .eq(CoachAthleteRow.colStatus, 'active')
        .order(CoachAthleteRow.colAcceptedAt, ascending: false);
    return _linksWithProfiles(
        (rows as List).cast<Map<String, dynamic>>(), CoachAthleteRow.colAthleteId);
  }

  /// Active coaches the signed-in athlete is linked to, newest first.
  Future<List<CoachAthleteLink>> fetchMyCoaches() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _client
        .from(CoachAthleteRow.table)
        .select('id, status, note, created_at, accepted_at, coach_id')
        .eq(CoachAthleteRow.colAthleteId, uid)
        .eq(CoachAthleteRow.colStatus, 'active')
        .order(CoachAthleteRow.colAcceptedAt, ascending: false);
    return _linksWithProfiles(
        (rows as List).cast<Map<String, dynamic>>(), CoachAthleteRow.colCoachId);
  }

  /// The whole coach roster in one consent-gated round-trip
  /// (coach_roster.md). Calls the SECURITY DEFINER `coach_roster_summary` RPC,
  /// which re-checks the active link per athlete inside its body — a non-coach
  /// gets zero rows, an unauthenticated caller raises. Returns no track bytes.
  Future<List<CoachRosterRow>> fetchCoachRosterSummary() async {
    if (userId == null) return const [];
    final data = await _client.rpc('coach_roster_summary');
    return (data as List).cast<Map<String, dynamic>>().map((r) {
      return CoachRosterRow(
        athleteId: r['athlete_id'] as String,
        displayName: r['display_name'] as String?,
        avatarUrl: r['avatar_url'] as String?,
        lastRunAt: r['last_run_at'] == null
            ? null
            : DateTime.parse(r['last_run_at'] as String),
        runs7d: (r['runs_7d'] as num?)?.toInt() ?? 0,
        distance7dM: (r['distance_7d_m'] as num?)?.toDouble() ?? 0,
        loadAcute: (r['load_acute'] as num?)?.toDouble() ?? 0,
        loadChronic: (r['load_chronic'] as num?)?.toDouble() ?? 0,
        activePlanId: r['active_plan_id'] as String?,
        planCompletionPct: (r['plan_completion_pct'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  Future<List<CoachAthleteLink>> _linksWithProfiles(
      List<Map<String, dynamic>> rows, String otherIdCol) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((r) => r[otherIdCol] as String).toSet().toList();
    final profiles = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter(UserProfileRow.colId, ids);
    final byId = <String, ({String? displayName, String? avatarUrl})>{};
    for (final p in (profiles as List).cast<Map<String, dynamic>>()) {
      byId[p['id'] as String] = (
        displayName: p['display_name'] as String?,
        avatarUrl: p['avatar_url'] as String?,
      );
    }
    return rows.map((r) {
      final otherId = r[otherIdCol] as String;
      final prof = byId[otherId];
      return CoachAthleteLink(
        id: r['id'] as String,
        status: r['status'] as String,
        note: r['note'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
        acceptedAt: r['accepted_at'] == null
            ? null
            : DateTime.parse(r['accepted_at'] as String),
        userId: otherId,
        displayName: prof?.displayName,
        avatarUrl: prof?.avatarUrl,
      );
    }).toList();
  }

  /// Unredeemed invites the signed-in coach has minted, newest first.
  Future<List<PendingCoachInvite>> fetchPendingCoachInvites() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _client
        .from(CoachAthleteRow.table)
        .select('id, invite_token, note, created_at')
        .eq(CoachAthleteRow.colCoachId, uid)
        .eq(CoachAthleteRow.colStatus, 'pending')
        .isFilter(CoachAthleteRow.colAthleteId, null)
        .order(CoachAthleteRow.colCreatedAt, ascending: false);
    return (rows as List).cast<Map<String, dynamic>>().map((r) {
      return PendingCoachInvite(
        id: r['id'] as String,
        inviteToken: r['invite_token'] as String,
        note: r['note'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );
    }).toList();
  }

  /// Redeem an invite token. Returns the coach's user id. Throws the RPC's
  /// raise text (e.g. an expired or already-redeemed token).
  Future<String> redeemCoachInvite(String token) async {
    final res = await _client.rpc('redeem_coach_invite', params: {'token': token});
    return res as String;
  }

  /// End an active link (either party may call). Goes through the
  /// `end_coach_link` RPC, not a direct UPDATE — `coach_athletes` has no
  /// client UPDATE policy, so a coach can't reassign athlete_id to forge a
  /// link. Soft-ends via status so the row survives for audit.
  Future<void> endCoachLink(String id) async {
    await _client.rpc('end_coach_link', params: {'p_id': id});
  }

  /// Revoke (hard-delete) an unredeemed invite. RLS only permits this on the
  /// coach's own pending, athlete-less rows.
  Future<void> revokeCoachInvite(String id) async {
    await _client.from(CoachAthleteRow.table).delete().eq(CoachAthleteRow.colId, id);
  }

  /// One athlete's recent runs for the coach review surface. The RLS policy
  /// `active coach reads athlete runs` (migration 20261103_001) grants a
  /// `status='active'` coach SELECT on the athlete's run rows — public AND
  /// private — straight off the base table, so the `user_id` filter here is
  /// the *athlete*. Column-narrowed: no track download (the raw GPS trace
  /// stays owner-only — decisions § 98). Returns [] when the caller isn't an
  /// active coach (RLS simply yields zero rows).
  Future<List<AthleteRunSummary>> fetchAthleteRuns(String athleteId,
      {int limit = 20}) async {
    if (userId == null || athleteId.isEmpty) return const [];
    final data = await _client
        .from(RunRow.table)
        .select(
            'id, started_at, distance_m, duration_s, is_public, source, route_id, activity_type, metadata')
        .eq(RunRow.colUserId, athleteId)
        .order(RunRow.colStartedAt, ascending: false)
        .limit(limit);
    return (data as List).cast<Map<String, dynamic>>().map((r) {
      return AthleteRunSummary(
        id: r['id'] as String,
        startedAt: DateTime.parse(r['started_at'] as String),
        distanceM: ((r['distance_m'] as num?) ?? 0).toDouble(),
        durationS: ((r['duration_s'] as num?) ?? 0).toInt(),
        isPublic: (r['is_public'] as bool?) ?? false,
        source: r['source'] as String?,
        routeId: r['route_id'] as String?,
        activityType: (r['activity_type'] as String?) ?? 'run',
        metadata: r['metadata'] as Map<String, dynamic>?,
      );
    }).toList();
  }

  /// The athlete's active training plan + its weeks/workouts for the coach
  /// review surface. Mirrors web `fetchAthletePlanOverview` — the coach
  /// plan-read policies (migration 20261116_001) grant SELECT on
  /// `training_plans` / `plan_weeks` / `plan_workouts` for active-linked
  /// athletes. Null when the athlete has no active plan, or the caller isn't
  /// their active coach (RLS yields no rows). `completionPct` excludes rest
  /// days, matching the web roll-up.
  Future<AthletePlanOverview?> fetchAthletePlanOverview(String athleteId) async {
    if (userId == null || athleteId.isEmpty) return null;
    final planRow = await _client
        .from(TrainingPlanRow.table)
        .select()
        .eq(TrainingPlanRow.colUserId, athleteId)
        .eq('status', 'active')
        .maybeSingle();
    if (planRow == null) return null;
    final plan = TrainingPlanRow.fromJson(planRow);
    final weekRows = await _client
        .from(PlanWeekRow.table)
        .select()
        .eq(PlanWeekRow.colPlanId, plan.id)
        .order(PlanWeekRow.colWeekIndex, ascending: true);
    final weeks = (weekRows as List)
        .cast<Map<String, dynamic>>()
        .map(PlanWeekRow.fromJson)
        .toList();
    var workouts = <PlanWorkoutRow>[];
    if (weeks.isNotEmpty) {
      final woRows = await _client
          .from(PlanWorkoutRow.table)
          .select()
          .inFilter(PlanWorkoutRow.colWeekId, [for (final w in weeks) w.id])
          .order(PlanWorkoutRow.colScheduledDate, ascending: true);
      workouts = (woRows as List)
          .cast<Map<String, dynamic>>()
          .map(PlanWorkoutRow.fromJson)
          .toList();
    }
    final real = workouts.where((w) => w.kind != 'rest').toList();
    final done = real
        .where((w) => w.manuallyCompleted == true || w.completedRunId != null)
        .length;
    final pct = real.isEmpty ? 0 : (100 * done / real.length).round();
    return AthletePlanOverview(
      plan: plan,
      weeks: weeks,
      workouts: workouts,
      completionPct: pct,
    );
  }

  /// Training plans owned by the signed-in coach, newest first — the source
  /// plans the assign control offers. Mirrors web `fetchMyPlans`.
  Future<List<TrainingPlanRow>> fetchMyPlans({int limit = 100}) async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _client
        .from(TrainingPlanRow.table)
        .select()
        .eq(TrainingPlanRow.colUserId, uid)
        .order(TrainingPlanRow.colCreatedAt, ascending: false)
        .limit(limit);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(TrainingPlanRow.fromJson)
        .toList();
  }

  /// Assign one of the coach's plans to a linked athlete via the
  /// `assign_plan_to_athlete` RPC (migration 20270106_001). The thrown error
  /// carries the RPC's raise text (e.g. the athlete already has an active
  /// plan), which the caller surfaces. Returns the new plan id.
  Future<String> assignPlanToAthlete({
    required String sourcePlanId,
    required String athleteId,
    required DateTime startDate,
    String? Function(DateTime)? toIso,
  }) async {
    try {
      final res = await _client.rpc('assign_plan_to_athlete', params: {
        'p_source_plan_id': sourcePlanId,
        'p_athlete_id': athleteId,
        'p_start_date': (toIso ?? _isoDate)(startDate),
      });
      return res as String;
    } on PostgrestException catch (e) {
      // Surface the RPC's RAISE text verbatim (e.g. "athlete already has an
      // active plan") rather than the noisy PostgrestException.toString(), so
      // the caller can show it directly without re-parsing the SQLSTATE.
      throw Exception(e.message);
    }
  }

  // --- Achievements / badges ---
  // Reads go through RLS: the owner sees all of their rows, a non-owner sees
  // only is_public = true (the achievements_public_select policy). Awards are
  // written only by the SECURITY DEFINER award function — no client path.

  /// A profile's badges, newest first. RLS returns all rows for the owner and
  /// only public rows for anyone else. Mirrors web `fetchUserBadges`.
  Future<List<AchievementRow>> fetchUserBadges(String userId) async {
    final data = await _client
        .from(AchievementRow.table)
        .select()
        .eq(AchievementRow.colUserId, userId)
        .order(AchievementRow.colEarnedAt, ascending: false);
    return data
        .map<AchievementRow>((row) => AchievementRow.fromJson(row))
        .toList();
  }

  /// The signed-in user's own badges (incl. private). Empty when signed out.
  Future<List<AchievementRow>> fetchMyBadges() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    return fetchUserBadges(uid);
  }

  /// Public badge awards from people the viewer follows, cursor-paged over
  /// (earned_at, id) like the run feed. Public rows only (RLS), newest first.
  /// Mirrors web `fetchFollowingBadgeAwards`.
  Future<List<BadgeAwardEntry>> fetchFollowingBadgeAwards({
    int limit = 20,
    ({DateTime earnedAt, String id})? cursor,
  }) async {
    final viewerId = _client.auth.currentUser?.id;
    if (viewerId == null) return const [];

    final edges = await _client
        .from(UserFollowRow.table)
        .select(UserFollowRow.colFolloweeId)
        .eq(UserFollowRow.colFollowerId, viewerId);
    final authors = edges
        .map<String>((e) => e[UserFollowRow.colFolloweeId] as String)
        .toList();
    if (authors.isEmpty) return const [];

    var q = _client
        .from(AchievementRow.table)
        .select()
        .inFilter(AchievementRow.colUserId, authors)
        .eq(AchievementRow.colIsPublic, true);
    if (cursor != null) {
      final iso = cursor.earnedAt.toIso8601String();
      q = q.or(
        'earned_at.lt.$iso,and(earned_at.eq.$iso,id.lt.${cursor.id})',
      );
    }
    final rows = await q
        .order(AchievementRow.colEarnedAt, ascending: false)
        .order(AchievementRow.colId, ascending: false)
        .limit(limit);
    if (rows.isEmpty) return const [];

    final badges =
        rows.map<AchievementRow>((r) => AchievementRow.fromJson(r)).toList();
    final ids = badges.map((b) => b.userId).toSet().toList();
    final profiles = await _client
        .from(UserProfileRow.table)
        .select('id, display_name, avatar_url')
        .inFilter('id', ids);
    final byId = <String, Map<String, dynamic>>{
      for (final p in profiles) p['id'] as String: p,
    };
    return [
      for (final b in badges)
        BadgeAwardEntry(
          badge: b,
          authorId: b.userId,
          authorName: byId[b.userId]?['display_name'] as String?,
          authorAvatarUrl: byId[b.userId]?['avatar_url'] as String?,
        ),
    ];
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// One photo in an event's multi-attendee gallery (#49) — the mobile
/// mirror of web's `EventPhoto` (a `RunPhoto` MINUS `run_id`, PLUS the
/// uploader's display name). `run_id` is intentionally absent so a
/// private run's UUID never reaches an event viewer who can't see it.
class EventPhotoView {
  final String id;
  final String ownerId;
  final String storagePath;
  final String? thumb512Path;
  final String? caption;
  final int positionIdx;
  final DateTime createdAt;
  final String? uploaderName;

  const EventPhotoView({
    required this.id,
    required this.ownerId,
    required this.storagePath,
    this.thumb512Path,
    this.caption,
    required this.positionIdx,
    required this.createdAt,
    this.uploaderName,
  });

  factory EventPhotoView.fromJson(
    Map<String, dynamic> json,
    String? uploaderName,
  ) =>
      EventPhotoView(
        id: json['id'] as String,
        ownerId: json['owner_id'] as String,
        storagePath: json['storage_path'] as String,
        thumb512Path: json['thumb_512_path'] as String?,
        caption: json['caption'] as String?,
        positionIdx: (json['position_idx'] as num).toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
        uploaderName: uploaderName,
      );
}

/// One athlete on a coach's roster, or one coach on an athlete's list — the
/// mirror of web's `CoachAthleteLink`. `userId` is whichever party is *not*
/// the viewer (the athlete for a coach's roster, the coach for an athlete's
/// list).
class CoachAthleteLink {
  final String id;
  final String status;
  final String? note;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final String userId;
  final String? displayName;
  final String? avatarUrl;

  const CoachAthleteLink({
    required this.id,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.acceptedAt,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });
}

/// One row of the multi-athlete coach roster (coach_roster.md) — the bespoke
/// `coach_roster_summary` RPC projection, mirror of web's `CoachRosterRow`.
/// loadAcute / loadChronic are RAW distance-proxy stress sums; the UI derives
/// the ACWR risk band + load trend from them via the coach_load helper.
class CoachRosterRow {
  final String athleteId;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? lastRunAt;
  final int runs7d;
  final double distance7dM;
  final double loadAcute;
  final double loadChronic;
  final String? activePlanId;
  final int planCompletionPct;

  const CoachRosterRow({
    required this.athleteId,
    required this.displayName,
    required this.avatarUrl,
    required this.lastRunAt,
    required this.runs7d,
    required this.distance7dM,
    required this.loadAcute,
    required this.loadChronic,
    required this.activePlanId,
    required this.planCompletionPct,
  });
}

/// An unredeemed coach invite — mirror of web's `PendingCoachInvite`.
class PendingCoachInvite {
  final String id;
  final String inviteToken;
  final String? note;
  final DateTime createdAt;

  const PendingCoachInvite({
    required this.id,
    required this.inviteToken,
    required this.note,
    required this.createdAt,
  });
}

/// One of an athlete's recent runs on the coach review surface — mirror of
/// web's `AthleteRunSummary`. Column-narrowed: no track.
class AthleteRunSummary {
  final String id;
  final DateTime startedAt;
  final double distanceM;
  final int durationS;
  final bool isPublic;
  final String? source;
  final String? routeId;
  final String activityType;
  final Map<String, dynamic>? metadata;

  const AthleteRunSummary({
    required this.id,
    required this.startedAt,
    required this.distanceM,
    required this.durationS,
    required this.isPublic,
    required this.source,
    required this.routeId,
    required this.activityType,
    required this.metadata,
  });
}

/// An athlete's active plan + weeks/workouts + completion percentage for the
/// coach review surface — mirror of web's `ActivePlanOverview` (scoped to the
/// athlete, with no `todayWorkout` — the coach surface shows a window, not a
/// today card).
class AthletePlanOverview {
  final TrainingPlanRow plan;
  final List<PlanWeekRow> weeks;
  final List<PlanWorkoutRow> workouts;
  final int completionPct;

  const AthletePlanOverview({
    required this.plan,
    required this.weeks,
    required this.workouts,
    required this.completionPct,
  });
}

/// One set in a [ApiClient.createGymWorkout] / `updateGymWorkout` call,
/// before it has a server id or set_index (those are assigned on insert).
typedef GymSetInput = ({
  String exerciseName,
  int? reps,
  double? weightKg,
  double? rpe,
  // Role this set played (warmup/working/dropset/amrap/failure/backoff);
  // null defaults to 'working' at write time (migration 20270224_001).
  String? setType,
  int? durationS,
  // Optional link to a public.exercises catalogue entry (migration
  // 20270222_001). null for a free-text set — the default offline path.
  String? exerciseId,
});

/// One planned set in a [ApiClient.createGymRoutine] call (targets only).
/// `set_index` is assigned positionally on insert. A single rep target lives
/// in [targetRepsMin] with [targetRepsMax] null. [setType] defaults to
/// 'working' server-side; [restS] / [targetDurationS] / [targetDistanceM]
/// carry the P2 set-type / rest / modality targets.
typedef GymRoutineSetInput = ({
  String? setType,
  int? targetRepsMin,
  int? targetRepsMax,
  double? targetWeightKg,
  double? targetRpe,
  num? restS,
  int? targetDurationS,
  double? targetDistanceM,
});

/// One planned exercise in a [ApiClient.createGymRoutine] call. [exerciseKey]
/// is `normaliseExerciseName(exerciseName)` stamped at write time (the frozen
/// identity that binds the plan to logged sets). `position` is assigned
/// positionally on insert. [supersetGroup] / [supersetOrder] bracket the
/// exercise into a superset; [modality] / [progression] / [progressionParams]
/// carry the P2 modality + P4 progression scheme.
typedef GymRoutineExerciseInput = ({
  String exerciseName,
  String exerciseKey,
  int? supersetGroup,
  int? supersetOrder,
  String? modality,
  String? progression,
  Map<String, dynamic>? progressionParams,
  List<GymRoutineSetInput> sets,
});

/// One item in a [ApiClient.createMealTemplate] call. Mirrors a food_log
/// row's macro shape; `position` is assigned positionally on insert.
typedef MealTemplateItemInput = ({
  String itemName,
  String? mealSlot,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
});

/// One ingredient in a [ApiClient.createRecipe] call. Mirrors a food_log row's
/// macro shape plus a `quantity` multiplier; `position` is assigned positionally
/// on insert.
typedef RecipeIngredientInput = ({
  String itemName,
  double quantity,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
});

/// One food_log entry for [ApiClient.logFoodBatch]. The one-tap meal-template
/// log path turns each template item into one of these.
typedef FoodLogInput = ({
  String? id,
  DateTime? startedAt,
  String itemName,
  String? mealSlot,
  double? calories,
  double? proteinG,
  double? carbsG,
  double? fatG,
  String? externalId,
});

/// One block in a [ApiClient.createSessionPlan] call. `id` is client-minted so
/// an item can reference it in the same insert without a server round-trip.
typedef SessionPlanBlockInput = ({
  String id,
  int position,
  String? name,
});

/// One movement item in a [ApiClient.createSessionPlan] call. [kind] is the raw
/// `'hold' | 'reps' | 'flow'` wire value; [blockId] references a
/// [SessionPlanBlockInput.id] (or null for a flat, blockless plan).
typedef SessionPlanItemInput = ({
  String id,
  String? blockId,
  int position,
  String movementName,
  String kind,
  int? durationS,
  int? reps,
  bool perSide,
  String? tempo,
  String? cue,
});

/// One row of the `activities` UNION view (runs + gym_workouts + food_log),
/// projecting (id, kind, started_at, summary). `summary` is a thin per-kind
/// jsonb the History timeline renders without a second fetch; the detail
/// screens load the full underlying row. Migration 20261204_001. Mirrors the
/// web `ActivityRow` (core/data.ts); `kind` stays a raw string ('run' |
/// 'lift' | 'meal') like the web union.
class ActivityRow {
  final String id;
  final String kind;
  final DateTime startedAt;
  final Map<String, dynamic> summary;
  const ActivityRow({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.summary,
  });

  /// Parse one `activities` view row. Returns null for a row with no id or an
  /// unparseable `started_at` (a row that can't land on a calendar day can't
  /// render in the timeline) — mirrors the web `fetchActivities` filter.
  /// `kind` defaults to 'run', `summary` to an empty map.
  static ActivityRow? fromRow(Map<String, dynamic> row) {
    final id = row['id'] as String?;
    final startedAt = row['started_at'] as String?;
    if (id == null || id.isEmpty || startedAt == null || startedAt.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(startedAt);
    if (parsed == null) return null;
    final rawSummary = row['summary'];
    return ActivityRow(
      id: id,
      kind: (row['kind'] as String?) ?? 'run',
      startedAt: parsed,
      summary:
          rawSummary is Map ? rawSummary.cast<String, dynamic>() : const {},
    );
  }
}

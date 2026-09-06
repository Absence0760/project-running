import 'dart:async';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:api_client/api_client.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

import 'audio_cues.dart';
import 'background_sync.dart';
import 'dev_auto_login.dart';
import 'firebase_push_messaging.dart';
import 'in_progress_recovery.dart';
import 'l10n/gen/app_localizations.dart';
import 'l10n/locale_support.dart';
import 'local_food_store.dart';
import 'local_gear_store.dart';
import 'local_gym_store.dart';
import 'local_route_store.dart';
import 'local_run_store.dart';
import 'offline_store_wipe.dart';
import 'offline_sync_store.dart';
import 'preferences.dart';
import 'push_messaging_bridge.dart';
import 'push_target.dart';
import 'race_controller.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'settings_cache.dart';
import 'settings_sync.dart';
import 'shared_file_import.dart';
import 'social_service.dart';
import 'sync_service.dart';
import 'ble_heart_rate.dart';
import 'ble_treadmill.dart';
import 'tile_cache.dart';
import 'training_service.dart';
import 'watch_ingest_queue.dart';
import 'wear_auth_bridge.dart';
import 'wear_routes_bridge.dart';
import 'widgets/undo_bar.dart';

/// Holds the auth-state subscription registered in [main]. Top-level so
/// a re-entrant main (rare — full hot-restart resets isolate state, but
/// belt-and-braces for future reconnect logic) can cancel any prior
/// listener instead of stacking duplicates.
StreamSubscription<AuthState>? _authStateSub;
// The most recent signed-in user id, remembered so the signedOut handler
// (whose event carries no session) can scope the settings-cache drop to
// the departing account (issue #231).
String? _lastSignedInUserId;

/// The native-push (FCM/APNs) device-token bridge, attached in [main] after
/// Supabase init. Top-level so a re-entrant main can detach a prior instance.
/// A no-op when Firebase isn't configured on the device (the credential gate).
PushMessagingBridge? _pushBridge;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load the locale-specific date symbols so `intl`'s DateFormat renders
  // month / weekday names in the active language. Cheap, idempotent, and
  // required before any non-`en` DateFormat is constructed.
  await initializeDateFormatting();

  // Replace Flutter's default red-screen error widget in release builds
  // with a quiet fallback card. A crash inside a single subtree (most
  // likely the live map — flutter_map is the widest surface area in the
  // run screen) would otherwise take down the whole screen, including
  // the recording stats. RunRecorder lives outside the widget tree, so
  // recording itself keeps going while the user sees a replaced subtree.
  //
  // Kept as the default red screen in debug so we don't mask bugs during
  // development.
  //
  // The debugPrint no-op: Flutter's default debugPrint forwards to
  // print() in EVERY build mode — release included; only assert()
  // blocks are compiler-stripped. The layered-resilience contract
  // debugPrints caught exceptions (`$e`) across ~76 files, and a
  // PostgrestException's details/hint can echo row content (contact
  // emails, health free text) into logcat/os_log on a release build
  // attached for field debugging. No-op the whole class in release;
  // keep debug verbose. /audit/pii-in-logs.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
    ErrorWidget.builder = (details) {
      debugPrint('ErrorWidget: ${details.exception}');
      return Container(
        color: const Color(0xFF1E1B4B),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              // No Theme above this builder; the surface is hardcoded dark,
              // so take the dark palette's token statically.
              color: AppSemanticColors.dark.warning,
              size: 24,
            ),
            const SizedBox(height: 8),
            const Text(
              "This section couldn't load.\nRecording is still running.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      );
    };
  }

  // `dotenv` must resolve first because the Supabase URL/key come from it,
  // and Supabase.initialize is one of the parallel tasks below.
  //
  // Two paths run for every platform: a `String.fromEnvironment` block
  // that picks up `--dart-define`s (production CI passes these for
  // both iOS and Android), and a debug-only `.env.development` load
  // that gives local development a frictionless path. Release builds
  // NEVER read `.env.development` even though pubspec.yaml ships it as
  // an asset — this closes the audit High where a developer-built
  // release APK would otherwise embed their real local
  // SUPABASE_ANON_KEY, MAPTILER_KEY, dev creds, and BYPASS_PAYWALL=true.
  // See decisions §13 for the iOS counterpart. Per-machine overrides go
  // through `--dart-define` (merged on top below, winning); on mobile
  // that is the override path, not a `.env.local` file, because
  // flutter_dotenv loads from the asset bundle (decisions §137).
  //
  // EVERY key any surface reads from dotenv must appear here, or it is
  // debug-only by accident: three sign-off-gated feature flags sat unreadable
  // in release builds because they did not (decisions §709). The
  // `env_flag_test.dart` reachability guard fails the build when a new read
  // is added without its bridge entry. Whether a release WORKFLOW passes a
  // given define is a separate, deploy-time decision.
  const mapTilerKey = String.fromEnvironment('MAPTILER_KEY');
  const webBaseUrl = String.fromEnvironment('WEB_BASE_URL');
  const stravaClientId = String.fromEnvironment('STRAVA_CLIENT_ID');
  const supabaseUrlDef = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKeyDef = String.fromEnvironment('SUPABASE_ANON_KEY');
  const devEmailDef = String.fromEnvironment('DEV_USER_EMAIL');
  const devPasswordDef = String.fromEnvironment('DEV_USER_PASSWORD');
  const osrmUrlDef = String.fromEnvironment('OSRM_URL');
  const liveHubUrlDef = String.fromEnvironment('LIVE_HUB_URL');
  const sentryDsnDef = String.fromEnvironment('SENTRY_DSN');
  const googleWebClientIdDef = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  const revenueCatAndroidDef = String.fromEnvironment('REVENUECAT_API_KEY_ANDROID');
  const revenueCatIosDef = String.fromEnvironment('REVENUECAT_API_KEY_IOS');
  const enableNearbyRunnersDef = String.fromEnvironment('ENABLE_NEARBY_RUNNERS');
  const offRouteEscalationDef =
      String.fromEnvironment('OFF_ROUTE_ESCALATION_ENABLED');
  const adaptiveFitnessGateDef = String.fromEnvironment('ADAPTIVE_FITNESS_GATE');
  const weighInGateDef = String.fromEnvironment('WEIGH_IN_GATE');
  const tileUrlTemplateDef = String.fromEnvironment('TILE_URL_TEMPLATE');
  const usdaFdcApiKeyDef = String.fromEnvironment('USDA_FDC_API_KEY');
  dotenv.loadFromString(
    envString: [
      if (supabaseUrlDef.isNotEmpty) 'SUPABASE_URL=$supabaseUrlDef',
      if (supabaseAnonKeyDef.isNotEmpty) 'SUPABASE_ANON_KEY=$supabaseAnonKeyDef',
      if (mapTilerKey.isNotEmpty) 'MAPTILER_KEY=$mapTilerKey',
      if (webBaseUrl.isNotEmpty) 'WEB_BASE_URL=$webBaseUrl',
      if (stravaClientId.isNotEmpty) 'STRAVA_CLIENT_ID=$stravaClientId',
      if (devEmailDef.isNotEmpty) 'DEV_USER_EMAIL=$devEmailDef',
      if (devPasswordDef.isNotEmpty) 'DEV_USER_PASSWORD=$devPasswordDef',
      if (osrmUrlDef.isNotEmpty) 'OSRM_URL=$osrmUrlDef',
      if (liveHubUrlDef.isNotEmpty) 'LIVE_HUB_URL=$liveHubUrlDef',
      if (sentryDsnDef.isNotEmpty) 'SENTRY_DSN=$sentryDsnDef',
      if (googleWebClientIdDef.isNotEmpty) 'GOOGLE_WEB_CLIENT_ID=$googleWebClientIdDef',
      if (revenueCatAndroidDef.isNotEmpty) 'REVENUECAT_API_KEY_ANDROID=$revenueCatAndroidDef',
      if (revenueCatIosDef.isNotEmpty) 'REVENUECAT_API_KEY_IOS=$revenueCatIosDef',
      if (enableNearbyRunnersDef.isNotEmpty)
        'ENABLE_NEARBY_RUNNERS=$enableNearbyRunnersDef',
      if (offRouteEscalationDef.isNotEmpty)
        'OFF_ROUTE_ESCALATION_ENABLED=$offRouteEscalationDef',
      if (adaptiveFitnessGateDef.isNotEmpty)
        'ADAPTIVE_FITNESS_GATE=$adaptiveFitnessGateDef',
      if (weighInGateDef.isNotEmpty) 'WEIGH_IN_GATE=$weighInGateDef',
      if (tileUrlTemplateDef.isNotEmpty) 'TILE_URL_TEMPLATE=$tileUrlTemplateDef',
      if (usdaFdcApiKeyDef.isNotEmpty) 'USDA_FDC_API_KEY=$usdaFdcApiKeyDef',
    ].join('\n'),
    isOptional: true,
  );
  if (kDebugMode) {
    try {
      // flutter_dotenv's load() calls clean() (clearing its env map) before it
      // applies mergeWith, so passing the live `dotenv.env` would self-wipe the
      // dart-define values loaded just above. Snapshot them first.
      final defineEnv = Map<String, String>.from(dotenv.env);
      await dotenv.load(
        fileName: '.env.development',
        mergeWith: defineEnv,
        isOptional: true,
      );
    } catch (e) {
      debugPrint('main: optional .env.development load failed: $e');
    }
  }

  // Construct stores synchronously so we can kick off their `init()`s in
  // parallel with the other independent launch tasks. Nothing here
  // depends on anything else — the previous sequential-await chain was
  // just paying plugin-channel round-trip latency N times for no reason.
  final store = LocalRunStore();
  final routeStore = LocalRouteStore();
  final gearStore = LocalGearStore();
  final gymStore = LocalGymStore();
  final foodStore = LocalFoodStore();
  final prefs = Preferences();
  final watchQueue = WatchIngestQueue();

  final supabaseUrl = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
  final hasSupabase = supabaseUrl != null &&
      anonKey != null &&
      supabaseUrl.isNotEmpty &&
      anonKey.isNotEmpty;

  // Parallel batch. Each of these is independent — the platform plugin
  // channels (`getApplicationDocumentsDirectory`, `getApplicationCacheDirectory`,
  // `SharedPreferences.getInstance`, etc.) multiplex fine.
  await Future.wait([
    TileCache.init(),
    store.init(),
    routeStore.init(),
    gearStore.init(),
    gymStore.init(),
    foodStore.init(),
    prefs.init(),
    watchQueue.init(),
    if (hasSupabase)
      ApiClient.initialize(url: supabaseUrl, anonKey: anonKey)
          .catchError((Object e) {
        debugPrint('Supabase init failed, running offline: $e');
      }),
    // Best-effort Firebase init for native push. Succeeds only when the
    // operator's google-services.json / GoogleService-Info.plist are present in
    // the native project (the credential gate); without them this throws and we
    // run with push disabled — the PushMessagingBridge no-ops on
    // FirebasePushMessaging.isAvailable == false. Never blocks startup.
    initFirebaseForPush(),
  ]);

  // Expose the loaded Preferences via the top-level accessor in
  // `preferences.dart` so screens that don't take a Preferences
  // constructor dep (feed, profile notifications, club-detail route
  // list, live spectator, the recovered-run banner, TTS announcer)
  // can read the user's unit pref via `activeDistanceUnit` /
  // `formatDistanceForPref()`. Idempotent.
  registerActivePreferences(prefs);

  // Hydrate the theme-mode notifier from the persisted preference.
  // Must run before runApp so the first frame paints in the user's
  // chosen mode instead of flashing the default and then snapping over.
  themeModeNotifier.value = prefs.themeMode;

  // Hydrate the locale notifier from the persisted per-device preference.
  // Null = follow the device locale (negotiated in MaterialApp). Must run
  // before runApp so the first frame paints in the chosen language.
  localeNotifier.value = prefs.locale;

  // Keep the context-free active-locale tag in sync with the notifier so
  // date formatting on surfaces without a BuildContext (share cards,
  // notification text, period-summary share text) follows the user's
  // language. Resolve once now, then on every locale change.
  void syncActiveLocaleTag() {
    registerActiveLocaleTag(resolveActiveLocaleTag(
        localeNotifier.value,
        PlatformDispatcher.instance.locales));
  }

  syncActiveLocaleTag();
  localeNotifier.addListener(syncActiveLocaleTag);

  // Recover a run that was in progress when the app was last killed
  // (crash, force-stop, OOM). We promote the partial data to a regular
  // completed run so at least the user keeps whatever was captured. Only
  // runs with meaningful content are kept — tiny "I tapped start then
  // backgrounded" runs are dropped silently.
  //
  // An indoor (pedometer-only) run has no track and its distance came
  // from `steps × stride`. For those, we accept the run if duration ≥ 60s
  // instead of requiring GPS waypoints — a treadmill session that crashed
  // after 10 minutes shouldn't evaporate just because there are no fixes.
  cm.Run? recoveredRun;
  // A recent, non-empty partial is RESUMABLE — instead of finalizing it into a
  // separate finished Run (which split one continuous multi-day effort into two
  // disjoint records — the moab240 CRITICAL finding), hand it down to the run
  // screen so it can re-hydrate the recorder and continue the SAME run. The
  // in-progress file is deliberately NOT cleared in this branch; the run screen
  // appends to it on resume (or clears it on Finish / Discard).
  cm.Run? resumablePartial;
  // Persona-hunt Casual #3: surface a one-time banner when a partial
  // is recovered OR discarded, so a "the app ate my run" suspicion
  // becomes "the app noticed and dropped a 38 m partial". Null when
  // nothing happened (and null for the resumable branch, which prompts
  // interactively on the run screen rather than passively).
  String? recoveryBannerMessage;

  final audioCues = AudioCues();

  // ApiClient is created synchronously if Supabase initialised. The
  // awaited `Supabase.initialize` above sets `ApiClient.isInitialized`
  // to `true` on success; on silent failure (the `.catchError` branch
  // above) the flag stays `false` and we leave `api` null so the rest
  // of the app behaves like the no-env-vars path. Without this gate, a
  // failed init produces `ApiClient` instances whose first method call
  // explodes with `LateInitializationError` deep inside the Supabase
  // SDK — see decisions.md for the bug history.
  ApiClient? api;
  SettingsSyncService? settingsSync;
  if (hasSupabase && ApiClient.isInitialized) {
    try {
      api = ApiClient();
      final sp = await SharedPreferences.getInstance();
      settingsSync = SettingsSyncService(
        preferences: prefs,
        cache: SharedPrefsSettingsCache(sp),
      );
    } catch (e) {
      debugPrint('ApiClient construction failed: $e');
    }
  }

  // Wire the owner-tag provider so every locally-saved run carries
  // `metadata.created_by_user_id`. Without this, on a shared device
  // User A's runs would silently sync under User B's account after
  // a sign-out/sign-in. The SyncService filters by this tag during
  // drain; see `docs/architecture/decisions.md § 67`.
  //
  // The provider reads `api?.userId` on each save — captures the
  // session at write time. When signed out, returns null (legitimate
  // for the "record without an account" flow; the first signed-in
  // user adopts those runs).
  store.currentUserIdProvider = () => api?.userId;
  // Routes get the same treatment (issue #229): the store stamps a
  // device-local owner tag on save and filters its getters by it, so a
  // shared device's next account neither sees nor sync-pushes the prior
  // account's local route library.
  routeStore.currentUserIdProvider = () => api?.userId;

  // Recovery runs AFTER the owner-tag providers are wired, not before:
  // `store.save` only stamps `created_by_user_id` when the provider is
  // set, and the in-progress file itself is never tagged. Recovering
  // first left the run untagged, which `filterRunsForCurrentUser` reads
  // as adoptable — so on a shared device the next account to sign in
  // would push a previous user's crashed run as its own (§67).
  try {
    final partial = await store.loadInProgress();
    final evaluation = evaluateInProgressPartial(partial);
    switch (evaluation.outcome) {
      case InProgressOutcome.recovered:
        await store.save(evaluation.recovered!);
        recoveredRun = evaluation.recovered;
        await store.clearInProgress();
      case InProgressOutcome.resumable:
        // Keep the in-progress file — the run screen resumes appending to it.
        resumablePartial = evaluation.resumablePartial;
      case InProgressOutcome.discarded:
        await store.clearInProgress();
      case InProgressOutcome.none:
        break;
    }
    recoveryBannerMessage = evaluation.bannerMessage;
  } catch (e) {
    debugPrint('In-progress recovery failed: $e');
  }

  final social = SocialService();
  final syncService = SyncService(
    apiClient: api,
    runStore: store,
    routeStore: routeStore,
    socialService: social,
  );
  syncService.start();

  final raceController = RaceController(social);
  // start() -> _refresh() reads Supabase.instance.client, which throws until
  // init resolves; the unawaited call would otherwise abort the isolate.
  if (hasSupabase && api != null) {
    unawaited(raceController.start());
  }
  final training = TrainingService();
  final heartRate = BleHeartRate();
  // Kick off auto-reconnect in the background. If the user has paired a
  // strap previously, HR is ready when they tap Start; otherwise it's a
  // no-op and the run records without HR.
  unawaited(heartRate.connectCached());
  // Same lifetime + auto-reconnect contract as the HR strap: one app-owned
  // FTMS belt reader, connected at startup, so a belt paired in Settings is
  // the same instance the run screen reads for treadmill mode.
  final treadmill = BleTreadmill();
  unawaited(treadmill.connectCached());

  // Apple Watch ingest path. The native iOS bridge
  // (`Runner/WatchIngestBridge.swift`) forwards `WCSession` payloads via
  // the `run_app/watch_ingest` MethodChannel. On Android the channel
  // isn't registered, so `WatchIngest.attach` fires `MissingPluginException`
  // (caught) and the no-op is invisible — keeps the bootstrap identical
  // across both apps.
  if (api != null && api.userId != null) {
    WatchIngest.attach(api, watchQueue);
    // Bootstrap with whoever is currently signed in (cached session
    // from a previous launch). Any payloads enqueued during a future
    // signed-out window will carry this stamp, so a different user
    // signing in later can't accidentally adopt them. The same call
    // fires from the signedIn listener below for fresh sign-ins.
    unawaited(watchQueue.setLastKnownOwner(api.userId));
  }

  // Everything below here runs AFTER the first frame paints:
  //
  //  - WorkManager background-sync registration (plugin channel work the
  //    user never sees)
  //  - Dev-only auto sign-in (network round-trip)
  //  - SettingsSync cloud fetch (network round-trip)
  //  - WearAuthBridge attach (method channel)
  //  - Auth-state subscription (reactive sign-in plumbing —
  //    settingsSync.onSignedIn must not appear on the critical path)
  //
  // Previously these all awaited before runApp and held the splash screen
  // open for hundreds of ms on slow connections. None of them change the
  // first-frame render — if the user isn't signed in yet, the dashboard
  // shows the signed-out state and updates when auth finishes.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    registerBackgroundSync();
    if (!hasSupabase || api == null) return;
    final apiNonNull = api;
    // Cancel any prior subscription before attaching a fresh one.
    // Hot-restart resets isolate state so this is normally a no-op,
    // but it makes a re-entrant main() (or future reconnect logic)
    // safe against leaked listeners.
    _authStateSub?.cancel();
    _authStateSub = Supabase.instance.client.auth.onAuthStateChange
        .listen((event) {
      final sessionUserId = event.session?.user.id;
      if (sessionUserId != null && sessionUserId.isNotEmpty) {
        _lastSignedInUserId = sessionUserId;
      }
      if (event.event == AuthChangeEvent.signedIn) {
        WatchIngest.attach(apiNonNull, watchQueue);
        // Stamp the queue with the freshly-signed-in user BEFORE
        // draining. The drain below skips files whose stamp names a
        // different user — without this update the drain would still
        // see the previous user's stamp and skip every file. The
        // setLastKnownOwner write is itself unawaited (it's cheap
        // file I/O and we don't want to gate the drain on it); the
        // queue's in-memory cache updates synchronously inside the
        // call, which is what drain actually consults via the
        // `intended_owner_user_id` check against `api.userId`.
        watchQueue.setLastKnownOwner(apiNonNull.userId).catchError((Object e) {
          debugPrint('Watch ingest last-owner stamp failed: $e');
        });
        // Mirror web's `fetchUser` upsert-when-null path so a mobile-
        // only sign-up (user creates an account on mobile and never
        // visits web) gets a `user_profiles` row materialised with
        // defaults. Without this, RLS-joined reads silently return
        // nothing and the dashboard's preferred-unit falls back to
        // whichever hard-coded default each reader uses.
        apiNonNull.ensureMyProfile().catchError((Object e) {
          debugPrint('ensureMyProfile failed: $e');
        });
        try {
          watchQueue.drain(apiNonNull).catchError((Object e) {
            debugPrint('Watch ingest queue drain failed: $e');
          });
        } catch (e) {
          debugPrint('Watch ingest queue drain error: $e');
        }
        settingsSync?.onSignedIn().catchError((Object e) {
          debugPrint('Settings sync on signedIn failed: $e');
        });
        // Drain the unsynced run queue now that a session is live.
        // Without this trigger, runs recorded offline (or while a
        // previous session was signed out) sit unsynced until the
        // app is backgrounded + foregrounded, a connectivity blip
        // fires, or the user manually taps "Sync all" in runs_screen.
        // 'signin' also bypasses the backoff window — a fresh auth
        // session invalidates any prior auth-rejection backoff that
        // would otherwise stall the drain for up to 30 min.
        syncService.triggerSync('signin').catchError((Object e) {
          debugPrint('Sync on signedIn failed: $e');
        });
      } else if (event.event == AuthChangeEvent.signedOut) {
        // Drop the previously-signed-in user's cached settings bag
        // so a subsequent sign-in by a DIFFERENT user on the same
        // device doesn't read the prior user's universal/device prefs
        // during the brief window before onSignedIn re-fetches. The
        // privacy-zones path matters specifically here: the live
        // broadcaster's privacyZonesProvider reads the cached bag on
        // every push (see decisions §33), so leaving stale zones in
        // place would leak the previous user's home/work coordinates
        // to a new user's spectator broadcast. Other settings (units,
        // theme) are merely cosmetic but the clear is uniform.
        // The reset also clears the bag-mirrored Preferences (privacy
        // default, body weight, goals, fueling rates, units) + the runs
        // delta-sync watermark, and drops the departing account's cached
        // bags — the sign-in overlay only overwrites keys present in the
        // NEXT account's bag, so anything left set would carry over.
        final departingUserId = _lastSignedInUserId;
        _lastSignedInUserId = null;
        settingsSync
            ?.onSignedOut(priorUserId: departingUserId)
            .catchError((Object e) {
          debugPrint('Settings sync on signedOut failed: $e');
        });
        // Clear the per-row offline stores so a DIFFERENT user signing in on
        // the same device can't read the prior user's gym/food/gear rows, and
        // — worse — so an unsynced pendingCreate row from the prior user can't
        // be pushed into the new user's account on the next drain. These
        // stores aren't user-namespaced on disk (decisions §73/§122 deferred
        // the `created_by_user_id` tag), so sign-out wipes them outright,
        // mirroring the settings cache's drop-on-sign-out (§72).
        for (final s in <OfflineSyncStore>[gearStore, gymStore, foodStore]) {
          s.clear().catchError((Object e) {
            debugPrint('Offline store clear on signedOut failed: $e');
          });
        }
        // The screen-owned store types (routines, meal templates, recipes,
        // checkpoint crossings, session plans) have no app-singleton to
        // clear — wipe their shared on-disk directories via throwaway
        // instances. The crossings store carries bibs and, behind
        // WEIGH_IN_GATE, medical weigh-in fields.
        // Re-push the watch's route list. LocalRouteStore hides another
        // account's tagged routes once the provider reports signed-out, but
        // the bridge only pushes on a store MUTATION — and signing out isn't
        // one. Without this the paired watch keeps showing the previous
        // account's starred route names and waypoints until some unrelated
        // future edit happens to fire the listener. attach() re-pushes and
        // drops the diff cache, so it is the right idempotent nudge.
        WearRoutesBridge().attach(routeStore);
        wipeScreenOwnedOfflineStores().catchError((Object e) {
          debugPrint('Screen-owned store wipe on signedOut failed: $e');
        });
        // The run store's rows are owner-tagged and stay (a re-signing-in
        // account keeps its own history), but the in-progress snapshot is
        // not tagged and would be adopted by whoever signs in next.
        wipeInProgressRecording(store);
      }
    });
    WearAuthBridge().attach(url: supabaseUrl, anonKey: anonKey);
    WearRoutesBridge().attach(routeStore);
    // Native-push device-token registration. No-ops when Firebase isn't
    // configured on the device (FirebasePushMessaging.isAvailable == false).
    // L4 auxiliary effect — attach() never throws into the startup path.
    _pushBridge?.detach();
    _pushBridge = PushMessagingBridge(
      messaging: FirebasePushMessaging(),
      api: apiNonNull,
      // Park the tapped notification's target; HomeScreen drains it. Without
      // this the seam existed but nothing consumed it, so every push tap
      // opened wherever the app already was and discarded the deep link.
      onOpenNotification: routePushOpen,
    )..attach();
    final devEmail = dotenv.env['DEV_USER_EMAIL'];
    final devPassword = dotenv.env['DEV_USER_PASSWORD'];
    Future(() async {
      // Gated on a loopback SUPABASE_URL — seed creds must never sign a
      // user into a production backend. See dev_auto_login.dart.
      if (shouldAutoLogin(
        url: supabaseUrl,
        email: devEmail,
        password: devPassword,
      )) {
        try {
          await api!.signIn(email: devEmail!, password: devPassword!);
        } catch (e) {
          debugPrint('Auto sign-in failed: $e');
        }
      }
      // Best-effort — the service stores `lastError` for the settings
      // screen to surface.
      try {
        await settingsSync?.onSignedIn();
      } catch (e) {
        debugPrint('Settings sync failed: $e');
      }
    });
  });

  // Sentry init runs in release builds only and only when SENTRY_DSN is
  // populated (via dotenv on Android, --dart-define-from-file on iOS).
  // Empty DSN → no-op, so dev builds and CI builds without secrets stay
  // off the Sentry dashboard. The release-tag (versionName) is read from
  // the build via `--dart-define=APP_RELEASE=...` so a regression's
  // release can be pinpointed.
  final sentryDsn = dotenv.env['SENTRY_DSN'] ?? '';
  final appRelease = const String.fromEnvironment('APP_RELEASE', defaultValue: 'dev');
  // Sentry opt-out (audit/gdpr May 2026 High): Settings → Privacy →
  // "Send error reports" persists `prefs.sentryOptOut`. When true,
  // we skip init entirely so no traces / breadcrumbs / events fire.
  // Toggle applies on next launch — the SDK can't be cleanly un-
  // initialised mid-process without sentry-version-fragile shims.
  final shouldUseSentry =
      kReleaseMode && sentryDsn.isNotEmpty && !prefs.sentryOptOut;

  Future<void> startApp() async {
    runApp(RunApp(
      apiClient: api,
      runStore: store,
      routeStore: routeStore,
      gearStore: gearStore,
      gymStore: gymStore,
      foodStore: foodStore,
      preferences: prefs,
      audioCues: audioCues,
      syncService: syncService,
      settingsSync: settingsSync,
      social: social,
      raceController: raceController,
      training: training,
      heartRate: heartRate,
      treadmill: treadmill,
      recoveredRun: recoveredRun,
      recoveryBannerMessage: recoveryBannerMessage,
      resumablePartial: resumablePartial,
    ));
  }

  if (shouldUseSentry) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.release = appRelease;
        options.tracesSampleRate = 0.1;
        options.environment = appRelease == 'dev' ? 'development' : 'production';
        // audit/app-store-privacy (2026-05-25): Sentry's default
        // behaviour attaches the client IP and (depending on the
        // platform) device identifiers to events. The Play Data
        // Safety form + iOS Privacy Manifest declare crash data as
        // "not linked to user", so we have to hold Sentry to that
        // contract by opting out of identity attachment.
        options.sendDefaultPii = false;
        // Drop the user's Authorization header from breadcrumbs — the
        // bearer token would otherwise land on every Sentry event.
        options.beforeSend = (event, hint) {
          final scrubbed = event;
          // Sentry's default PII scrubbing handles most of it; this is
          // belt-and-braces for the Supabase JWT path specifically.
          return scrubbed;
        };
      },
      appRunner: startApp,
    );
  } else {
    await startApp();
  }

  // OS "Open with" / share-sheet GPX/KML → route import (Android
  // ACTION_VIEW / ACTION_SEND intent-filters, iOS document open). Listen
  // for files shared while running, then drain any file that cold-launched
  // the app; HomeScreen consumes incomingRouteImport once it mounts. See
  // shared_file_import.dart + the AndroidManifest / iOS Info.plist
  // registration. Guarded so a plugin/platform failure never blocks launch.
  try {
    final sharedFileImport =
        SharedFileImportService(routeStore: routeStore)..start();
    unawaited(sharedFileImport.processInitial());
  } catch (e) {
    debugPrint('shared-file import init failed: $e');
  }
}

class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);
}

final themeModeNotifier = ThemeModeNotifier();

/// Active app locale. `null` means "follow the device locale" (the default).
/// Hydrated from [Preferences] in [main] and flipped by the language picker;
/// drives [MaterialApp.locale] reactively, mirroring [themeModeNotifier].
/// Per-device, never synced to the settings bag — matches web's
/// localStorage-only locale model.
final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

/// Cross-screen handoff for "start this workout now". Set by deep
/// flows (e.g. plan_detail_screen's calendar → workout_detail →
/// Start workout) that need to bring the user back to the Run tab and
/// preload the structured runner. HomeScreen listens and switches to
/// the Run tab; RunScreen listens (or drains in initState) and calls
/// the workout runner.
///
/// Intentionally global rather than threaded through ~5 layers of
/// widget constructors — every entry path (run-screen, plans-screen,
/// plan-new-screen, club-detail) ultimately routes through the same
/// HomeScreen, so a single notifier centralises the handoff.
final ValueNotifier<cm.PlanWorkoutRow?> pendingStartWorkout =
    ValueNotifier<cm.PlanWorkoutRow?>(null);

/// Cross-screen handoff for "arm this guided run on the recorder". Set by the
/// guided-run detail screen (reachable from the Coach tab and from Settings),
/// which pops back to the shell straight after; HomeScreen listens and
/// switches to the Run tab, RunScreen drains it and arms the script through
/// the same path its own picker uses. Sibling of [pendingStartWorkout].
///
/// The library ID travels rather than the resolved run: the library is
/// rebuilt per locale, so the recorder re-resolves it against its own
/// [AppLocalizations] instead of holding a title built somewhere else.
final ValueNotifier<String?> pendingArmGuidedRun = ValueNotifier<String?>(null);

/// Cross-screen handoff for "start a run following this route now". Set by
/// any route surface that isn't hosted under HomeScreen's route-list flow —
/// the route-detail Start FAB (so it works regardless of who pushed the
/// screen) and the public / shared-route screen (a route the viewer doesn't
/// own). HomeScreen listens, switches to the recorder page, and preselects
/// the route. Sibling of [pendingStartWorkout] — one notifier instead of
/// threading an `onStartRun` callback down every push path.
final ValueNotifier<cm.Route?> pendingStartRunWithRoute =
    ValueNotifier<cm.Route?>(null);

/// Cross-screen handoff for "a push notification was tapped, open its
/// target". Set by [PushMessagingBridge]'s open callback; HomeScreen listens
/// and navigates. A notifier rather than a direct navigation because the tap
/// that COLD-STARTS the app is delivered before any Navigator exists — the
/// target parks here and HomeScreen drains it on its first frame, the same
/// shape [incomingRouteImport] uses for a GPX opened from a closed app.
final ValueNotifier<PushTarget?> pendingPushTarget =
    ValueNotifier<PushTarget?>(null);

/// The bridge's open-notification callback: map the tapped notification's URL
/// onto a target and park it for HomeScreen. Named (not an inline closure) so
/// the seam between the push payload and the notifier is directly testable.
void routePushOpen(PushOpenedMessage msg) =>
    pendingPushTarget.value = pushTargetFromUrl(msg.url);

class RunApp extends StatefulWidget {
  final ApiClient? apiClient;
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final LocalGearStore gearStore;
  final LocalGymStore gymStore;
  final LocalFoodStore foodStore;
  final Preferences preferences;
  final AudioCues audioCues;
  final SyncService syncService;
  final SettingsSyncService? settingsSync;
  final SocialService social;
  final RaceController raceController;
  final TrainingService training;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final cm.Run? recoveredRun;
  final String? recoveryBannerMessage;
  final cm.Run? resumablePartial;
  const RunApp({
    super.key,
    this.apiClient,
    required this.runStore,
    required this.routeStore,
    required this.gearStore,
    required this.gymStore,
    required this.foodStore,
    required this.preferences,
    required this.audioCues,
    required this.syncService,
    this.settingsSync,
    required this.social,
    required this.raceController,
    required this.training,
    required this.heartRate,
    required this.treadmill,
    this.recoveredRun,
    this.recoveryBannerMessage,
    this.resumablePartial,
  });

  @override
  State<RunApp> createState() => _RunAppState();
}

class _RunAppState extends State<RunApp> {
  @override
  void initState() {
    super.initState();
    // The undo host reads its window at defer time from a module-level value
    // rather than from a context, because a `commit` outlives the surface that
    // scheduled it. Mirror the pref in from here so the direction of the
    // dependency stays app → widget.
    _syncUndoWindow();
    widget.preferences.addListener(_syncUndoWindow);
  }

  void _syncUndoWindow() => setUndoWindowS(widget.preferences.undoWindowS);

  @override
  void dispose() {
    widget.preferences.removeListener(_syncUndoWindow);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([themeModeNotifier, localeNotifier]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Threkir',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeModeNotifier.value,
          locale: localeNotifier.value,
          supportedLocales: supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          // `locale` (when the user has picked) or the device's ordered
          // locale list is negotiated down to one of our six catalogues.
          localeListResolutionCallback: (locales, supported) =>
              negotiateLocale(null, locales?.toList() ?? const []),
          home: widget.preferences.onboarded
              ? HomeScreen(
                  apiClient: widget.apiClient,
                  runStore: widget.runStore,
                  routeStore: widget.routeStore,
                  gearStore: widget.gearStore,
                  gymStore: widget.gymStore,
                  foodStore: widget.foodStore,
                  preferences: widget.preferences,
                  audioCues: widget.audioCues,
                  social: widget.social,
                  raceController: widget.raceController,
                  training: widget.training,
                  heartRate: widget.heartRate,
                  treadmill: widget.treadmill,
                  settingsSync: widget.settingsSync,
                  recoveredRun: widget.recoveredRun,
                  recoveryBannerMessage: widget.recoveryBannerMessage,
                  resumablePartial: widget.resumablePartial,
                )
              : OnboardingScreen(
                  preferences: widget.preferences,
                  settingsSync: widget.settingsSync,
                  onDone: () => setState(() {}),
                ),
        );
      },
    );
  }
}

/// Receives runs from the paired Apple Watch via a method channel owned
/// by `Runner/AppDelegate.swift` + `Runner/WatchIngestBridge.swift` on
/// iOS. Android doesn't register the channel, so the `setMethodCallHandler`
/// installation is a harmless no-op and the bridge never fires.
///
/// Each call carries: `{id, started_at, duration_s, distance_m, source,
/// avg_bpm?, hr_coverage?, activity_type?, last_modified_at?, track}` —
/// `track` as the JSON TEXT of the file the watch wrote. Decoding is
/// [runFromWatchPayload]'s, not this class's: the same payload is decoded
/// here when the runner is signed in and by the queue's drain when they are
/// not, so a second copy of the decode could only ever be a divergence
/// waiting to happen, and was one.
///
/// When the user is not authenticated, the payload is persisted to the
/// [WatchIngestQueue] on disk and replayed on the next sign-in.
class WatchIngest {
  static const _channel = MethodChannel('run_app/watch_ingest');

  static void attach(ApiClient api, WatchIngestQueue queue) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'run') return null;
      final args = call.arguments as Map<Object?, Object?>?;
      if (args == null) return false;

      // One payload, ONE decoder. This handler used to carry a second
      // hand-written copy of the decode for the signed-in branch, and the two
      // copies had already drifted in both directions over the same bridge
      // payload: this one never learned the per-point `bpm` that
      // `docs/backend/metadata.md` says the watch-ingest decoder reads, and
      // `runFromWatchPayload` never learned that this bridge sends `track` as
      // JSON TEXT — so an Apple Watch run that arrived while signed out was
      // enqueued and later replayed with no track at all. Whether the runner
      // happened to be signed in is not something a decoder should be able to
      // change about the run.
      final payload = <String, dynamic>{
        for (final e in args.entries)
          if (e.key is String) e.key as String: e.value,
      };

      if (api.userId == null) {
        try {
          await queue.enqueue(payload);
        } catch (e) {
          debugPrint('Watch ingest queue write failed: $e');
        }
        return false;
      }

      try {
        await api.saveRun(runFromWatchPayload(payload));
        return true;
      } catch (e) {
        debugPrint('Watch ingest failed: $e');
        return false;
      }
    });
  }
}

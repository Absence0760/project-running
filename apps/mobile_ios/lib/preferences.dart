import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'goals.dart';
import 'l10n/locale_support.dart';
import 'l10n/number_format.dart';

enum DistanceUnit { km, mi }

enum WeightUnit { kg, lbs }

enum ActivityType {
  run,
  walk,
  cycle,
  hike,
  stroller;

  String get label {
    switch (this) {
      case ActivityType.run:
        return 'Run';
      case ActivityType.walk:
        return 'Walk';
      case ActivityType.cycle:
        return 'Cycle';
      case ActivityType.hike:
        // Surfaced as "Trail run" on the activity picker. The
        // internal enum + database value stays `hike` for back-
        // compat (existing rows, the SQL CHECK constraint, the
        // Strava + Health Connect importers, and the `parity.md`
        // matrix all key on the name), but the user-facing label
        // is the more accurate "Trail run" — a runner picking
        // this typically means "off-road run", not a hike. User
        // surfaced the old label as confusing because trail
        // runners didn't see themselves represented in the
        // picker and assumed selecting Hike meant they'd be
        // pushed onto roads.
        return 'Trail run';
      case ActivityType.stroller:
        return 'Stroller';
    }
  }

  IconData get icon {
    switch (this) {
      case ActivityType.run:
        return Icons.directions_run;
      case ActivityType.walk:
        return Icons.directions_walk;
      case ActivityType.cycle:
        return Icons.directions_bike;
      case ActivityType.hike:
        return Icons.terrain;
      case ActivityType.stroller:
        return Icons.child_friendly;
    }
  }

  /// Cycling shows speed (km/h, mph) instead of pace (min/km, min/mi).
  bool get usesSpeed => this == ActivityType.cycle;

  /// Calories burned per kilogram of body weight per kilometre travelled.
  /// Approximate metabolic equivalents.
  double get kcalPerKgPerKm {
    switch (this) {
      case ActivityType.run:
        return 1.0;
      case ActivityType.walk:
        return 0.5;
      case ActivityType.cycle:
        return 0.4;
      case ActivityType.hike:
        return 0.7;
      case ActivityType.stroller:
        // Running while pushing a stroller — a touch above open running.
        return 1.1;
    }
  }

  /// Distance interval (metres) for split notifications. Larger for cycling
  /// so a 30 km ride doesn't fire 30 announcements.
  double get splitIntervalMetres {
    switch (this) {
      case ActivityType.cycle:
        return 5000;
      default:
        return 1000;
    }
  }

  /// GPS distance filter in metres — how far the runner must move before
  /// the next position update is fired. Larger for cycling.
  int get gpsDistanceFilter {
    switch (this) {
      case ActivityType.cycle:
        return 5;
      default:
        return 3;
    }
  }

  /// Minimum movement (metres) between GPS samples that counts as real
  /// motion. Anything below this is treated as GPS jitter.
  double get minMovementMetres {
    switch (this) {
      case ActivityType.cycle:
        return 4;
      default:
        return 2;
    }
  }

  /// Average stride / step length in metres. Used as a fallback distance
  /// estimate for indoor / treadmill runs where GPS never produces a fix —
  /// the pedometer still counts steps, so `steps × strideMetres` gives a
  /// rough distance that's better than the `0.00 km` we'd otherwise show.
  /// Values are average-adult estimates; individual stride varies with
  /// height, cadence, and fatigue. Cycling has no pedometer so its value
  /// is unused.
  double get strideMetres {
    switch (this) {
      case ActivityType.run:
        return 1.1; // ~2000 steps/km at a moderate pace
      case ActivityType.walk:
        return 0.73; // ~1370 steps/km
      case ActivityType.cycle:
        return 0.0; // pedometer not meaningful for cycling
      case ActivityType.hike:
        return 0.85; // shorter than running, longer than walking
      case ActivityType.stroller:
        return 1.1; // running stride
    }
  }

  /// Maximum plausible speed (metres/second). Position deltas implying
  /// anything faster than this are discarded as GPS corruption — the line
  /// shouldn't teleport across town because of one bad fix.
  ///
  /// Values are deliberately generous (faster than realistic peak) to avoid
  /// dropping genuine fast segments, while still catching outright glitches.
  double get maxSpeedMps {
    switch (this) {
      case ActivityType.run:
        return 10; // ~2:45/km, faster than world records — pure corruption above this
      case ActivityType.walk:
        return 5; // brisk walk ~1.7 m/s; 5 gives headroom
      case ActivityType.cycle:
        return 25; // 90 km/h — higher than any sane cyclist
      case ActivityType.hike:
        return 6; // slow running overlap for scrambling / downhill
      case ActivityType.stroller:
        return 9; // running with a pram — a touch under open-run peak
    }
  }

  static ActivityType fromName(String? name) {
    return ActivityType.values.firstWhere(
      (a) => a.name == name,
      orElse: () => ActivityType.run,
    );
  }
}

/// App-wide user preferences (units, audio cues, etc.).
class Preferences extends ChangeNotifier {
  static const _kUseMiles = 'use_miles';
  static const _kAudioCues = 'audio_cues';
  static const _kOnboarded = 'onboarded';
  static const _kTargetPaceSecPerKm = 'target_pace_sec_per_km';
  static const _kGoalsJson = 'goals_json';
  static const _kAdvancedGps = 'advanced_gps';
  static const _kSplitIntervalMetres = 'split_interval_metres';
  // Mirrors the universal `default_activity_type` settings-bag key.
  // Drives the run screen's initial activity selection. One of
  // 'run', 'walk', 'cycle', 'hike'. Empty / unknown = 'run'.
  static const _kDefaultActivityType = 'default_activity_type';
  // Voice-feedback verbosity: 'full' (default) speaks every cue;
  // 'minimal' suppresses the chatty in-rep progress + pace-drift nudges
  // while keeping start / finish / split / step-transition (round-5 older).
  static const _kVoiceFeedbackVerbosity = 'voice_feedback_verbosity';
  // Mirrors the device-scoped `keep_screen_on` settings-bag key.
  // Defaults true so existing users keep the wakelock-on-during-run
  // behaviour they're used to.
  static const _kKeepScreenOn = 'keep_screen_on';
  // Per-device, never synced: write completed runs back to Android
  // Health Connect so they flow on to Google Fit / Samsung Health / etc.
  // Off by default — writing user data to a third-party store is opt-in
  // (persona #36). Local-only because Health Connect is an Android
  // on-device capability, not a roaming account preference.
  static const _kWriteToHealthConnect = 'write_to_health_connect';
  // Timestamp of the last successful runs-list fetch. Drives the
  // delta-fetch path in RunsScreen so refreshes only pull rows modified
  // since, instead of re-paging the entire history every time.
  static const _kRunsLastFetchedAt = 'runs_last_fetched_at';

  static const _kBatteryOptHintShown = 'battery_opt_hint_shown';

  static const _kNotifDeniedHintShown = 'notif_denied_hint_shown';

  // Stable per-install identifier used to scope `user_device_settings`
  // rows. Minted on first launch and never rotated — rotating would
  // orphan the device's row and lose per-device preferences.
  static const _kDeviceId = 'device_id';
  // Persisted theme mode (light / dark / system). Stored as a string
  // so the value reads cleanly in `flutter:run -d` shared-prefs dumps.
  // Defaults to 'dark' to preserve the original launch experience for
  // users who haven't explicitly chosen.
  static const _kThemeMode = 'theme_mode';
  // Per-device app-language override, stored as a canonical tag ('en',
  // 'pt-BR'). Absent / null means "follow the device locale" — mirrors
  // web's localStorage-only model. Deliberately NOT routed through the
  // synced settings bag: locale is a per-device choice, not a roaming
  // account preference.
  static const _kLocale = 'locale';
  // Mirrors the universal `body_weight_kg` settings-bag key. Drives
  // the run-detail calorie estimate. 0 / unset = use the 70 kg
  // fallback (documented in `_estimatedCalories`).
  static const _kBodyWeightKg = 'body_weight_kg';
  // Mirrors the universal `privacy_default` settings-bag key.
  // Drives the initial `is_public` flag on newly-saved runs. One of
  // 'public' / 'followers' / 'private'. Empty / unknown = 'private'
  // (the conservative default — DB column default is false anyway).
  static const _kPrivacyDefault = 'privacy_default';
  // Mirrors the universal `weight_unit` settings-bag key. Display +
  // entry unit for body / lift weights (Phase 4 gym/nutrition).
  // 'kg' (default) | 'lbs'. Storage stays canonical kg — this only
  // changes how the number is shown and parsed.
  static const _kWeightUnit = 'weight_unit';
  // Phase 4 multi-modal nav (multi_modal.md § "Protect the core runner").
  // When true, the centre Log button starts a run on a single tap (the
  // one-tap primary action a pure runner relies on) and long-press opens
  // the full Log sheet; when false (default) tap opens the sheet and
  // long-press repeats the last logged modality. Per-device, never synced —
  // a nav-shape choice, not a roaming account preference.
  static const _kKeepRunPrimary = 'keep_run_primary';
  // The capture type the user last logged via the Log button —
  // 'run' | 'lift' | 'meal' | 'snack'. Drives both the long-press
  // repeat-last gesture and the Log sheet's most-recent-floats-to-top
  // ordering. Per-device.
  static const _kLastLogType = 'last_log_type';

  // GDPR Art 7(3) / Art 21 withdrawal path for Sentry error reporting.
  // When true, main.dart skips Sentry.init at app launch — the SDK
  // never initialises so no traces, breadcrumbs, or events are
  // emitted. Defaults to false (Sentry on) so existing builds are
  // unchanged; the Settings → Privacy toggle flips it. Takes effect
  // on next app launch (the in-place SentryFlutter.close() path is
  // sentry_flutter-version-fragile and not worth the complexity for
  // a once-per-account toggle). See audit/gdpr (2026-05-25) High.
  static const _kSentryOptOut = 'sentry_opt_out';

  // Legacy key — a single weekly distance goal in km. Migrated into the
  // richer [goals] list on first launch of the new build, then removed.
  static const _kLegacyWeeklyGoalKm = 'weekly_goal_km';

  late SharedPreferences _prefs;
  bool _useMiles = false;
  bool _audioCues = true;
  bool _onboarded = false;
  int _targetPaceSecPerKm = 0;
  List<RunGoal> _goals = [];
  bool _advancedGps = false;
  int _splitIntervalMetres = 0;
  String _deviceId = '';
  String _defaultActivityType = 'run';
  String _voiceFeedbackVerbosity = 'full';
  bool _keepScreenOn = true;
  bool _writeToHealthConnect = false;
  ThemeMode _themeMode = ThemeMode.dark;
  Locale? _locale;
  double? _bodyWeightKg;
  String _privacyDefault = 'private';
  WeightUnit _weightUnit = WeightUnit.kg;
  bool _keepRunPrimary = false;
  String? _lastLogType;
  bool _sentryOptOut = false;

  DistanceUnit get unit => _useMiles ? DistanceUnit.mi : DistanceUnit.km;
  bool get useMiles => _useMiles;
  bool get audioCues => _audioCues;
  bool get onboarded => _onboarded;
  bool get advancedGps => _advancedGps;

  /// Custom split interval in metres. 0 means use the activity-type default
  /// (1 km for run/walk/hike, 5 km for cycling).
  int get splitIntervalMetres => _splitIntervalMetres;

  /// Default activity type for the run screen. Mirrors the universal
  /// `default_activity_type` settings-bag key so the choice roams
  /// across devices. One of 'run', 'walk', 'cycle', 'hike'.
  String get defaultActivityType => _defaultActivityType;

  /// 'full' (default) or 'minimal'. In 'minimal' the chatty in-rep
  /// progress + pace-drift voice cues are suppressed.
  String get voiceFeedbackVerbosity => _voiceFeedbackVerbosity;

  /// Whether the run screen should hold a wakelock while recording.
  /// Mirrors the device-scoped `keep_screen_on` settings-bag key.
  bool get keepScreenOn => _keepScreenOn;

  /// Whether completed runs are written back to Android Health Connect
  /// (persona #36). Local-only, off by default, Android-only at the call
  /// site. Toggled from Settings → Integrations after the user grants
  /// the Health Connect write permission.
  bool get writeToHealthConnect => _writeToHealthConnect;

  /// User's body weight in kg, mirrored from the universal
  /// `body_weight_kg` settings-bag key. Null when the user hasn't set
  /// it — callers (e.g. run-detail calorie estimate) fall through to
  /// a documented default. The web equivalent is the same key on
  /// `user_settings.prefs.body_weight_kg`.
  double? get bodyWeightKg => _bodyWeightKg;

  /// Default visibility for newly-saved runs, mirrored from
  /// `user_settings.prefs.privacy_default`. One of `public` /
  /// `followers` / `private` — only `public` actually flips
  /// `runs.is_public` to true on save (the other two are private
  /// today because there's no followers-only column on `runs`).
  /// Defaults to `private` — matches the DB column default.
  String get privacyDefault => _privacyDefault;

  /// GDPR Art 7(3) / Art 21 withdrawal flag for Sentry error
  /// reporting. When true, `main.dart` skips `SentryFlutter.init`
  /// so no events leave the device. Defaults to false (Sentry on
  /// for opted-in builds). Toggle in Settings → Privacy → "Send
  /// error reports".
  bool get sentryOptOut => _sentryOptOut;

  /// Convenience: should newly-saved runs be marked `is_public=true`?
  /// True only when `privacyDefault == 'public'`. `followers` /
  /// `private` / unknown all return false. Wired into the run-save
  /// path on `run_screen` + `add_run_screen`.
  bool get newRunsArePublic => _privacyDefault == 'public';

  /// Display + entry unit for body / lift weights, mirrored from the
  /// universal `weight_unit` settings-bag key. Storage stays canonical
  /// kg — see [WeightFormat]. Defaults to kg.
  WeightUnit get weightUnit => _weightUnit;

  /// Phase 4 multi-modal nav: when true the centre Log button starts a run
  /// on a single tap (long-press opens the full Log sheet), preserving the
  /// one-tap run start a pure runner relies on. Defaults to false (tap opens
  /// the sheet; long-press repeats the last logged modality).
  bool get keepRunPrimary => _keepRunPrimary;

  Future<void> setKeepRunPrimary(bool v) async {
    _keepRunPrimary = v;
    await _prefs.setBool(_kKeepRunPrimary, v);
    notifyListeners();
  }

  /// The capture type last logged via the Log button — `run` / `lift` /
  /// `meal` / `snack`, or null when nothing has been logged yet. Drives the
  /// long-press repeat-last gesture and the Log sheet's ordering.
  String? get lastLogType => _lastLogType;

  Future<void> setLastLogType(String type) async {
    if (type == _lastLogType) return;
    _lastLogType = type;
    await _prefs.setString(_kLastLogType, type);
    notifyListeners();
  }

  /// Stable per-install device identifier. Minted on first launch.
  String get deviceId => _deviceId;

  /// Persisted theme mode. Hydrated in [init] and updated via
  /// [setThemeMode]; survives app restarts so the user only picks
  /// light/dark once.
  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    await _prefs.setString(_kThemeMode, _themeModeToString(mode));
    notifyListeners();
  }

  /// Per-device app-language override. Null = follow the device locale.
  /// Hydrated in [init] and updated via [setLocale]; survives restarts.
  /// Written to SharedPreferences only — never the synced settings bag,
  /// matching web's localStorage-only locale model.
  Locale? get locale => _locale;

  Future<void> setLocale(Locale? next) async {
    _locale = next;
    if (next == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, localeToTag(next));
    }
    notifyListeners();
  }

  static String _themeModeToString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _themeModeFromString(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  /// Timestamp of the last successful `getRuns` call. Used to drive the
  /// delta-fetch path so refreshing the Runs tab only pulls rows updated
  /// since the last visit. Null means "never fetched" — the first fetch
  /// is full, subsequent ones are deltas.
  DateTime? get runsLastFetchedAt {
    final iso = _prefs.getString(_kRunsLastFetchedAt);
    return iso == null ? null : DateTime.tryParse(iso);
  }

  Future<void> setRunsLastFetchedAt(DateTime when) async {
    await _prefs.setString(_kRunsLastFetchedAt, when.toIso8601String());
  }

  /// Whether the one-time OEM battery-optimisation hint has been shown. Many
  /// Android OEMs (Samsung Stamina, Xiaomi MIUI, OnePlus) kill the recording
  /// foreground service unless the app is exempted from battery optimisation,
  /// which silently drops a long run. We surface a single dismissible hint
  /// before the first long run; this flag keeps it from nagging afterward.
  bool get batteryOptHintShown =>
      _prefs.getBool(_kBatteryOptHintShown) ?? false;

  Future<void> setBatteryOptHintShown() async {
    await _prefs.setBool(_kBatteryOptHintShown, true);
  }

  /// Whether the one-time "notifications are off, the live run notification
  /// won't show" hint has been surfaced. Denying POST_NOTIFICATIONS on
  /// Android 13+ silently no-ops the lock-screen stats; this flag keeps the
  /// disclosure from repeating on every run.
  bool get notifDeniedHintShown =>
      _prefs.getBool(_kNotifDeniedHintShown) ?? false;

  Future<void> setNotifDeniedHintShown() async {
    await _prefs.setBool(_kNotifDeniedHintShown, true);
  }

  /// Target pace in seconds per km (0 means no target). Audio cue triggers
  /// when current pace is more than 30s off in either direction.
  int get targetPaceSecPerKm => _targetPaceSecPerKm;

  /// The user's configured training goals. Immutable view — mutate via
  /// [upsertGoal] / [removeGoal].
  List<RunGoal> get goals => List.unmodifiable(_goals);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _useMiles = _prefs.getBool(_kUseMiles) ?? false;
    _audioCues = _prefs.getBool(_kAudioCues) ?? true;
    _onboarded = _prefs.getBool(_kOnboarded) ?? false;
    _targetPaceSecPerKm = _prefs.getInt(_kTargetPaceSecPerKm) ?? 0;
    _advancedGps = _prefs.getBool(_kAdvancedGps) ?? false;
    _writeToHealthConnect = _prefs.getBool(_kWriteToHealthConnect) ?? false;
    _splitIntervalMetres = _prefs.getInt(_kSplitIntervalMetres) ?? 0;
    _defaultActivityType =
        _prefs.getString(_kDefaultActivityType) ?? 'run';
    _voiceFeedbackVerbosity =
        _prefs.getString(_kVoiceFeedbackVerbosity) ?? 'full';
    _keepScreenOn = _prefs.getBool(_kKeepScreenOn) ?? true;
    _themeMode = _themeModeFromString(_prefs.getString(_kThemeMode));
    _locale = localeFromTag(_prefs.getString(_kLocale));
    final bw = _prefs.getDouble(_kBodyWeightKg);
    _bodyWeightKg = (bw != null && bw > 0) ? bw : null;
    _privacyDefault = _prefs.getString(_kPrivacyDefault) ?? 'private';
    _weightUnit = WeightFormat.unitFromWire(_prefs.getString(_kWeightUnit));
    _keepRunPrimary = _prefs.getBool(_kKeepRunPrimary) ?? false;
    _lastLogType = _prefs.getString(_kLastLogType);
    _sentryOptOut = _prefs.getBool(_kSentryOptOut) ?? false;

    final existingDeviceId = _prefs.getString(_kDeviceId);
    if (existingDeviceId != null && existingDeviceId.isNotEmpty) {
      _deviceId = existingDeviceId;
    } else {
      _deviceId = const Uuid().v4();
      await _prefs.setString(_kDeviceId, _deviceId);
    }

    final rawGoals = _prefs.getString(_kGoalsJson);
    if (rawGoals != null && rawGoals.isNotEmpty) {
      try {
        final list = jsonDecode(rawGoals) as List;
        _goals = list
            .map((e) => RunGoal.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Failed to parse goals JSON: $e');
      }
    }

    // One-shot migration: promote the legacy single weekly-km goal into
    // the new goals list, then drop the legacy key.
    final legacyKm = _prefs.getDouble(_kLegacyWeeklyGoalKm);
    if (legacyKm != null && legacyKm > 0 && _goals.isEmpty) {
      _goals.add(RunGoal(
        id: newGoalId(),
        period: GoalPeriod.week,
        distanceMetres: legacyKm * 1000,
      ));
      await _persistGoals();
    }
    if (_prefs.containsKey(_kLegacyWeeklyGoalKm)) {
      await _prefs.remove(_kLegacyWeeklyGoalKm);
    }
  }

  Future<void> setUseMiles(bool v) async {
    _useMiles = v;
    await _prefs.setBool(_kUseMiles, v);
    notifyListeners();
  }

  Future<void> setAudioCues(bool v) async {
    _audioCues = v;
    await _prefs.setBool(_kAudioCues, v);
    notifyListeners();
  }

  Future<void> setOnboarded(bool v) async {
    _onboarded = v;
    await _prefs.setBool(_kOnboarded, v);
    notifyListeners();
  }

  Future<void> setTargetPaceSecPerKm(int v) async {
    _targetPaceSecPerKm = v;
    await _prefs.setInt(_kTargetPaceSecPerKm, v);
    notifyListeners();
  }

  Future<void> setAdvancedGps(bool v) async {
    _advancedGps = v;
    await _prefs.setBool(_kAdvancedGps, v);
    notifyListeners();
  }

  Future<void> setSplitIntervalMetres(int v) async {
    _splitIntervalMetres = v;
    await _prefs.setInt(_kSplitIntervalMetres, v);
    notifyListeners();
  }

  Future<void> setDefaultActivityType(String v) async {
    _defaultActivityType = v;
    await _prefs.setString(_kDefaultActivityType, v);
    notifyListeners();
  }

  Future<void> setVoiceFeedbackVerbosity(String v) async {
    _voiceFeedbackVerbosity = v;
    await _prefs.setString(_kVoiceFeedbackVerbosity, v);
    notifyListeners();
  }

  Future<void> setSentryOptOut(bool v) async {
    _sentryOptOut = v;
    await _prefs.setBool(_kSentryOptOut, v);
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool v) async {
    _keepScreenOn = v;
    await _prefs.setBool(_kKeepScreenOn, v);
    notifyListeners();
  }

  Future<void> setWriteToHealthConnect(bool v) async {
    _writeToHealthConnect = v;
    await _prefs.setBool(_kWriteToHealthConnect, v);
    notifyListeners();
  }

  /// Update the cached privacy_default. Values outside `public` /
  /// `followers` / `private` fall back to `private` so a corrupt bag
  /// can't promote runs to public by mistake. Driven from
  /// `SettingsSyncService._applyUniversal` whenever the cloud bag's
  /// `privacy_default` lands.
  Future<void> setPrivacyDefault(String v) async {
    final next = (v == 'public' || v == 'followers' || v == 'private')
        ? v
        : 'private';
    if (next == _privacyDefault) return;
    _privacyDefault = next;
    await _prefs.setString(_kPrivacyDefault, next);
    notifyListeners();
  }

  /// Update the cached weight_unit. Any value other than `lbs` resolves
  /// to kg (the canonical default), so a corrupt bag can't produce an
  /// undefined unit. Driven from `SettingsSyncService._applyUniversal`
  /// whenever the cloud universal bag's `weight_unit` lands.
  Future<void> setWeightUnit(WeightUnit unit) async {
    if (unit == _weightUnit) return;
    _weightUnit = unit;
    await _prefs.setString(_kWeightUnit, WeightFormat.label(unit));
    notifyListeners();
  }

  /// Update the cached body-weight value. Passing null (or a
  /// non-positive value) clears it, so the calorie-estimate path
  /// falls back to its documented 70 kg default. Driven from
  /// `SettingsSyncService._applyUniversal` whenever the cloud
  /// universal bag's `body_weight_kg` lands.
  Future<void> setBodyWeightKg(double? v) async {
    final next = (v != null && v > 0) ? v : null;
    if (next == _bodyWeightKg) return;
    _bodyWeightKg = next;
    if (next == null) {
      await _prefs.remove(_kBodyWeightKg);
    } else {
      await _prefs.setDouble(_kBodyWeightKg, next);
    }
    notifyListeners();
  }

  /// Create or update a goal by id.
  Future<void> upsertGoal(RunGoal goal) async {
    final idx = _goals.indexWhere((g) => g.id == goal.id);
    if (idx >= 0) {
      _goals[idx] = goal;
    } else {
      _goals.add(goal);
    }
    await _persistGoals();
    notifyListeners();
  }

  /// Remove the goal with the given id. No-op if not present.
  Future<void> removeGoal(String id) async {
    final before = _goals.length;
    _goals.removeWhere((g) => g.id == id);
    if (_goals.length == before) return;
    await _persistGoals();
    notifyListeners();
  }

  Future<void> _persistGoals() async {
    final payload = jsonEncode(_goals.map((g) => g.toJson()).toList());
    await _prefs.setString(_kGoalsJson, payload);
  }
}

/// Distance/pace formatting helpers that respect the user's unit preference.
class UnitFormat {
  static const _metresPerMile = 1609.344;

  /// Format distance: "5.23 km" or "3.25 mi" (decimal separator follows the
  /// active locale — "5,23 km" in de).
  static String distance(double metres, DistanceUnit unit) {
    return '${distanceValue(metres, unit)} ${distanceLabel(unit)}';
  }

  /// Format distance value only (no unit suffix), localised separator.
  static String distanceValue(double metres, DistanceUnit unit) {
    final value =
        unit == DistanceUnit.mi ? metres / _metresPerMile : metres / 1000;
    return formatFixed(value, 2, activeLocaleTag);
  }

  /// Distance unit label.
  static String distanceLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? 'mi' : 'km';

  /// Format pace: "5:30" (per km/mi based on unit).
  static String pace(double? secondsPerKm, DistanceUnit unit) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '--:--';
    final secondsPerUnit = unit == DistanceUnit.mi
        ? secondsPerKm * (_metresPerMile / 1000)
        : secondsPerKm;
    final m = secondsPerUnit ~/ 60;
    final s = (secondsPerUnit % 60).toInt();
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Pace unit label e.g. "/km" or "/mi".
  static String paceLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? '/mi' : '/km';

  /// How many distance "ticks" (km or mi) the runner has hit so far.
  static int distanceTicks(double metres, DistanceUnit unit) {
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).floor();
    }
    return (metres / 1000).floor();
  }

  /// Number of activity-aware split ticks hit so far (e.g. 5km splits for cycle).
  static int activityTicks(double metres, double intervalMetres) {
    return (metres / intervalMetres).floor();
  }

  /// Format speed: "12.5 km/h" or "7.8 mph" (localised separator).
  static String speed(double? secondsPerKm, DistanceUnit unit) {
    if (secondsPerKm == null || secondsPerKm <= 0) return '--';
    final kmh = 3600 / secondsPerKm;
    final value = unit == DistanceUnit.mi ? kmh / 1.609344 : kmh;
    return formatFixed(value, 1, activeLocaleTag);
  }

  /// Speed unit label e.g. "km/h" or "mph".
  static String speedLabel(DistanceUnit unit) =>
      unit == DistanceUnit.mi ? 'mph' : 'km/h';

  static const _feetPerMetre = 3.28084;

  /// Format cumulative elevation gain: "120 m" / "394 ft". Integer
  /// rounding because sub-metre precision on cumulative gain is the
  /// GPS-noise floor. Null renders as em-dash. Mirrors web
  /// `formatElevation` in `apps/web/src/lib/units.svelte.ts`.
  static String elevation(double? metres, DistanceUnit unit) {
    if (metres == null) return '—';
    if (unit == DistanceUnit.mi) {
      final ft = (metres * _feetPerMetre).round().toDouble();
      return '${formatFixed(ft, 0, activeLocaleTag)} ft';
    }
    return '${formatFixed(metres.round().toDouble(), 0, activeLocaleTag)} m';
  }
}

/// Weight formatting + parsing helpers that respect the user's
/// `weight_unit` preference. Storage is always canonical kilograms
/// (`gym_sets.weight_kg`); these convert only on display + entry — the
/// same display-only split as [UnitFormat] over `preferred_unit`.
/// Mirror of the web `weight_unit` converter (parity is behavioural;
/// keep both sides on the same constant).
class WeightFormat {
  /// Exact kg→lbs factor (1 kg = 2.2046226218 lb).
  static const _lbsPerKg = 2.2046226218;

  static WeightUnit unitFromWire(String? raw) =>
      raw == 'lbs' ? WeightUnit.lbs : WeightUnit.kg;

  /// Convert a canonical-kg value into the display unit.
  static double toDisplay(double kg, WeightUnit unit) =>
      unit == WeightUnit.lbs ? kg * _lbsPerKg : kg;

  /// Convert a display-unit value back into canonical kg for storage.
  static double toKg(double value, WeightUnit unit) =>
      unit == WeightUnit.lbs ? value / _lbsPerKg : value;

  /// Format a canonical-kg weight with one decimal + unit suffix, e.g.
  /// "100.0 kg" / "220.5 lbs" (decimal separator follows the active locale).
  static String format(double? kg, WeightUnit unit) {
    if (kg == null) return '—';
    return '${value(kg, unit)} ${label(unit)}';
  }

  /// Number-only display (no unit suffix), localised separator.
  static String value(double kg, WeightUnit unit) =>
      formatFixed(toDisplay(kg, unit), 1, activeLocaleTag);

  /// Unit label, "kg" or "lbs".
  static String label(WeightUnit unit) =>
      unit == WeightUnit.lbs ? 'lbs' : 'kg';

  /// Parse a user-entered display-unit string into canonical kg. Tolerates
  /// the active locale's decimal comma and a trailing unit suffix. Returns
  /// null on empty / unparseable input.
  static double? parseToKg(String raw, WeightUnit unit) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    s = s.replaceAll('kg', '').replaceAll('lbs', '').replaceAll('lb', '').trim();
    s = s.replaceAll(',', '.');
    final v = double.tryParse(s);
    if (v == null) return null;
    return toKg(v, unit);
  }
}

// ───────────── Global active-preferences accessor ─────────────
//
// Screens that take `Preferences` as a constructor dep can reach the
// user's unit via `widget.preferences.unit`. But several read-only
// surfaces (notification verbs in the activity feed, the recovered-run
// banner on home, club-detail route subtitles, live-spectator stat
// tiles, the TTS announcer) don't take Preferences today and aren't
// worth threading through every callsite.
//
// `registerActivePreferences()` is called once from `main.dart` after
// Preferences is constructed; thereafter `activeDistanceUnit` reads
// the current pref, and the top-level `formatDistanceForPref()` helper
// is a drop-in replacement for the ad-hoc `(metres / 1000) km` strings
// these surfaces carry today. Non-reactive: a pref flip won't rebuild
// a mounted screen, but every list refresh / ping tick re-renders the
// label, which is the cadence these read-only surfaces churn at
// anyway.
Preferences? _activePreferences;

/// Register the global Preferences instance. Call once from main.dart
/// after Preferences.load() completes. Idempotent — re-registering
/// (e.g. in a test) replaces the previous instance.
void registerActivePreferences(Preferences p) {
  _activePreferences = p;
}

/// Current user unit pref. Returns km when no Preferences has been
/// registered (host-test runner, very early app start). Use this
/// rather than constructing Preferences again.
DistanceUnit get activeDistanceUnit =>
    _activePreferences?.unit ?? DistanceUnit.km;

/// Format a distance using the active user unit pref. Drop-in for
/// `'${(metres / 1000).toStringAsFixed(2)} km'` in surfaces that
/// don't carry a Preferences dep.
String formatDistanceForPref(double metres) =>
    UnitFormat.distance(metres, activeDistanceUnit);

/// Format an elevation gain using the active user unit pref. Mirrors
/// `formatElevation` in `apps/web/src/lib/units.svelte.ts`. Null →
/// em-dash.
String formatElevationForPref(double? metres) =>
    UnitFormat.elevation(metres, activeDistanceUnit);

/// Format a pace (seconds per km) using the active user unit pref,
/// including the unit label (`/km` or `/mi`). Drop-in for surfaces that
/// don't carry a Preferences dep — fixes feed/spectator/profile cards
/// hard-coding `/km` for mile-unit users. Non-positive → em-dash.
String formatPaceForPref(double secPerKm) => secPerKm <= 0
    ? '—'
    : '${UnitFormat.pace(secPerKm, activeDistanceUnit)} ${UnitFormat.paceLabel(activeDistanceUnit)}';

/// Current user weight-unit pref. Returns kg when no Preferences has
/// been registered (host-test runner, very early app start). Used by
/// gym surfaces that don't carry a Preferences dep (the compose sheet,
/// detail PR chips) so weight renders + parses in the user's unit.
WeightUnit get activeWeightUnit =>
    _activePreferences?.weightUnit ?? WeightUnit.kg;

@visibleForTesting
void resetActivePreferencesForTest() {
  _activePreferences = null;
}

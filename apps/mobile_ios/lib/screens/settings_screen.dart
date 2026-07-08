import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../ble_heart_rate.dart';
import '../ble_treadmill.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_gear_store.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../dev_auto_login.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../sim_watch_link.dart';
import '../widgets/top_banner.dart';
import 'coaching_screen.dart';
import 'devices_screen.dart';
import 'gear_screen.dart';
import 'settings_account_screen.dart';
import 'settings_integrations_screen.dart';
import 'settings_licenses_screen.dart';
import 'settings_preferences_screen.dart';
import 'settings_pro_screen.dart';
import 'settings_safety_screen.dart';
import 'sign_in_screen.dart';
import 'sim_watch_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;
  final LocalRouteStore? routeStore;
  final LocalGearStore? gearStore;
  final BleHeartRate heartRate;
  final BleTreadmill treadmill;
  final SettingsSyncService? settingsSync;

  /// Backend URL used to gate the developer section. Defaults to the
  /// runtime SUPABASE_URL; only a loopback backend shows the section,
  /// same isolation rail as the seed auto-login.
  final String? devBackendUrl;

  const SettingsScreen({
    super.key,
    this.apiClient,
    required this.preferences,
    required this.heartRate,
    required this.treadmill,
    this.runStore,
    this.routeStore,
    this.gearStore,
    this.settingsSync,
    this.devBackendUrl,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _open(Widget Function(BuildContext) builder) {
    Navigator.push(context, MaterialPageRoute(builder: builder));
  }

  Future<void> _openAfterSignIn(Widget Function(BuildContext) builder) async {
    final api = widget.apiClient;
    if (api == null) {
      showTopBanner(
          context, AppLocalizations.of(context).settingsBackendNotConfigured);
      return;
    }
    if (api.userId != null) {
      _open(builder);
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInScreen(apiClient: api)),
    );
    if (ok == true && mounted) {
      setState(() {});
      _open(builder);
    }
  }

  Widget _tab({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.apiClient;
    final signedIn = api?.userId != null;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionHeader(l10n.settingsSectionProfile),
            _tab(
              icon: Icons.person_outline,
              label: l10n.settingsAccountTitle,
              subtitle: signedIn
                  ? (api?.userEmail?.isNotEmpty ?? false
                      ? api!.userEmail!
                      : l10n.settingsAccountSignedIn)
                  : l10n.settingsTabAccountSubtitle,
              onTap: () => _open((_) => SettingsAccountScreen(
                    apiClient: widget.apiClient,
                    preferences: widget.preferences,
                    settingsSync: widget.settingsSync,
                    runStore: widget.runStore,
                    routeStore: widget.routeStore,
                  )),
            ),
            _tab(
              icon: Icons.tune,
              label: l10n.prefsTitle,
              subtitle: l10n.settingsTabPreferencesSubtitle,
              onTap: () => _open((_) => SettingsPreferencesScreen(
                    apiClient: widget.apiClient,
                    preferences: widget.preferences,
                    settingsSync: widget.settingsSync,
                  )),
            ),
            _tab(
              icon: Icons.health_and_safety_outlined,
              label: l10n.safetyTitle,
              subtitle: l10n.safetyTileSubtitle,
              onTap: () => _openAfterSignIn((_) => SettingsSafetyScreen(
                    api: widget.apiClient,
                    settingsSync: widget.settingsSync,
                  )),
            ),
            _tab(
              icon: Icons.groups_outlined,
              label: l10n.coachingTitle,
              subtitle: l10n.settingsTabCoachingSubtitle,
              onTap: () => _openAfterSignIn((_) => CoachingScreen(
                    api: widget.apiClient!,
                    preferences: widget.preferences,
                  )),
            ),
            _SectionHeader(l10n.settingsSectionAppsData),
            _tab(
              icon: Icons.link,
              label: l10n.integrationsTitle,
              subtitle: l10n.settingsTabIntegrationsSubtitle,
              onTap: () => _open((_) => SettingsIntegrationsScreen(
                    apiClient: widget.apiClient,
                    heartRate: widget.heartRate,
                    treadmill: widget.treadmill,
                    preferences: widget.preferences,
                  )),
            ),
            _tab(
              icon: Icons.devices,
              label: l10n.devicesTitle,
              subtitle: signedIn
                  ? l10n.settingsTabDevicesSubtitle
                  : l10n.settingsDevicesSignedOutSubtitle,
              onTap: () => _openAfterSignIn((_) => DevicesScreen(
                    api: widget.apiClient!,
                    currentDeviceId: widget.preferences.deviceId,
                  )),
            ),
            _tab(
              icon: Icons.directions_run,
              label: l10n.gearTitle,
              subtitle: l10n.settingsTabGearSubtitle,
              onTap: () {
                final gearStore = widget.gearStore;
                if (gearStore == null) return;
                _open((_) => GearScreen(
                      api: widget.apiClient,
                      preferences: widget.preferences,
                      store: gearStore,
                      runStore: widget.runStore,
                    ));
              },
            ),
            _SectionHeader(l10n.settingsSectionAccountLegal),
            _tab(
              icon: Icons.favorite_outline,
              label: l10n.proTitle,
              subtitle: l10n.settingsTabProSubtitle,
              onTap: () => _open((_) => const SettingsProScreen()),
            ),
            _tab(
              icon: Icons.description_outlined,
              label: l10n.licensesTitle,
              subtitle: l10n.settingsTabLicensesSubtitle,
              onTap: () => _open((_) => const SettingsLicensesScreen()),
            ),
            if (isLocalSupabaseUrl(
                widget.devBackendUrl ?? maybeDevBackendUrl())) ...[
              _SectionHeader(l10n.settingsSectionDeveloper),
              _tab(
                icon: Icons.watch_outlined,
                label: l10n.simWatchTitle,
                subtitle: l10n.settingsTabSimWatchSubtitle,
                onTap: () => _open((_) => const SimWatchScreen()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

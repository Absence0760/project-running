import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../ble_heart_rate.dart';
import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';
import '../settings_sync.dart';
import '../widgets/top_banner.dart';
import 'devices_screen.dart';
import 'gear_screen.dart';
import 'settings_account_screen.dart';
import 'settings_integrations_screen.dart';
import 'settings_licenses_screen.dart';
import 'settings_preferences_screen.dart';
import 'settings_pro_screen.dart';
import 'sign_in_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ApiClient? apiClient;
  final Preferences preferences;
  final LocalRunStore? runStore;
  final LocalRouteStore? routeStore;
  final BleHeartRate heartRate;
  final SettingsSyncService? settingsSync;

  const SettingsScreen({
    super.key,
    this.apiClient,
    required this.preferences,
    required this.heartRate,
    this.runStore,
    this.routeStore,
    this.settingsSync,
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
      showTopBanner(context, 'Backend not configured');
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _SectionHeader('Settings', isPageTitle: true),
            const _SectionHeader('Profile'),
            _tab(
              icon: Icons.person_outline,
              label: 'Account',
              subtitle: signedIn
                  ? (api?.userEmail?.isNotEmpty ?? false
                      ? api!.userEmail!
                      : 'Signed in')
                  : 'Sign in, backup, delete account',
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
              label: 'Preferences',
              subtitle: 'Units, theme, recording, training, privacy',
              onTap: () => _open((_) => SettingsPreferencesScreen(
                    preferences: widget.preferences,
                    settingsSync: widget.settingsSync,
                  )),
            ),
            const _SectionHeader('Apps & data'),
            _tab(
              icon: Icons.link,
              label: 'Integrations',
              subtitle: 'Strava, parkrun, heart-rate strap',
              onTap: () => _open((_) => SettingsIntegrationsScreen(
                    apiClient: widget.apiClient,
                    heartRate: widget.heartRate,
                  )),
            ),
            _tab(
              icon: Icons.devices,
              label: 'Devices',
              subtitle: signedIn
                  ? 'Where you\'re signed in and per-device overrides'
                  : 'Sign in to manage your devices',
              onTap: () => _openAfterSignIn((_) => DevicesScreen(
                    api: widget.apiClient!,
                    currentDeviceId: widget.preferences.deviceId,
                  )),
            ),
            _tab(
              icon: Icons.directions_run,
              label: 'Gear',
              subtitle: signedIn
                  ? 'Track shoes + bikes and per-item mileage'
                  : 'Sign in to track shoes and bikes',
              onTap: () => _openAfterSignIn((_) => GearScreen(
                    api: widget.apiClient!,
                    preferences: widget.preferences,
                  )),
            ),
            const _SectionHeader('Account & legal'),
            _tab(
              icon: Icons.favorite_outline,
              label: 'Pro & support',
              subtitle: 'Subscribe, restore purchases, manage billing',
              onTap: () => _open((_) => const SettingsProScreen()),
            ),
            _tab(
              icon: Icons.description_outlined,
              label: 'Licenses',
              subtitle: 'App version and open-source notices',
              onTap: () => _open((_) => const SettingsLicensesScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final bool isPageTitle;
  const _SectionHeader(this.label, {this.isPageTitle = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isPageTitle) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          label,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    }
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

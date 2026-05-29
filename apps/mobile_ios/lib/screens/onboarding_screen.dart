import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../preferences.dart';
import '../settings_sync.dart';

/// First-launch welcome flow. Three info pages, then a privacy-default
/// chooser, followed by the location-permission request. Marks
/// preferences.onboarded = true on completion.
class OnboardingScreen extends StatefulWidget {
  final Preferences preferences;
  final VoidCallback onDone;
  /// Optional — when present, the chosen privacy default is written to
  /// the universal settings bag so it roams and isn't silently
  /// overridden by another device's default (persona #56).
  final SettingsSyncService? settingsSync;

  const OnboardingScreen({
    super.key,
    required this.preferences,
    required this.onDone,
    this.settingsSync,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  /// Default visibility for new runs, chosen on the final onboarding
  /// page. Privacy-by-default for a brand-new runner (persona #56);
  /// matches the web wizard's default so cross-device sync agrees.
  String _privacyDefault = 'private';

  /// Total onboarding pages: the info pages + the privacy chooser.
  int get _pageCount => _pages.length + 1;
  bool get _onPrivacyPage => _page == _pages.length;

  final _pages = const [
    _PageData(
      icon: Icons.directions_run,
      title: 'Track every run',
      description:
          'GPS recording with live map, splits, pace, cadence, and elevation. '
          'Works fully offline — sign in later to sync across devices.',
    ),
    _PageData(
      icon: Icons.route,
      title: 'Follow routes',
      description:
          'Import GPX or KML files, or sync routes from the web app. '
          'Get off-route alerts while you run.',
    ),
    // Background-location disclosure copy mandated by Google Play's
    // location policy: the in-app rationale must run BEFORE the OS
    // permission dialog, must name the specific feature using
    // background location, and must explain what happens if the user
    // declines. Apple's App Review Guideline 5.1.5 also requires the
    // same disclosure in the location strings (covered by
    // NSLocationAlwaysAndWhenInUseUsageDescription on iOS, but the
    // pre-prompt rationale here doubles as the cross-platform copy
    // for the Play disclosure surface). /audit/app-store-privacy May
    // 2026 High closeout.
    _PageData(
      icon: Icons.location_on,
      title: 'Location access',
      description:
          'Threkir records your runs by sampling your GPS location while '
          'the app is in the foreground AND in the background (so it '
          'keeps tracking when your screen is off or you switch apps to '
          'take a photo). Location data is stored on your device and '
          'only uploaded to Threkir\'s servers when you choose to share '
          'or sync a run. If you decline background location, runs will '
          'stop recording the moment you switch away from the app — '
          'you can change this later in Settings → Apps → Threkir → '
          'Permissions.',
    ),
  ];

  Future<void> _next() async {
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Persist the privacy choice locally (drives is_public on every
      // run save) AND push it to the universal bag so it's an explicit
      // value that roams + isn't overridden by another device's default
      // (persona #56). The bag write is best-effort — the local pref is
      // what protects new-run visibility immediately.
      await widget.preferences.setPrivacyDefault(_privacyDefault);
      try {
        await widget.settingsSync?.updateUniversal(
          <String, dynamic>{SettingsKeys.privacyDefault: _privacyDefault},
        );
      } catch (e) {
        debugPrint('onboarding privacy bag write failed (kept local): $e');
      }
      await _requestLocationPermission();
      await widget.preferences.setOnboarded(true);
      if (!mounted) return;
      widget.onDone();
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      final status = await Geolocator.checkPermission();
      if (status == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('Location permission request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  if (index == _pages.length) return _buildPrivacyPage(theme);
                  final p = _pages[index];
                  // The Location page's Play-policy disclosure copy is
                  // long enough to overflow a small phone viewport when
                  // centered in a fixed-height Column. LayoutBuilder +
                  // SingleChildScrollView + ConstrainedBox(minHeight) +
                  // IntrinsicHeight keeps the vertical centering on
                  // pages whose content fits AND falls through to a
                  // scrollable column on the disclosure page.
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: theme.colorScheme.primaryContainer,
                                  ),
                                  child: Icon(p.icon,
                                      size: 60, color: theme.colorScheme.primary),
                                ),
                                const SizedBox(height: 32),
                                Text(
                                  p.title,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  p.description,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.outline,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pageCount, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _onPrivacyPage ? 'Grant permission' : 'Next',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyPage(ThemeData theme) {
    const options = [
      (
        value: 'private',
        icon: Icons.lock_outline,
        title: 'Private',
        subtitle: 'Only you can see your runs. You can share any run later.',
      ),
      (
        value: 'followers',
        icon: Icons.group_outlined,
        title: 'Followers',
        subtitle: 'People who follow you see new runs in their feed.',
      ),
      (
        value: 'public',
        icon: Icons.public,
        title: 'Public',
        subtitle: 'Anyone can find and view your runs.',
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Text(
            'Who sees your runs?',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            'Pick a default for new runs. You can change it any time in '
            'Settings, and override it on any single run.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
          ),
          const SizedBox(height: 20),
          for (final o in options)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _privacyDefault == o.value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline.withValues(alpha: 0.25),
                  width: _privacyDefault == o.value ? 2 : 1,
                ),
              ),
              child: RadioListTile<String>(
                value: o.value,
                groupValue: _privacyDefault,
                onChanged: (v) => setState(() => _privacyDefault = v!),
                secondary: Icon(o.icon, color: theme.colorScheme.primary),
                title: Text(o.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(o.subtitle),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageData {
  final IconData icon;
  final String title;
  final String description;
  const _PageData({
    required this.icon,
    required this.title,
    required this.description,
  });
}

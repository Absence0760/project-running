import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../preferences.dart';

/// First-launch welcome flow. Three swipable pages followed by permission
/// request. Marks preferences.onboarded = true on completion.
class OnboardingScreen extends StatefulWidget {
  final Preferences preferences;
  final VoidCallback onDone;

  const OnboardingScreen({
    super.key,
    required this.preferences,
    required this.onDone,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

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
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
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
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
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
              children: List.generate(_pages.length, (i) {
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
                    _page == _pages.length - 1 ? 'Grant permission' : 'Next',
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

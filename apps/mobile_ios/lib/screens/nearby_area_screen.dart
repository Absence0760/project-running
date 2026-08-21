import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../geocoding.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/confirm_destructive.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';

/// The coarse-area setter behind opt-in "runners nearby" discovery (issue #466).
///
/// The area is a CITY or NEIGHBOURHOOD the runner picks by name — never their
/// live position, and never a map the runner drops a pin on. The chosen
/// centroid is rounded to ~1 km server-side by `set_discoverable_area` before
/// it is stored, and no surface ever reads it back: `my_discoverable_area`
/// returns only the label the runner typed.
///
/// A place search is offered rather than a single geocode-the-top-hit because
/// the runner is publishing this: confirming WHICH "Springfield" they meant is
/// the difference between a coarse area they chose and one guessed for them.
///
/// Reached only from the Settings privacy section while the default-off
/// `ENABLE_NEARBY_RUNNERS` gate is on. Mirrors the area setter on web's
/// `/settings/preferences`.
class NearbyAreaScreen extends StatefulWidget {
  final ApiClient api;

  /// Test seam — production passes null and the search uses the real provider.
  final GeocodingFetcher? geocodingFetcher;

  const NearbyAreaScreen({
    super.key,
    required this.api,
    this.geocodingFetcher,
  });

  @override
  State<NearbyAreaScreen> createState() => _NearbyAreaScreenState();
}

class _NearbyAreaScreenState extends State<NearbyAreaScreen> {
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  String? _label;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  bool _searching = false;
  bool _searched = false;
  bool _searchUnavailable = false;
  List<PlaceResult> _results = const [];

  String get _maptilerKey {
    try {
      return dotenv.env['MAPTILER_KEY'] ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLabel();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _loadLabel() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final label = await widget.api.fetchMyDiscoverableArea();
      if (!mounted) return;
      setState(() {
        _label = label;
        _loading = false;
      });
    } catch (e) {
      debugPrint('nearby area load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _searched = false;
        _searchUnavailable = false;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(value),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    final outcome = await searchPlaces(
      query,
      apiKey: _maptilerKey,
      fetcher: widget.geocodingFetcher,
    );
    if (!mounted) return;
    setState(() {
      _results = outcome.results;
      _searchUnavailable = outcome.isUnavailable;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _pick(PlaceResult place) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final stored = await widget.api.setDiscoverableArea(
        place.lng,
        place.lat,
        place.name,
      );
      if (!mounted) return;
      _searchCtl.clear();
      setState(() {
        _label = stored ?? place.name;
        _results = const [];
        _searched = false;
        _busy = false;
      });
      showTopBanner(context, l10n.nearbyAreaSaved);
    } catch (e) {
      debugPrint('nearby area save failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      showTopBanner(context, l10n.nearbyAreaSaveFailed);
    }
  }

  Future<void> _forget() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.nearbyAreaForgetConfirmTitle,
      body: l10n.nearbyAreaForgetConfirmBody,
      confirmLabel: l10n.nearbyAreaForget,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.clearDiscoverableArea();
      if (!mounted) return;
      setState(() {
        _label = null;
        _busy = false;
      });
      showTopBanner(context, l10n.nearbyAreaForgotten);
    } catch (e) {
      debugPrint('nearby area clear failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      showTopBanner(context, l10n.nearbyAreaForgetFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.nearbyAreaTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              l10n.nearbyAreaExplainer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_loadFailed)
              ErrorState(
                message: l10n.nearbyAreaLoadFailed,
                onRetry: _loadLabel,
              )
            else
              Card(
                child: ListTile(
                  title: Text(
                    _label == null
                        ? l10n.nearbyAreaNone
                        : l10n.nearbyAreaCurrent(_label!),
                  ),
                  trailing: _label == null
                      ? null
                      : TextButton(
                          onPressed: _busy ? null : _forget,
                          style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          child: Text(l10n.nearbyAreaForget),
                        ),
                ),
              ),
            const SizedBox(height: 24),
            Semantics(
              textField: true,
              label: l10n.nearbyAreaSearchHint,
              child: TextField(
                controller: _searchCtl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.nearbyAreaSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_searchUnavailable)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                // A provider that is down must not read as "that place does
                // not exist" — the runner would go looking for another name.
                child: Text(
                  l10n.nearbyAreaSearchUnavailable,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              )
            else if (_searched && _results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  l10n.nearbyAreaNoResults,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final r in _results)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(r.name),
                  enabled: !_busy,
                  onTap: () => _pick(r),
                ),
          ],
        ),
      ),
    );
  }
}

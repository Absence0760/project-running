import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/gen/app_localizations.dart';
import '../race_service.dart';
import '../widgets/error_state.dart';
import '../widgets/top_banner.dart';

/// Race calendar discovery (race_calendar.md). Mirrors the web `/races` page:
/// a name search + distance-band chips + "near a place" geocode over the
/// `search_race_listings` RPC, with a Register link per result and an
/// "Import my result" affordance (manual paste; RunSignUp pull when the
/// provider key is configured). A "Add a race" action submits a crowd listing.
///
/// Reached as a sub-route from the run surface — NOT a bottom-nav destination
/// (the 5-slot ceiling holds, decisions §63).
class RacesScreen extends StatefulWidget {
  final RaceService service;
  final String? mapTilerKey;

  const RacesScreen({super.key, required this.service, this.mapTilerKey});

  @override
  State<RacesScreen> createState() => _RacesScreenState();
}

const _distanceBands = ['', '5k', '10k', 'half', 'marathon', 'ultra'];

class _RacesScreenState extends State<RacesScreen> {
  final _searchCtl = TextEditingController();
  final _placeCtl = TextEditingController();
  Timer? _debounce;
  int _gen = 0;

  String _query = '';
  String _distance = '';
  String _nearPlace = '';

  bool _loading = true;
  bool _error = false;
  List<RaceListingView> _results = const [];
  bool _runSignUpAvailable = false;

  @override
  void initState() {
    super.initState();
    _run();
    _probeRunSignUp();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    _placeCtl.dispose();
    super.dispose();
  }

  Future<void> _probeRunSignUp() async {
    try {
      final ok = await widget.service.isRunSignUpConfigured();
      if (mounted) setState(() => _runSignUpAvailable = ok);
    } catch (_) {
      if (mounted) setState(() => _runSignUpAvailable = false);
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _run);
  }

  Future<void> _run() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final next = await widget.service.searchRaceListings(
        query: _query,
        distance: _distance.isEmpty ? null : _distance,
        nearPlace: _nearPlace.isEmpty ? null : _nearPlace,
        mapTilerKey: widget.mapTilerKey,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _results = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  String _bandLabel(AppLocalizations l, String band) {
    switch (band) {
      case '5k':
        return l.racesDistance5k;
      case '10k':
        return l.racesDistance10k;
      case 'half':
        return l.racesDistanceHalf;
      case 'marathon':
        return l.racesDistanceMarathon;
      case 'ultra':
        return l.racesDistanceUltra;
      default:
        return l.racesDistanceAny;
    }
  }

  Future<void> _openSubmit() async {
    final created = await showRaceListingForm(context, widget.service);
    if (created == true) _run();
  }

  Future<void> _openImport(RaceListingView race) async {
    final done = await showRaceImportSheet(
      context,
      service: widget.service,
      race: race,
      runSignUpAvailable: _runSignUpAvailable,
    );
    if (done == true && mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesImported);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.racesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openSubmit,
        icon: const Icon(Icons.add),
        label: Text(l.racesSubmitRace),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l.racesSearchPlaceholder,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _query = v;
                    _schedule();
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _placeCtl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.place_outlined),
                    hintText: l.racesNearPlace,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _nearPlace = v;
                    _schedule();
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final band in _distanceBands)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_bandLabel(l, band)),
                            selected: _distance == band,
                            onSelected: (_) {
                              setState(() => _distance = band);
                              _run();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildResults(l)),
        ],
      ),
    );
  }

  Widget _buildResults(AppLocalizations l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error) {
      return ErrorState(message: l.racesSearchFailed, onRetry: _run);
    }
    if (_results.isEmpty) {
      return Center(child: Text(l.racesEmpty));
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) => _RaceCard(
        race: _results[i],
        onImport: () => _openImport(_results[i]),
      ),
    );
  }
}

class _RaceCard extends StatelessWidget {
  final RaceListingView race;
  final VoidCallback onImport;

  const _RaceCard({required this.race, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final meta = <String>[
      _formatRaceDate(race.raceDate),
      if (race.distanceM != null) '${(race.distanceM! / 1000).toStringAsFixed(1)} km',
      if (race.locationLabel != null) race.locationLabel!,
      if (race.distanceMAway != null)
        l.racesKmAway((race.distanceMAway! / 1000).toStringAsFixed(1)),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(race.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(meta.join(' · '), style: Theme.of(context).textTheme.bodySmall),
            if (!race.isVerified)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.racesUnverified,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (race.entryUrl != null)
                  OutlinedButton(
                    onPressed: () => _launch(context, race.entryUrl!),
                    child: Text(l.racesRegister),
                  ),
                if (race.resultsUrl != null)
                  OutlinedButton(
                    onPressed: () => _launch(context, race.resultsUrl!),
                    child: Text(l.racesViewResults),
                  ),
                FilledButton(onPressed: onImport, child: Text(l.racesImportResult)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    var ok = false;
    if (uri != null) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          ok = true;
        } else {
          debugPrint('RacesScreen: no handler available for $url');
        }
      } catch (e) {
        debugPrint('RacesScreen: launch failed for $url: $e');
      }
    } else {
      debugPrint('RacesScreen: could not parse URL: $url');
    }
    if (!ok && context.mounted) {
      showTopBanner(context, AppLocalizations.of(context).racesCouldNotOpenLink);
    }
  }
}

String _formatRaceDate(String iso) {
  // YYYY-MM-DD only — display the date part verbatim (locale-agnostic so the
  // calendar day never shifts across zones; mirrors the web card's formatDate).
  return iso.length >= 10 ? iso.substring(0, 10) : iso;
}

/// Manual-listing submit form (modal). Resolves true when a listing was saved.
Future<bool?> showRaceListingForm(BuildContext context, RaceService service) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _RaceListingForm(service: service),
  );
}

class _RaceListingForm extends StatefulWidget {
  final RaceService service;
  const _RaceListingForm({required this.service});

  @override
  State<_RaceListingForm> createState() => _RaceListingFormState();
}

class _RaceListingFormState extends State<_RaceListingForm> {
  final _name = TextEditingController();
  final _date = TextEditingController();
  final _distance = TextEditingController();
  final _location = TextEditingController();
  final _entryUrl = TextEditingController();
  final _resultsUrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _date.dispose();
    _distance.dispose();
    _location.dispose();
    _entryUrl.dispose();
    _resultsUrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _date.text.trim().isNotEmpty && !_saving;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    try {
      await widget.service.submitRaceListing(
        name: _name.text,
        raceDate: _date.text,
        distanceM: int.tryParse(_distance.text.trim()),
        locationLabel: _location.text,
        entryUrl: _entryUrl.text,
        resultsUrl: _resultsUrl.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showTopBanner(context, l.racesSubmitFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.racesEditorTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l.racesFieldName),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _date,
              readOnly: true,
              onTap: _pickDate,
              decoration: InputDecoration(
                labelText: l.racesFieldDate,
                suffixIcon: const Icon(Icons.calendar_today),
              ),
            ),
            TextField(
              controller: _distance,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.racesFieldDistance),
            ),
            TextField(
              controller: _location,
              decoration: InputDecoration(labelText: l.racesFieldLocation),
            ),
            TextField(
              controller: _entryUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l.racesFieldEntryUrl, hintText: 'https://'),
            ),
            TextField(
              controller: _resultsUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l.racesFieldResultsUrl, hintText: 'https://'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l.racesCancel),
        ),
        FilledButton(onPressed: _canSave ? _save : null, child: Text(l.racesSave)),
      ],
    );
  }
}

/// Import a result onto a recorded run / new race run. Offers the RunSignUp
/// pull when the provider is configured, else a manual paste form. Resolves
/// true when a result was imported.
Future<bool?> showRaceImportSheet(
  BuildContext context, {
  required RaceService service,
  required RaceListingView race,
  required bool runSignUpAvailable,
  String? matchRunId,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _RaceImportForm(
      service: service,
      race: race,
      runSignUpAvailable: runSignUpAvailable,
      matchRunId: matchRunId,
    ),
  );
}

class _RaceImportForm extends StatefulWidget {
  final RaceService service;
  final RaceListingView race;
  final bool runSignUpAvailable;
  final String? matchRunId;

  const _RaceImportForm({
    required this.service,
    required this.race,
    required this.runSignUpAvailable,
    this.matchRunId,
  });

  @override
  State<_RaceImportForm> createState() => _RaceImportFormState();
}

class _RaceImportFormState extends State<_RaceImportForm> {
  final _bib = TextEditingController();
  final _chip = TextEditingController();
  final _gun = TextEditingController();
  final _place = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _bib.dispose();
    _chip.dispose();
    _gun.dispose();
    _place.dispose();
    super.dispose();
  }

  bool get _canPaste =>
      !_busy && (_chip.text.trim().isNotEmpty || _gun.text.trim().isNotEmpty);

  Future<void> _runSignUpImport() async {
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      await widget.service.importRaceResult(
        provider: 'runsignup',
        listingId: widget.race.id,
        matchRunId: widget.matchRunId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RunSignUpUnavailable {
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l.integrationsRunsignupUnavailable);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l.racesImportFailed);
      }
    }
  }

  Future<void> _pasteImport() async {
    if (!_canPaste) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    try {
      await widget.service.importRaceResult(
        provider: 'paste',
        listingId: widget.race.id,
        matchRunId: widget.matchRunId,
        result: PastedRaceResult(
          bib: _blank(_bib.text),
          chipTime: _blank(_chip.text),
          gunTime: _blank(_gun.text),
          overallPlace: int.tryParse(_place.text.trim()),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showTopBanner(context, l.racesImportFailed);
      }
    }
  }

  String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.race.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.race.provider == 'runsignup' && widget.runSignUpAvailable)
              FilledButton(
                onPressed: _busy ? null : _runSignUpImport,
                child: Text(l.racesImportResult),
              )
            else if (widget.race.provider == 'runsignup' && !widget.runSignUpAvailable)
              Text(
                l.integrationsRunsignupUnavailable,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(l.racesPasteResultHint, style: Theme.of(context).textTheme.bodySmall),
            TextField(
              controller: _bib,
              decoration: InputDecoration(labelText: l.racesBib),
            ),
            TextField(
              controller: _chip,
              decoration: InputDecoration(labelText: l.racesChipTime, hintText: '1:47:23'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _gun,
              decoration: InputDecoration(labelText: l.racesGunTime, hintText: '1:48:01'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _place,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.racesOverallPlace),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l.racesCancel),
        ),
        FilledButton(
          onPressed: _canPaste ? _pasteImport : null,
          child: Text(l.racesMatchConfirm),
        ),
      ],
    );
  }
}

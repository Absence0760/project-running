import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../local_route_store.dart';
import '../local_run_store.dart';
import '../preferences.dart';

/// Form for adding a run to history without recording it live.
///
/// The user provides date, duration, and distance; they can optionally pick
/// one of their saved routes to prefill the distance. No GPS track is
/// captured — the resulting run has an empty `track` and `metadata` is
/// stamped with `manual_entry: true` so other surfaces can tell it apart
/// from a recorded one.
class AddRunScreen extends StatefulWidget {
  final LocalRunStore runStore;
  final LocalRouteStore routeStore;
  final Preferences preferences;

  const AddRunScreen({
    super.key,
    required this.runStore,
    required this.routeStore,
    required this.preferences,
  });

  @override
  State<AddRunScreen> createState() => _AddRunScreenState();
}

class _AddRunScreenState extends State<AddRunScreen> {
  static const _metresPerMile = 1609.344;
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();
  final _titleCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _distanceCtl = TextEditingController();
  final _hoursCtl = TextEditingController();
  final _minutesCtl = TextEditingController();
  final _secondsCtl = TextEditingController();

  late DateTime _startedAt;
  ActivityType _activityType = ActivityType.run;
  Route? _selectedRoute;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startedAt = DateTime(now.year, now.month, now.day, now.hour);
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _notesCtl.dispose();
    _distanceCtl.dispose();
    _hoursCtl.dispose();
    _minutesCtl.dispose();
    _secondsCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _startedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startedAt.hour,
        _startedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (picked == null) return;
    setState(() {
      _startedAt = DateTime(
        _startedAt.year,
        _startedAt.month,
        _startedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _onRouteSelected(Route? route) {
    setState(() {
      _selectedRoute = route;
      if (route != null) {
        _distanceCtl.text = _formatDistanceForInput(route.distanceMetres);
        if (_titleCtl.text.trim().isEmpty) {
          _titleCtl.text = route.name;
        }
      }
    });
  }

  Future<void> _pickRoute(List<Route> routes, DistanceUnit unit) async {
    final picked = await Navigator.push<_RoutePick>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RoutePickerPage(routes: routes, unit: unit),
      ),
    );
    if (picked == null) return;
    _onRouteSelected(picked.route);
  }

  String _formatDistanceForInput(double metres) {
    final unit = widget.preferences.unit;
    if (unit == DistanceUnit.mi) {
      return (metres / _metresPerMile).toStringAsFixed(2);
    }
    return (metres / 1000).toStringAsFixed(2);
  }

  double? _parseDistanceMetres(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v <= 0) return null;
    return widget.preferences.unit == DistanceUnit.mi
        ? v * _metresPerMile
        : v * 1000;
  }

  Duration? _parseDuration() {
    final h = int.tryParse(_hoursCtl.text.trim().isEmpty ? '0' : _hoursCtl.text.trim());
    final m = int.tryParse(_minutesCtl.text.trim().isEmpty ? '0' : _minutesCtl.text.trim());
    final s = int.tryParse(_secondsCtl.text.trim().isEmpty ? '0' : _secondsCtl.text.trim());
    if (h == null || m == null || s == null) return null;
    if (h < 0 || m < 0 || s < 0) return null;
    final total = Duration(hours: h, minutes: m, seconds: s);
    if (total.inSeconds <= 0) return null;
    return total;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final distance = _parseDistanceMetres(_distanceCtl.text);
    final duration = _parseDuration();
    if (distance == null || duration == null) return;

    setState(() => _saving = true);

    final metadata = <String, dynamic>{
      'activity_type': _activityType.name,
      'manual_entry': true,
    };
    final title = _titleCtl.text.trim();
    if (title.isNotEmpty) metadata['title'] = title;
    final notes = _notesCtl.text.trim();
    if (notes.isNotEmpty) metadata['notes'] = notes;

    final run = Run(
      id: _uuid.v4(),
      startedAt: _startedAt.toUtc(),
      duration: duration,
      distanceMetres: distance,
      source: RunSource.app,
      routeId: _selectedRoute?.id,
      metadata: metadata,
    );

    try {
      await widget.runStore.save(run);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save run: $e')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Run added to history')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = widget.preferences.unit;
    final routes = widget.routeStore.routes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add run'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16),
          children: [
            Text('When', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_formatDate(_startedAt)),
                    onPressed: _pickDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text(_formatTime(_startedAt)),
                    onPressed: _pickTime,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Activity', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ActivityType.values.map((a) {
                final selected = _activityType == a;
                return ChoiceChip(
                  label: Text(a.label),
                  avatar: Icon(a.icon, size: 18),
                  selected: selected,
                  onSelected: (_) => setState(() => _activityType = a),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            if (routes.isNotEmpty) ...[
              Text('Route (optional)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _pickRoute(routes, unit),
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    suffixIcon: _selectedRoute == null
                        ? const Icon(Icons.search)
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear route',
                            onPressed: () => _onRouteSelected(null),
                          ),
                  ),
                  child: Text(
                    _selectedRoute == null
                        ? 'Search saved routes'
                        : '${_selectedRoute!.name} • '
                            '${UnitFormat.distance(_selectedRoute!.distanceMetres, unit)}',
                    style: _selectedRoute == null
                        ? theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          )
                        : theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text('Distance', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _distanceCtl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffixText: UnitFormat.distanceLabel(unit),
              ),
              validator: (v) {
                if (_parseDistanceMetres(v ?? '') == null) {
                  return 'Enter a distance greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('Duration', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            FormField<Duration>(
              validator: (_) =>
                  _parseDuration() == null ? 'Enter a duration' : null,
              builder: (state) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _durationField(_hoursCtl, 'h', state)),
                        const SizedBox(width: 8),
                        Expanded(child: _durationField(_minutesCtl, 'm', state)),
                        const SizedBox(width: 8),
                        Expanded(child: _durationField(_secondsCtl, 's', state)),
                      ],
                    ),
                    if (state.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 12),
                        child: Text(
                          state.errorText!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text('Title (optional)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. Lunchtime loop',
              ),
            ),
            const SizedBox(height: 20),
            Text('Notes (optional)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'How did it feel?',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Save run'),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _durationField(
    TextEditingController ctl,
    String suffix,
    FormFieldState<Duration> state,
  ) {
    return TextField(
      controller: ctl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => state.didChange(null),
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        suffixText: suffix,
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Result wrapper so `Navigator.pop(null)` (dismiss) is distinguishable
/// from "the user picked the No route option" — the latter pops a
/// [_RoutePick] whose `route` field is null.
class _RoutePick {
  final Route? route;
  const _RoutePick(this.route);
}

/// Full-screen searchable route picker. Pushed as a Material full-screen
/// dialog rather than a modal bottom sheet — sheets fight the keyboard
/// animation (viewInsets + FractionallySizedBox both reflow during open),
/// which is the "slow and glitchy" feel users notice. A pushed Scaffold
/// has the OS soft keyboard, AppBar, and list layout all playing by
/// their normal rules.
class _RoutePickerPage extends StatefulWidget {
  final List<Route> routes;
  final DistanceUnit unit;
  const _RoutePickerPage({required this.routes, required this.unit});

  @override
  State<_RoutePickerPage> createState() => _RoutePickerPageState();
}

class _RoutePickerPageState extends State<_RoutePickerPage> {
  final _searchCtl = TextEditingController();
  String _query = '';

  /// Lowercased route names, indexed parallel to `widget.routes`. Filled
  /// once in `initState` so typing a 6-character query doesn't re-allocate
  /// N lowercase strings per keystroke.
  late final List<String> _lowerNames;

  @override
  void initState() {
    super.initState();
    _lowerNames = widget.routes.map((r) => r.name.toLowerCase()).toList();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  List<Route> _filtered() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.routes;
    final out = <Route>[];
    for (var i = 0; i < widget.routes.length; i++) {
      if (_lowerNames[i].contains(q)) out.add(widget.routes[i]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchCtl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: theme.textTheme.titleMedium,
          decoration: const InputDecoration(
            hintText: 'Search routes',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () {
                _searchCtl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: filtered.isEmpty
            ? Center(
                child: Text(
                  'No routes match "$_query"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            : ListView.builder(
                // `+1` for the leading "No route" row.
                itemCount: filtered.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: const Icon(Icons.block),
                      title: const Text('No route'),
                      onTap: () =>
                          Navigator.pop(context, const _RoutePick(null)),
                    );
                  }
                  final route = filtered[index - 1];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.route,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      route.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      UnitFormat.distance(
                        route.distanceMetres,
                        widget.unit,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, _RoutePick(route)),
                  );
                },
              ),
      ),
    );
  }
}

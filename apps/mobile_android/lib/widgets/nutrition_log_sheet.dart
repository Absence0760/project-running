import 'dart:async';

import 'package:flutter/material.dart';

import '../food_search.dart';
import '../l10n/gen/app_localizations.dart';
import '../local_food_store.dart';
import '../nutrition_totals.dart';
import 'full_screen_form.dart';

/// Open the nutrition log composer as a fullscreen dialog. Resolves `true`
/// when a food entry was logged (so the caller can kick a sync), null when
/// the user backed out.
///
/// Flutter twin of web `/nutrition/log`: search Open Food Facts -> tap a
/// result -> confirm portion, with manual macro entry as the no-match
/// fallback. Writes through [LocalFoodStore] so logging works offline.
Future<bool?> showNutritionLogSheet({
  required BuildContext context,
  required LocalFoodStore store,
}) {
  final l10n = AppLocalizations.of(context);
  return showFullScreenForm<bool>(
    context,
    title: l10n.nutritionLogTitle,
    builder: (ctx) => NutritionLogSheet(store: store),
  );
}

class NutritionLogSheet extends StatefulWidget {
  final LocalFoodStore store;

  /// Test seam — inject a canned Open Food Facts fetcher.
  final FoodFetcher? fetcher;
  const NutritionLogSheet({super.key, required this.store, this.fetcher});

  @override
  State<NutritionLogSheet> createState() => _NutritionLogSheetState();
}

class _NutritionLogSheetState extends State<NutritionLogSheet> {
  final _queryCtl = TextEditingController();
  String _mealSlot = 'breakfast';
  bool _searching = false;
  bool _searched = false;
  bool _searchFailed = false;
  List<FoodSearchResult> _results = const [];
  Timer? _debounce;
  bool _manualOpen = false;
  bool _saving = false;
  String? _error;

  final _manualName = TextEditingController();
  final _manualKcal = TextEditingController();
  final _manualProtein = TextEditingController();
  final _manualCarbs = TextEditingController();
  final _manualFat = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtl.dispose();
    _manualName.dispose();
    _manualKcal.dispose();
    _manualProtein.dispose();
    _manualCarbs.dispose();
    _manualFat.dispose();
    super.dispose();
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _queryCtl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _searchFailed = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final res = await searchFoods(q, fetcher: widget.fetcher);
      if (!mounted) return;
      setState(() {
        _results = res;
        _searching = false;
        _searched = true;
      });
    } catch (_) {
      // Distinguish a failed search from a genuinely empty one so the user
      // sees a retry affordance, not a misleading "no matches".
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _searched = true;
        _searchFailed = true;
      });
    }
  }

  Future<void> _pick(FoodSearchResult r) async {
    final l10n = AppLocalizations.of(context);
    final grams = await showDialog<int>(
      context: context,
      builder: (_) => _PortionDialog(result: r, l10n: l10n),
    );
    if (grams == null || grams <= 0) return;
    final m = scalePortion(r, grams.toDouble());
    await _log(
      itemName: r.name,
      calories: m.calories.toDouble(),
      proteinG: m.proteinG.toDouble(),
      carbsG: m.carbsG.toDouble(),
      fatG: m.fatG.toDouble(),
    );
  }

  Future<void> _saveManual() async {
    final name = _manualName.text.trim();
    if (name.isEmpty) return;
    await _log(
      itemName: name,
      calories: double.tryParse(_manualKcal.text),
      proteinG: double.tryParse(_manualProtein.text),
      carbsG: double.tryParse(_manualCarbs.text),
      fatG: double.tryParse(_manualFat.text),
    );
  }

  Future<void> _log({
    required String itemName,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.createLocal(
        startedAt: DateTime.now(),
        itemName: itemName,
        mealSlot: _mealSlot,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('nutrition_log_sheet: save failed: $e');
      if (mounted) {
        setState(() {
          _error = AppLocalizations.of(context).nutritionSaveFailed;
          _saving = false;
        });
      }
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FullScreenFormBody(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _mealSlot,
          decoration: InputDecoration(labelText: l10n.nutritionMealSlot),
          items: [
            for (final s in mealSlots)
              DropdownMenuItem(value: s, child: Text(_slotLabel(l10n, s))),
          ],
          onChanged: (v) => setState(() => _mealSlot = v ?? 'breakfast'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _queryCtl,
          onChanged: _onQuery,
          decoration: InputDecoration(
            labelText: l10n.nutritionSearchHint,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        if (_searching)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l10n.nutritionSearching),
          )
        else if (_results.isNotEmpty)
          ..._results.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text(r.brand == null ? r.name : '${r.name} · ${r.brand}'),
                  subtitle: Text('${r.calories100g.round()} kcal / 100 g'),
                  onTap: _saving ? null : () => _pick(r),
                ),
              ))
        else if (_searchFailed)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.nutritionSearchFailed),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _runSearch,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(l10n.nutritionSearchRetry),
                ),
              ],
            ),
          )
        else if (_searched)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(l10n.nutritionNoResults),
          ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: Icon(_manualOpen ? Icons.expand_less : Icons.expand_more),
          label: Text(l10n.nutritionManualEntry),
          onPressed: () => setState(() => _manualOpen = !_manualOpen),
        ),
        if (_manualOpen) ...[
          TextField(
            controller: _manualName,
            decoration: InputDecoration(labelText: l10n.nutritionItemName),
          ),
          Row(
            children: [
              Expanded(child: _numField(_manualKcal, l10n.nutritionCalories)),
              const SizedBox(width: 8),
              Expanded(child: _numField(_manualProtein, '${l10n.nutritionProtein} (g)')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _numField(_manualCarbs, '${l10n.nutritionCarbs} (g)')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_manualFat, '${l10n.nutritionFat} (g)')),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving || _manualName.text.trim().isEmpty ? null : _saveManual,
            child: Text(l10n.nutritionAdd),
          ),
        ],
      ],
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      );

  String _slotLabel(AppLocalizations l10n, String slot) => switch (slot) {
        'breakfast' => l10n.nutritionSlotBreakfast,
        'lunch' => l10n.nutritionSlotLunch,
        'dinner' => l10n.nutritionSlotDinner,
        _ => l10n.nutritionSlotSnack,
      };
}

class _PortionDialog extends StatefulWidget {
  final FoodSearchResult result;
  final AppLocalizations l10n;
  const _PortionDialog({required this.result, required this.l10n});

  @override
  State<_PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<_PortionDialog> {
  final _grams = TextEditingController(text: '100');

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final g = int.tryParse(_grams.text) ?? 0;
    final m = scalePortion(widget.result, g.toDouble());
    return AlertDialog(
      title: Text(widget.result.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _grams,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.nutritionPortionGrams),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('${m.calories} kcal · ${m.proteinG}g P · ${m.carbsG}g C · ${m.fatG}g F'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.nutritionCancel),
        ),
        FilledButton(
          onPressed: g > 0 ? () => Navigator.of(context).pop(g) : null,
          child: Text(l10n.nutritionAdd),
        ),
      ],
    );
  }
}

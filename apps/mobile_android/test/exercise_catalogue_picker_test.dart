import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_prs.dart' show normaliseExerciseName;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/exercise_catalogue_picker.dart';
import '../lib/widgets/top_banner.dart' show kTopBannerMaxDuration;
import '../lib/widgets/gym_compose_sheet.dart' show GymCatalogueEntry;

/// The behavioural pin the picker shipped without.
///
/// § 1332's third state and § 1334's ordering both landed here with nothing
/// under `test/` naming this widget, so the phone half of two fixes rested on
/// a reading while the web half was pinned five ways. A WIDGET test is the
/// instrument, not the extraction web took: § 1333 chose a pure module because
/// `apps/web` runs its unit suite under `tsx --test`, which cannot compile a
/// Svelte component, and a component harness there would be four
/// devDependencies and a SECOND runner. Flutter's one runner already renders
/// widgets, so the same pin costs nothing here — and it proves strictly more,
/// because it reaches the rendered sentence rather than the value behind it.
/// That is the half § 1333 says only a Playwright case can prove and still
/// owes on the web side.

/// An `ApiClient` whose create is scripted, so the create-custom path runs
/// without Supabase. Constructing the base class is safe as long as nothing
/// reads `_client`, which overriding the one method it would call guarantees.
class _ScriptedApi extends ApiClient {
  _ScriptedApi({this.result, this.fail = false});

  /// The row `createCustomExercise` answers with, or null for a refusal.
  final ExerciseRow? result;

  /// Whether to answer null regardless of [result] — the 23505 / offline path.
  final bool fail;

  /// Every call's arguments, so a test can assert what was SENT rather than
  /// only what came back — the category the picker derives from the dropdown
  /// is not observable any other way.
  final List<({String name, String category})> calls = [];

  @override
  Future<ExerciseRow?> createCustomExercise({
    required String name,
    String category = 'other',
    String modality = 'weight_reps',
  }) async {
    calls.add((name: name, category: category));
    return fail ? null : result;
  }
}

GymCatalogueEntry _entry(
  String id,
  String name,
  String category, {
  String? authorId,
  String? nameKey,
}) =>
    (
      name: name,
      id: id,
      category: category,
      authorId: authorId,
      // The server stamps the key from the name with the same fold, so a
      // fixture that does not override it carries the key that row would have.
      nameKey: nameKey ?? normaliseExerciseName(name),
    );

ExerciseRow _row(String id, String name, String category) => ExerciseRow(
      id: id,
      authorId: 'me',
      name: name,
      // The COLUMN still exists and the DTO still requires it -- decisions 1370
      // removed the key from createCustomExercise's arguments, not from the row.
      nameKey: name.toLowerCase(),
      category: category,
      modality: 'weight_reps',
      lastModifiedAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
    );

/// The three seeded-shaped globals every list case reads.
final _bench = _entry('e1', 'Bench Press', 'chest');
final _squat = _entry('e2', 'Back Squat', 'legs');
final _lunge = _entry('e3', 'Walking Lunge', 'legs');
final _catalogue = [_bench, _squat, _lunge];

/// Pushes the picker as a child route and records what it pops with.
///
/// A route rather than the home widget, because the picker pops on every exit
/// and popping a root route is an error. The returned probe reports the pop
/// value; it stays null until the pick happens.
Future<GymCatalogueEntry? Function()> _open(
  WidgetTester tester, {
  required List<GymCatalogueEntry> catalogue,
  ApiClient? api,
  bool unavailable = false,
  void Function(GymCatalogueEntry)? onCreated,
}) async {
  GymCatalogueEntry? picked;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () async {
              picked = await Navigator.of(ctx).push<GymCatalogueEntry>(
                MaterialPageRoute<GymCatalogueEntry>(
                  builder: (_) => ExerciseCataloguePickerScreen(
                    catalogue: catalogue,
                    api: api,
                    unavailable: unavailable,
                    onCreated: onCreated,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  // Timed pumps, never pumpAndSettle: the search field's cursor blinks
  // forever, so settling never returns.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return () => picked;
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
}

/// Selects a category from the dropdown by its English label.
///
/// The button renders the SELECTED label and the open menu renders every
/// label, so the currently-selected one is ambiguous while the menu is up —
/// which is why each case selects a category it is not already showing.
Future<void> _selectCategory(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButton<String>));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The display names the result list is rendering, in list order.
List<String> _listed(WidgetTester tester) => tester
    .widgetList<ListTile>(find.byType(ListTile))
    .map((t) => (t.title! as Text).data!)
    .toList();

void main() {
  testWidgets('a blank query lists the whole catalogue and offers no create',
      (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    expect(_listed(tester), ['Back Squat', 'Bench Press', 'Walking Lunge']);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('No exercises match.'), findsNothing);
  });

  testWidgets('the category filter narrows the list', (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await _selectCategory(tester, 'Legs');
    expect(_listed(tester), ['Back Squat', 'Walking Lunge']);
  });

  testWidgets('the search folds both sides through the canonical key',
      (tester) async {
    // U+00A0 is whitespace the exercise key collapses and a plain
    // `trim().toLowerCase()` does not: the entry that trapped § 1276.
    final nbsp = [_entry('e9', 'Bench\u00A0Press', 'chest')];
    await _open(tester, catalogue: nbsp, api: _ScriptedApi());
    await _type(tester, 'bench press');
    expect(_listed(tester), ['Bench\u00A0Press']);
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'the entry exists, so nothing may be created under its key');
  });

  testWidgets('an unmatched query offers the create affordance',
      (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await _type(tester, 'Farmer Carry');
    expect(_listed(tester), isEmpty);
    expect(find.text('Add “Farmer Carry” as a custom exercise'), findsOneWidget);
    expect(find.text('No exercises match.'), findsOneWidget);
  });

  testWidgets('a partial match lists the entries and still offers to create',
      (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await _type(tester, 'squat');
    expect(_listed(tester), ['Back Squat']);
    expect(find.text('Add “squat” as a custom exercise'), findsOneWidget,
        reason: '"squat" is not the name of any entry');
  });

  testWidgets('no create affordance without an API client', (tester) async {
    await _open(tester, catalogue: _catalogue);
    await _type(tester, 'Farmer Carry');
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'offline / signed out, browse stays read-only');
    expect(find.text('No exercises match.'), findsOneWidget);
  });

  testWidgets(
      'an exact name hidden by the category filter is explained, not dropped',
      (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await _selectCategory(tester, 'Legs');
    await _type(tester, 'bench press');
    expect(_listed(tester), isEmpty, reason: 'no leg exercise matches');
    expect(find.text('No exercises match.'), findsNothing,
        reason: 'the bare empty sentence is the untruth § 1332 removed');
    expect(
      find.text('“Bench Press” is already in the catalogue, under Chest.'),
      findsOneWidget,
    );
    expect(find.byType(OutlinedButton), findsNothing,
        reason: 'the name is taken whatever category is selected — offering '
            'to create it here is the duplicate-key write § 1332 refused');
  });

  testWidgets('the hidden-exact explanation folds too', (tester) async {
    final nbsp = [_entry('e9', 'Bench\u00A0Press', 'chest'), _squat];
    await _open(tester, catalogue: nbsp, api: _ScriptedApi());
    await _selectCategory(tester, 'Legs');
    await _type(tester, 'BENCH PRESS');
    expect(
      find.text('“Bench\u00A0Press” is already in the catalogue, under Chest.'),
      findsOneWidget,
    );
  });

  testWidgets('an exact match the filter does not hide is simply listed',
      (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await _type(tester, 'bench press');
    expect(_listed(tester), ['Bench Press']);
    expect(find.textContaining('already in the catalogue'), findsNothing,
        reason: 'under "all" a key EQUAL to the query necessarily contains it');
  });

  testWidgets('a partial match under a category is an ordinary empty search',
      (tester) async {
    await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await _selectCategory(tester, 'Legs');
    await _type(tester, 'bench');
    expect(find.text('No exercises match.'), findsOneWidget,
        reason: '"bench" names no entry, so nothing is being hidden');
    expect(find.text('Add “bench” as a custom exercise'), findsOneWidget);
  });

  testWidgets('accented names sort where a reader looks for them',
      (tester) async {
    // § 1334's measured list. A code-unit compare over the key files all
    // three accented names behind "Zercher Squat"; the folded compare puts
    // each where the web picker does.
    final names = [
      'Zercher Squat',
      'Überzug',
      'źcisk',
      'Row',
      'Overhead Press',
      'Élévation latérale',
      'Bench Press',
      'Ab Wheel',
    ];
    // A taller view than the 800x600 default: `ListView.builder` only builds
    // what fits, so a short viewport would assert on a PREFIX of the order and
    // pass whatever the tail did.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(
      tester,
      catalogue: [
        for (var i = 0; i < names.length; i++) _entry('e$i', names[i], 'other'),
      ],
      api: _ScriptedApi(),
    );
    expect(_listed(tester), [
      'Ab Wheel',
      'Bench Press',
      'Élévation latérale',
      'Overhead Press',
      'Row',
      'Überzug',
      'źcisk',
      'Zercher Squat',
    ]);
  });

  testWidgets('two spellings of one name order by id, not by input order',
      (tester) async {
    // The folded compare calls these equal, and Dart's `List.sort` is not
    // stable — without the id tiebreak the pair could swap between rebuilds.
    await _open(
      tester,
      catalogue: [
        _entry('e2', 'bench press', 'chest'),
        _entry('e1', 'Bench Press', 'chest'),
      ],
      api: _ScriptedApi(),
    );
    expect(_listed(tester), ['Bench Press', 'bench press']);
  });

  testWidgets('an owner custom shadowing a global lists both, badged',
      (tester) async {
    // The partial uniques allow it by design (`api_database.md`), so the
    // picker has to render it honestly: two rows under one folded key,
    // distinguishable only by the badge, and no offer to create a third.
    await _open(
      tester,
      catalogue: [
        _bench,
        _entry('e9', 'Bench Press', 'arms', authorId: 'me'),
      ],
      api: _ScriptedApi(),
    );
    await _type(tester, 'bench press');
    expect(_listed(tester), ['Bench Press', 'Bench Press']);
    expect(find.text('Custom'), findsOneWidget,
        reason: 'only the owner row carries the badge');
    expect(find.byType(OutlinedButton), findsNothing);
  });

  // Two rows under one folded key, filed under different categories — the
  // shadow `exercises`' partial uniques allow by design. The catalogue fetch
  // orders by `(name, id)` here and by `name` alone on web, so two rows
  // spelled identically are an unspecified tie there; without an order of its
  // own the explanation names whichever the server happened to return first.
  // Both cases must name the same one. A fresh `testWidgets` per order rather
  // than a loop, because re-pumping the host leaves the pushed picker route on
  // the navigator and the second open never happens.
  final shadowCustom = _entry('e9', 'Bench\u00A0Press', 'arms', authorId: 'me');

  Future<void> expectShadowExplained(
    WidgetTester tester,
    List<GymCatalogueEntry> catalogue,
  ) async {
    await _open(tester, catalogue: catalogue, api: _ScriptedApi());
    await _selectCategory(tester, 'Legs');
    await _type(tester, 'bench press');
    expect(
      find.text('\u201CBench Press\u201D is already in the catalogue, under Chest.'),
      findsOneWidget,
    );
  }

  testWidgets('a shadowed name is explained by the row the list shows first',
      (tester) async {
    await expectShadowExplained(tester, [_bench, shadowCustom, _squat]);
  });

  testWidgets('a shadowed name is explained the same way in the other order',
      (tester) async {
    await expectShadowExplained(tester, [shadowCustom, _bench, _squat]);
  });

  testWidgets('tapping a row pops with that entry', (tester) async {
    final picked = await _open(tester, catalogue: _catalogue, api: _ScriptedApi());
    await tester.tap(find.text('Walking Lunge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(picked()?.id, 'e3');
  });

  testWidgets('creating a custom pops with it and tells the host',
      (tester) async {
    final api = _ScriptedApi(result: _row('new-1', 'Farmer Carry', 'other'));
    GymCatalogueEntry? announced;
    final picked = await _open(
      tester,
      catalogue: _catalogue,
      api: api,
      onCreated: (e) => announced = e,
    );
    await _type(tester, 'Farmer Carry');
    await tester.tap(find.text('Add “Farmer Carry” as a custom exercise'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.calls.single.name, 'Farmer Carry');
    // The key is no longer asserted here because the caller no longer computes
    // one: decisions 1370 removed `nameKey` from createCustomExercise, and the
    // server stamps it. The record this mock collects has no such field, so the
    // analyzer is what refuses a caller that tries to send one, and
    // exercise_key_source_guard_test holds the source-level claim.
    expect(picked()?.id, 'new-1');
    expect(announced?.id, 'new-1',
        reason: 'the host merges it so the id binds without a reload');
  });

  testWidgets('a create under a category is filed there, not under other',
      (tester) async {
    final api = _ScriptedApi(result: _row('new-1', 'Farmer Carry', 'legs'));
    await _open(tester, catalogue: _catalogue, api: api);
    await _selectCategory(tester, 'Legs');
    await _type(tester, 'Farmer Carry');
    await tester.tap(find.text('Add “Farmer Carry” as a custom exercise'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.calls.single.category, 'legs');
  });

  testWidgets('a create under "all" is filed under other', (tester) async {
    final api = _ScriptedApi(result: _row('new-1', 'Farmer Carry', 'other'));
    await _open(tester, catalogue: _catalogue, api: api);
    await _type(tester, 'Farmer Carry');
    await tester.tap(find.text('Add “Farmer Carry” as a custom exercise'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(api.calls.single.category, 'other',
        reason: '"all" is a UI-only sentinel, not a category the column holds');
  });

  testWidgets('a refused create reports it and stays on the picker',
      (tester) async {
    final api = _ScriptedApi(fail: true);
    final picked = await _open(tester, catalogue: _catalogue, api: api);
    await _type(tester, 'Farmer Carry');
    await tester.tap(find.text('Add “Farmer Carry” as a custom exercise'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Couldn't add that exercise."), findsOneWidget);
    expect(picked(), isNull, reason: 'nothing was created, so nothing is picked');
    expect(find.text('Add “Farmer Carry” as a custom exercise'), findsOneWidget,
        reason: 'the affordance comes back so the user can retry');
    // Let the banner's own dismissal timer expire rather than leaving it
    // pending at teardown.
    await tester.pump(kTopBannerMaxDuration);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
      'an unavailable catalogue says so and refuses to call any name free',
      (tester) async {
    // An empty list and an unknown one look identical to every test the picker
    // runs, and only one of them supports the claim the create affordance makes.
    // A failed read left the picker offering to create a name the catalogue
    // already held — which mints a shadow against a seeded global the author's
    // partial unique cannot see, or 23505s against the user's own custom.
    await _open(
      tester,
      catalogue: const [],
      api: _ScriptedApi(),
      unavailable: true,
    );
    expect(
      find.text(
          "Couldn't load the exercise catalogue, so this list may be incomplete."),
      findsOneWidget,
    );
    await _type(tester, 'Farmer Carry');
    expect(find.text('Add “Farmer Carry” as a custom exercise'), findsNothing);
    expect(find.text('No exercises match.'), findsNothing,
        reason: '"nothing matches" is a claim about a catalogue we do not have');
  });

  testWidgets('an unavailable catalogue still shows the rows it does have',
      (tester) async {
    // The list is not deleted on a failed read: a stale entry still binds its
    // id correctly, and dropping it would be a second untruth on top of the
    // first. The notice runs alongside the results, not instead of them.
    final picked = await _open(
      tester,
      catalogue: _catalogue,
      api: _ScriptedApi(),
      unavailable: true,
    );
    expect(
      find.text(
          "Couldn't load the exercise catalogue, so this list may be incomplete."),
      findsOneWidget,
    );
    await tester.tap(find.text('Walking Lunge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(picked()?.id, 'e3');
  });
}

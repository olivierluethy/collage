import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:collage/features/library/library_query.dart';
import 'package:collage/features/library/library_state.dart';
import 'package:collage/features/library/library_view.dart';
import 'package:collage/l10n/app_localizations.dart';
import 'package:collage/models/collage_project.dart';
import 'package:collage/models/layout_template.dart';
import 'package:collage/services/draft_service.dart';
import 'package:collage/services/prefs_service.dart';
import 'package:collage/state/providers.dart';
import 'package:collage/theme/app_theme.dart';

CollageProject _p(String id, String title, DateTime created) => CollageProject(
      id: id,
      title: title,
      createdAt: created.millisecondsSinceEpoch,
      updatedAt: created.millisecondsSinceEpoch,
      ratioLabel: '1:1',
      layout: const LayoutTemplate(
        id: 'one',
        name: 'One',
        family: LayoutFamily.grid,
        slots: [LayoutSlot(id: 's1', rect: Rect.fromLTWH(0, 0, 1, 1))],
      ),
      fills: {},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );

/// In-memory DraftService: no disk, no path_provider. Records bulk calls.
class _FakeDrafts extends DraftService {
  _FakeDrafts(List<CollageProject> initial) : _lib = {for (final p in initial) p.id: p};

  final Map<String, CollageProject> _lib;
  final Map<String, (CollageProject, int)> _trash = {};
  final deleteManyCalls = <Set<String>>[];
  final restoreManyCalls = <Set<String>>[];

  @override
  Future<List<CollageProject>> list() async =>
      _lib.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> deleteMany(Iterable<String> ids) async {
    deleteManyCalls.add(ids.toSet());
    for (final id in ids.toSet()) {
      final p = _lib.remove(id);
      if (p != null) _trash[id] = (p, DateTime.now().millisecondsSinceEpoch);
    }
  }

  @override
  Future<void> delete(String id) => deleteMany([id]);

  @override
  Future<List<(CollageProject, int)>> listTrash() async => _trash.values.toList();

  @override
  Future<void> restoreMany(Iterable<String> ids) async {
    restoreManyCalls.add(ids.toSet());
    for (final id in ids.toSet()) {
      final e = _trash.remove(id);
      if (e != null) _lib[id] = e.$1;
    }
  }

  @override
  Future<void> restore(String id) => restoreMany([id]);
}

/// Mirrors HomeScreen: selection mode swaps the app bar and bottom bar.
class _Host extends ConsumerWidget {
  const _Host();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selecting = ref.watch(librarySelectionProvider) != null;
    return Scaffold(
      appBar: selecting ? const LibrarySelectionAppBar() : AppBar(title: const Text('My Collages')),
      body: LibraryView(onCreate: () {}, onBrowseTemplates: () {}),
      bottomNavigationBar: selecting ? const LibrarySelectionBar() : null,
    );
  }
}

final _seed = [
  _p('a', 'Alpha', DateTime(2026, 10, 1, 10)),
  _p('b', 'Beach', DateTime(2026, 10, 2, 10)),
  _p('c', 'Cake', DateTime(2026, 10, 3, 10)),
  _p('d', 'Dune', DateTime(2026, 9, 4, 10)),
  _p('e', 'Easter', DateTime(2026, 4, 5, 10)),
];

/// Title sort hides the sticky month headers, which currently trip a layout
/// assertion of their own (see the skipped test at the end).
const _titleSort = LibraryQuery(sort: LibrarySort.title);

Future<(ProviderContainer, _FakeDrafts)> _pump(
  WidgetTester tester, {
  String locale = 'en',
  LibraryQuery query = _titleSort,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await PrefsService.create();
  final fake = _FakeDrafts(_seed);
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        draftServiceProvider.overrideWithValue(fake),
        libraryQueryProvider.overrideWith((_) => query),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const _Host(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(_Host)));
  return (container, fake);
}

Set<String> _libIds(ProviderContainer c) => {for (final p in c.read(draftsProvider).requireValue) p.id};

Finder _inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

Future<void> _select(WidgetTester tester, ProviderContainer c, Set<String> ids) async {
  c.read(librarySelectionProvider.notifier).state = ids;
  await tester.pumpAndSettle();
}

Finder get _barTrashButton =>
    find.descendant(of: find.byType(LibrarySelectionBar), matching: find.text('Move to trash'));

void main() {
  testWidgets('the confirmation states the exact count; confirming moves exactly those and Undo restores them',
      (tester) async {
    final (c, fake) = await _pump(tester);
    await _select(tester, c, {'a', 'c', 'e'});
    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(_barTrashButton);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_inDialog('Move 3 collages to trash?'), findsOneWidget);
    expect(_inDialog('Collages in the trash can be restored for ${DraftService.trashDays} days.'), findsOneWidget);

    await tester.tap(_inDialog('Move to trash'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.deleteManyCalls, [
      {'a', 'c', 'e'}
    ]);
    expect(_libIds(c), {'b', 'd'});
    expect(c.read(librarySelectionProvider), isNull, reason: 'selection mode ends');
    expect(find.byType(LibrarySelectionBar), findsNothing);
    expect(find.text('3 collages moved to trash'), findsOneWidget);
    expect((await c.read(trashProvider.future)).length, 3);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(fake.restoreManyCalls, [
      {'a', 'c', 'e'}
    ]);
    expect(_libIds(c), {'a', 'b', 'c', 'd', 'e'});
    expect(c.read(trashProvider).requireValue, isEmpty);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('Cancel leaves the library and the selection untouched', (tester) async {
    final (c, fake) = await _pump(tester);
    await _select(tester, c, {'a', 'b'});
    await tester.tap(_barTrashButton);
    await tester.pumpAndSettle();
    expect(_inDialog('Move 2 collages to trash?'), findsOneWidget);
    await tester.tap(_inDialog('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.deleteManyCalls, isEmpty);
    expect(_libIds(c).length, 5);
    expect(c.read(librarySelectionProvider), {'a', 'b'});
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a single selected collage uses the singular forms', (tester) async {
    final (c, _) = await _pump(tester);
    await _select(tester, c, {'d'});
    await tester.tap(_barTrashButton);
    await tester.pumpAndSettle();
    expect(_inDialog('Move 1 collage to trash?'), findsOneWidget);
    await tester.tap(_inDialog('Move to trash'));
    await tester.pumpAndSettle();
    expect(find.text('1 collage moved to trash'), findsOneWidget);
    expect(_libIds(c), {'a', 'b', 'c', 'e'});
  });

  testWidgets('"Select all collages" then trash names the full count', (tester) async {
    final (c, fake) = await _pump(tester);
    await _select(tester, c, {});
    // Nothing selected yet: the trash button is disabled.
    final btn = tester.widget<ButtonStyleButton>(
        find.ancestor(of: _barTrashButton, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
    expect(btn.onPressed, isNull);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all collages (5)'));
    await tester.pumpAndSettle();
    expect(find.text('5 selected'), findsOneWidget);

    await tester.tap(_barTrashButton);
    await tester.pumpAndSettle();
    expect(_inDialog('Move 5 collages to trash?'), findsOneWidget);
    await tester.tap(_inDialog('Move to trash'));
    await tester.pumpAndSettle();
    expect(fake.deleteManyCalls.single.length, 5);
    expect(find.text('5 collages moved to trash'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(_libIds(c).length, 5);
  });

  testWidgets('"Move all N shown to trash" with a date filter names the count and the period', (tester) async {
    final (c, fake) = await _pump(
      tester,
      query: _titleSort.copyWith(period: DatePeriod.month(2026, 10)),
    );

    // The results row's menu (each card has its own "More actions" too).
    expect(find.text('3 collages'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move all 3 shown to trash'));
    await tester.pumpAndSettle();

    expect(_inDialog('Move 3 collages to trash?'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Created: October 2026')),
      findsOneWidget,
    );
    await tester.tap(_inDialog('Move to trash'));
    await tester.pumpAndSettle();
    expect(fake.deleteManyCalls, [
      {'a', 'b', 'c'}
    ]);
    expect(_libIds(c), {'d', 'e'});

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(fake.restoreManyCalls, [
      {'a', 'b', 'c'}
    ]);
    expect(_libIds(c).length, 5);
  });

  testWidgets('Undo restores only the last batch, not earlier trashed collages', (tester) async {
    final (c, fake) = await _pump(tester);
    await _select(tester, c, {'a'});
    await tester.tap(_barTrashButton);
    await tester.pumpAndSettle();
    await tester.tap(_inDialog('Move to trash'));
    await tester.pumpAndSettle();

    await _select(tester, c, {'b', 'c'});
    await tester.tap(_barTrashButton);
    await tester.pumpAndSettle();
    await tester.tap(_inDialog('Move to trash'));
    await tester.pumpAndSettle();
    expect(find.text('2 collages moved to trash'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(fake.restoreManyCalls.last, {'b', 'c'});
    expect(_libIds(c), {'b', 'c', 'd', 'e'});
    expect(c.read(trashProvider).requireValue.map((e) => e.$1.id), ['a']);
  });

  testWidgets('German: the count and Swiss-spelled texts', (tester) async {
    final (c, _) = await _pump(tester, locale: 'de');
    await _select(tester, c, {'a', 'b', 'c', 'd'});
    final l = AppLocalizations(const Locale('de'));
    await tester.tap(find.descendant(of: find.byType(LibrarySelectionBar), matching: find.text(l.t('moveToTrash'))));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Text)).first);
    expect(title.data, contains('4'));
    expect(title.data, isNot(contains('ß')));
  });

  testWidgets('sticky month headers lay out without errors (default newest-first sort)', (tester) async {
    await _pump(tester, query: const LibraryQuery());
    expect(tester.takeException(), isNull);
    expect(find.text('October 2026'), findsOneWidget);
  });
}

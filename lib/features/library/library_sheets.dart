import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/plural.dart';
import '../../models/collage_project.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import '../../widgets/ui.dart';
import 'library_query.dart';

String _fmt(DateFormat Function(String?) make, String? locale, DateTime d) {
  try {
    return make(locale).format(d);
  } catch (_) {
    return make('en').format(d);
  }
}

/// The filter sheet: date (range picker, year and month chips), template,
/// occasion, ratio and "has video". Only metadata that occurs in [all] is
/// offered. Returns the new query, or null when dismissed.
Future<LibraryQuery?> showLibraryFilterSheet(
  BuildContext context, {
  required List<CollageProject> all,
  required LibraryQuery query,
}) {
  return showModalBottomSheet<LibraryQuery>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(all: all, initial: query),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.all, required this.initial});
  final List<CollageProject> all;
  final LibraryQuery initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late LibraryQuery _q = widget.initial;

  // Facets are derived once from the whole library.
  late final _years = () {
    final m = <int, int>{};
    for (final p in widget.all) {
      final y = DateTime.fromMillisecondsSinceEpoch(p.createdAt).year;
      m[y] = (m[y] ?? 0) + 1;
    }
    return m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$1.compareTo(a.$1));
  }();
  late final _months = monthsWithCollages(widget.all);
  late final _styles = countBy(widget.all, templateStyleKey);
  late final _occasions = countBy(widget.all, (p) => p.occasionId);
  late final _ratios = countBy(widget.all, (p) => p.ratioLabel);
  late final _anyVideo = widget.all.any(hasVideo);

  int? get _year {
    final p = _q.period;
    if (p == null) return null;
    if (p.unit == PeriodUnit.year || p.unit == PeriodUnit.month) return p.start.year;
    return null;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    var first = now;
    var last = now;
    for (final p in widget.all) {
      final t = DateTime.fromMillisecondsSinceEpoch(p.createdAt);
      if (t.isBefore(first)) first = t;
      if (t.isAfter(last)) last = t;
    }
    first = DateTime(first.year, first.month, first.day);
    last = DateTime(last.year, last.month, last.day);
    DateTimeRange? initial = _q.period?.asRange;
    if (initial != null && (initial.start.isBefore(first) || initial.end.isAfter(last))) {
      initial = null;
    }
    final r = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initial,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (r != null) setState(() => _q = _q.copyWith(period: DatePeriod.range(r)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final locale = dateLocaleOf(context);
    final count = applyLibraryQuery(widget.all, _q, l).length;
    final year = _year;

    Widget title(String s) => Padding(
      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.sm),
      child: Text(s, style: context.text.labelMd.copyWith(color: c.textMid)),
    );

    Widget chip(String label, bool selected, VoidCallback onTap, {int? n, bool spec = false}) => ChoiceChip(
      label: Text(n == null ? label : '$label · $n', style: spec ? context.text.spec : null),
      selected: selected,
      onSelected: (_) => setState(onTap),
    );

    final period = _q.period;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              child: Text(l.t('libFilterTitle'), style: context.text.titleMd),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title(l.t('libDateRange')),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(
                        period?.unit == PeriodUnit.custom ? period!.label(l, locale) : l.t('libPickDates'),
                      ),
                    ),
                    if (_years.isNotEmpty) ...[
                      const SizedBox(height: Space.md),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          chip(l.t('libAnyTime'), period == null, () => _q = _q.copyWith(period: null)),
                          for (final (y, n) in _years)
                            chip('$y', year == y && period?.unit == PeriodUnit.year, () {
                              final pick = DatePeriod.year(y);
                              _q = _q.copyWith(period: _q.period == pick ? null : pick);
                            }, n: n),
                        ],
                      ),
                    ],
                    if (year != null) ...[
                      const SizedBox(height: Space.md),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (m, n) in _months.reversed)
                            if (m.year == year)
                              chip(
                                _fmt(DateFormat.MMM, locale, m),
                                period?.unit == PeriodUnit.month && period!.start == m,
                                () {
                                  final pick = DatePeriod.month(m.year, m.month);
                                  _q = _q.copyWith(period: _q.period == pick ? DatePeriod.year(year) : pick);
                                },
                                n: n,
                              ),
                        ],
                      ),
                    ],
                    if (_styles.isNotEmpty) ...[
                      title(l.t('libTemplate')),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (k, n) in _styles)
                            chip(
                              templateStyleLabel(l, k),
                              _q.style == k,
                              () => _q = _q.copyWith(style: _q.style == k ? null : k),
                              n: n,
                            ),
                        ],
                      ),
                    ],
                    if (_occasions.isNotEmpty) ...[
                      title(l.t('libOccasion')),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (k, n) in _occasions)
                            chip(
                              occasionLabel(l, k),
                              _q.occasion == k,
                              () => _q = _q.copyWith(occasion: _q.occasion == k ? null : k),
                              n: n,
                            ),
                        ],
                      ),
                    ],
                    if (_ratios.length > 1) ...[
                      title(l.t('libRatio')),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (k, n) in _ratios)
                            chip(
                              k,
                              _q.ratio == k,
                              () => _q = _q.copyWith(ratio: _q.ratio == k ? null : k),
                              n: n,
                              spec: true,
                            ),
                        ],
                      ),
                    ],
                    if (_anyVideo) ...[
                      const SizedBox(height: Space.md),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.videocam_outlined),
                        title: Text(l.t('libHasVideo')),
                        value: _q.hasVideo,
                        onChanged: (v) => setState(() => _q = _q.copyWith(hasVideo: v)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.xl, Space.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _q.chipCount == 0 ? null : () => setState(() => _q = _q.clearedFilters()),
                    child: Text(l.t('libClearAll')),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: PrimaryButton(
                      label: l.a('libShowResults', {'count': l.p('libCount', count)}),
                      onPressed: () => Navigator.pop(context, _q),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A year/month picker listing only months that have collages. Returns the
/// first day of the picked month.
Future<DateTime?> showJumpToMonth(
  BuildContext context, {
  required List<(DateTime, int)> months,
  DateTime? current,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) {
      final l = sheet.l10n;
      final c = sheet.colors;
      final locale = dateLocaleOf(sheet);
      final rows = <Widget>[];
      int? year;
      for (final (m, n) in months) {
        if (m.year != year) {
          year = m.year;
          rows.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xs),
              child: Semantics(
                header: true,
                child: Text(
                  _fmt(DateFormat.y, locale, m),
                  style: sheet.text.labelMd.copyWith(color: c.textMid),
                ),
              ),
            ),
          );
        }
        final here = current != null && current.year == m.year && current.month == m.month;
        rows.add(
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            selected: here,
            title: Text(_fmt(DateFormat.yMMMM, locale, m)),
            trailing: SpecChip('$n', active: here),
            onTap: () => Navigator.pop(sheet, m),
          ),
        );
      }
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: Text(l.t('libJumpTitle'), style: sheet.text.titleMd),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  children: rows,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

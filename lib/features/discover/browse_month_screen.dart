import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/library_index_service.dart';
import '../../state/library_index.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import 'discover_common.dart';

/// A month of the library as a calendar: each day shows how many photos were
/// taken on it, and a quiet dot when some of them are already in collages.
class BrowseMonthScreen extends ConsumerStatefulWidget {
  const BrowseMonthScreen({super.key, required this.year, required this.month});
  final int year;
  final int month;

  @override
  ConsumerState<BrowseMonthScreen> createState() => _BrowseMonthScreenState();
}

class _BrowseMonthScreenState extends ConsumerState<BrowseMonthScreen> {
  late int _year = widget.year;
  late int _month = widget.month;

  void _goToMonth(int? monthKey) {
    if (monthKey == null) return;
    setState(() {
      _year = monthKey ~/ 100;
      _month = monthKey % 100;
    });
  }

  Future<void> _openDay(int day) async {
    final back = await openDay(context, day, fromMonth: true);
    if (mounted && back != null) _goToMonth(back);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final index = ref.watch(libraryIndexDataProvider);
    final used = ref.watch(usedPerDayProvider);
    final key = monthKeyOf(_year, _month);

    return Scaffold(
      appBar: AppBar(title: Text(monthTitle(context, _year, _month))),
      bottomNavigationBar: CrumbBar(
        prevLabel: l.t('discoverPrevMonth'),
        nextLabel: l.t('discoverNextMonth'),
        onPrev: index?.adjacentMonth(key, -1) == null
            ? null
            : () => _goToMonth(index!.adjacentMonth(key, -1)),
        onNext: index?.adjacentMonth(key, 1) == null
            ? null
            : () => _goToMonth(index!.adjacentMonth(key, 1)),
        crumbs: [
          Crumb('$_year', onTap: () => backToYear(context, ref, _year)),
          Crumb(monthName(context, _month)),
        ],
      ),
      body: index == null
          ? const Center(child: CircularProgressIndicator())
          : _MonthBody(
              year: _year,
              month: _month,
              counts: index.dayCounts(_year, _month),
              used: used,
              onDay: _openDay,
            ),
    );
  }
}

class _MonthBody extends StatelessWidget {
  const _MonthBody({
    required this.year,
    required this.month,
    required this.counts,
    required this.used,
    required this.onDay,
  });

  final int year;
  final int month;
  final Map<int, int> counts; // day of month → photos
  final Map<int, int> used; // day key → photos already in collages
  final ValueChanged<int> onDay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ml = MaterialLocalizations.of(context);
    final first = ml.firstDayOfWeekIndex; // 0 = Sunday
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    // DateTime.weekday: Mon=1..Sun=7 → 0=Sunday based.
    final offset = (DateTime(year, month).weekday % 7 - first + 7) % 7;
    final total = counts.values.fold(0, (a, b) => a + b);
    var usedTotal = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      usedTotal += used[year * 10000 + month * 100 + d] ?? 0;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.xl),
      children: [
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SpecChip(photosLabel(context, total), icon: Icons.photo_camera_outlined),
            if (usedTotal > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UsedDot(),
                  const SizedBox(width: Space.xs),
                  Text(usedLabel(context, usedTotal),
                      style: context.text.caption.copyWith(color: c.textLo)),
                ],
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    ml.narrowWeekdays[(first + i) % 7],
                    textAlign: TextAlign.center,
                    style: context.text.caption.copyWith(color: c.textLo),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: Space.xs,
            crossAxisSpacing: Space.xs,
            mainAxisExtent: 56,
          ),
          itemCount: offset + daysInMonth,
          itemBuilder: (context, i) {
            if (i < offset) return const SizedBox.shrink();
            final d = i - offset + 1;
            final key = year * 10000 + month * 100 + d;
            return _DayCell(
              dayKey: key,
              day: d,
              count: counts[d] ?? 0,
              used: used[key] ?? 0,
              onTap: counts[d] == null ? null : () => onDay(key),
            );
          },
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayKey,
    required this.day,
    required this.count,
    required this.used,
    required this.onTap,
  });

  final int dayKey;
  final int day;
  final int count;
  final int used;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final has = count > 0;
    final label = [
      dayTitle(context, dayKey),
      if (has) photosLabel(context, count),
      if (used > 0) usedLabel(context, used),
    ].join(', ');
    return Semantics(
      button: has,
      enabled: has,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: has ? c.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.control),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$day',
                        style: context.text.labelMd
                            .copyWith(color: has ? c.textHi : c.textDisabled)),
                    if (has)
                      Text(formatCount(context, count),
                          style: context.text.spec.copyWith(fontSize: 11, color: c.textMid)),
                  ],
                ),
              ),
              if (used > 0)
                const Positioned(top: 5, right: 5, child: UsedDot()),
            ],
          ),
        ),
      ),
    );
  }
}

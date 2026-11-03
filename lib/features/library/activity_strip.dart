import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/plural.dart';
import '../../models/collage_project.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/meta_date.dart';
import 'library_query.dart';

/// One bar of the activity strip.
class _Bucket {
  _Bucket(this.period, this.count);
  final DatePeriod period;
  int count;
}

/// A compact, collapsible bar chart of when collages were made — per day,
/// week or month, and per hour once a single day is picked. Tapping a bar
/// filters the library to that period; tapping it again clears the filter.
///
/// Collapsed by default; the open/closed state is remembered.
class ActivityStrip extends ConsumerStatefulWidget {
  const ActivityStrip({super.key, required this.collages, required this.period, required this.onPick});

  /// The collages to chart (the library with every filter but the date one).
  final List<CollageProject> collages;

  /// The active date filter, highlighted in the chart.
  final DatePeriod? period;
  final ValueChanged<DatePeriod?> onPick;

  @override
  ConsumerState<ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends ConsumerState<ActivityStrip> {
  late bool _open = ref.read(prefsProvider).libraryActivityOpen;
  PeriodUnit _unit = PeriodUnit.month;

  void _toggle() {
    setState(() => _open = !_open);
    ref.read(prefsProvider).setLibraryActivityOpen(_open);
  }

  /// Showing the hours of one day (after a day or an hour was picked).
  DateTime? get _hoursOf {
    final p = widget.period;
    if (p == null) return null;
    if (p.unit == PeriodUnit.day || p.unit == PeriodUnit.hour) {
      return DateTime(p.start.year, p.start.month, p.start.day);
    }
    return null;
  }

  int get _firstWeekday {
    final idx = MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0 = Sunday
    return idx == 0 ? DateTime.sunday : idx;
  }

  /// Buckets newest first, from now back to the oldest collage, including
  /// empty ones so gaps read as gaps.
  List<_Bucket> _buckets() {
    final day = _hoursOf;
    if (day != null) {
      final out = [
        for (var h = 23; h >= 0; h--) _Bucket(DatePeriod.hour(DateTime(day.year, day.month, day.day, h)), 0),
      ];
      for (final p in widget.collages) {
        final t = DateTime.fromMillisecondsSinceEpoch(p.createdAt);
        if (t.year == day.year && t.month == day.month && t.day == day.day) {
          out[23 - t.hour].count++;
        }
      }
      return out;
    }
    if (widget.collages.isEmpty) return const [];
    DatePeriod of(DateTime d) => switch (_unit) {
      PeriodUnit.day => DatePeriod.day(d),
      PeriodUnit.week => DatePeriod.week(d, firstWeekday: _firstWeekday),
      _ => DatePeriod.month(d.year, d.month),
    };
    var oldest = DateTime.now();
    var newest = DateTime.now();
    final counts = <DateTime, int>{};
    for (final p in widget.collages) {
      final t = DateTime.fromMillisecondsSinceEpoch(p.createdAt);
      if (t.isBefore(oldest)) oldest = t;
      if (t.isAfter(newest)) newest = t;
      final k = of(t).start;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final out = <_Bucket>[];
    var cur = of(newest);
    final stop = of(oldest).start;
    // Guard against pathological dates (e.g. a clock set decades off).
    while (!cur.start.isBefore(stop) && out.length < 20000) {
      out.add(_Bucket(cur, counts[cur.start] ?? 0));
      cur = of(cur.start.subtract(const Duration(hours: 1)));
    }
    return out;
  }

  String _short(DatePeriod p, String? locale) {
    String f(DateFormat Function(String?) make) {
      try {
        return make(locale).format(p.start);
      } catch (_) {
        return make('en').format(p.start);
      }
    }

    return switch (p.unit) {
      PeriodUnit.hour => f(DateFormat.H),
      PeriodUnit.day => p.start.day == 1 ? f(DateFormat.MMM) : f(DateFormat.d),
      PeriodUnit.week => f(DateFormat.Md),
      _ => p.start.month == 1 ? f(DateFormat.y) : f(DateFormat.MMM),
    };
  }

  String _long(AppLocalizations l, DatePeriod p, String? locale) {
    if (p.unit == PeriodUnit.day) {
      try {
        return DateFormat.yMMMMd(locale).format(p.start);
      } catch (_) {
        return DateFormat.yMMMMd('en').format(p.start);
      }
    }
    return p.label(l, locale);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final hoursOf = _hoursOf;

    final header = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(Radii.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.touchTarget),
          child: Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 20, color: c.textMid),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  _open ? l.t('libHideActivity') : l.t('libShowActivity'),
                  style: context.text.labelMd.copyWith(color: c.textMid),
                ),
              ),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.textMid),
            ],
          ),
        ),
      ),
    );

    Widget body = const SizedBox(width: double.infinity);
    if (_open) {
      final locale = dateLocaleOf(context);
      final buckets = _buckets();
      final max = buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hoursOf != null)
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => widget.onPick(null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(l.t('libBackToDays')),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    l.a('libHoursOf', {'date': DatePeriod.day(hoursOf).label(l, locale)}),
                    style: context.text.caption.copyWith(color: c.textMid),
                  ),
                ),
              ],
            )
          else
            SegmentedButton<PeriodUnit>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: PeriodUnit.day, label: Text(l.t('libByDay'))),
                ButtonSegment(value: PeriodUnit.week, label: Text(l.t('libByWeek'))),
                ButtonSegment(value: PeriodUnit.month, label: Text(l.t('libByMonth'))),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: 120,
            child: ListView.builder(
              // Newest at the right edge, where the strip opens.
              reverse: true,
              scrollDirection: Axis.horizontal,
              itemCount: buckets.length,
              itemBuilder: (_, i) {
                final b = buckets[i];
                final active = widget.period == b.period;
                return _Bar(
                  label: _short(b.period, locale),
                  semantics: l.a('libBarLabel', {
                    'period': _long(l, b.period, locale),
                    'count': l.p('libCount', b.count),
                  }),
                  fraction: max == 0 ? 0 : b.count / max,
                  count: b.count,
                  active: active,
                  onTap: () => widget.onPick(active ? null : b.period),
                );
              },
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          AnimatedSize(
            duration: reduce ? Duration.zero : Motion.base,
            curve: Motion.standard,
            alignment: Alignment.topCenter,
            child: body,
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.semantics,
    required this.fraction,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String semantics;
  final double fraction;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.amber : (count > 0 ? c.textLo : c.line);
    return Semantics(
      button: true,
      selected: active,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.chip),
        child: Container(
          width: 40,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: Space.xs),
          decoration: active
              ? BoxDecoration(color: c.amberTint, borderRadius: BorderRadius.circular(Radii.chip))
              : null,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (_, box) => Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 14,
                      // Any non-empty period gets at least a visible stub.
                      height: count == 0 ? 2 : (box.maxHeight * fraction).clamp(4.0, box.maxHeight),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: context.text.caption.copyWith(color: active ? c.amber : c.textLo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

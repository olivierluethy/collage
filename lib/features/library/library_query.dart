import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/occasion_service.dart';
import '../../models/collage_project.dart';
import '../../models/collage_template.dart';
import '../../widgets/meta_date.dart';

/// How the library is ordered.
enum LibrarySort { newest, oldest, edited, title }

/// The granularity of a [DatePeriod] (drives its label and the histogram).
enum PeriodUnit { hour, day, week, month, year, custom }

/// A half-open span of local time `[start, end)` that a collage's creation
/// date must fall into, plus the unit it was picked at.
@immutable
class DatePeriod {
  const DatePeriod(this.start, this.end, this.unit);

  final DateTime start;
  final DateTime end;
  final PeriodUnit unit;

  factory DatePeriod.hour(DateTime d) {
    final s = DateTime(d.year, d.month, d.day, d.hour);
    return DatePeriod(s, DateTime(d.year, d.month, d.day, d.hour + 1), PeriodUnit.hour);
  }

  factory DatePeriod.day(DateTime d) =>
      DatePeriod(DateTime(d.year, d.month, d.day), DateTime(d.year, d.month, d.day + 1), PeriodUnit.day);

  /// The week containing [d], starting on [firstWeekday] (1 = Monday).
  factory DatePeriod.week(DateTime d, {int firstWeekday = DateTime.monday}) {
    final back = (d.weekday - firstWeekday) % 7;
    final s = DateTime(d.year, d.month, d.day - back);
    return DatePeriod(s, DateTime(s.year, s.month, s.day + 7), PeriodUnit.week);
  }

  factory DatePeriod.month(int year, int month) =>
      DatePeriod(DateTime(year, month), DateTime(year, month + 1), PeriodUnit.month);

  factory DatePeriod.year(int year) => DatePeriod(DateTime(year), DateTime(year + 1), PeriodUnit.year);

  /// From a [DateTimeRange] as returned by `showDateRangePicker` (end day
  /// inclusive).
  factory DatePeriod.range(DateTimeRange r) => DatePeriod(
    DateTime(r.start.year, r.start.month, r.start.day),
    DateTime(r.end.year, r.end.month, r.end.day + 1),
    PeriodUnit.custom,
  );

  bool contains(int epochMillis) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    return !t.isBefore(start) && t.isBefore(end);
  }

  /// Inclusive range for `showDateRangePicker`'s initial value.
  DateTimeRange get asRange => DateTimeRange(start: start, end: DateTime(end.year, end.month, end.day - 1));

  /// A short, locale-aware label: "3 Nov 2026", "November 2026", "2026",
  /// "3 Nov 2026, 14:00", "Week of 2 Nov 2026", "1 Mar – 14 Apr 2026".
  String label(AppLocalizations l, String? locale) {
    String f(DateFormat Function(String?) make, DateTime d) {
      try {
        return make(locale).format(d);
      } catch (_) {
        return make('en').format(d);
      }
    }

    return switch (unit) {
      PeriodUnit.hour => '${f(DateFormat.yMMMd, start)}, ${f(DateFormat.Hm, start)}–${f(DateFormat.Hm, end)}',
      PeriodUnit.day => f(DateFormat.yMMMd, start),
      PeriodUnit.week => l.a('libWeekOf', {'date': f(DateFormat.yMMMd, start)}),
      PeriodUnit.month => f(DateFormat.yMMMM, start),
      PeriodUnit.year => f(DateFormat.y, start),
      PeriodUnit.custom =>
        '${f(DateFormat.yMMMd, start)} – '
            '${f(DateFormat.yMMMd, DateTime(end.year, end.month, end.day - 1))}',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DatePeriod && other.start == start && other.end == end && other.unit == unit;

  @override
  int get hashCode => Object.hash(start, end, unit);
}

const _unset = Object();

/// Everything that narrows or orders the My Collages list.
@immutable
class LibraryQuery {
  const LibraryQuery({
    this.text = '',
    this.period,
    this.style,
    this.occasion,
    this.ratio,
    this.hasVideo = false,
    this.sort = LibrarySort.newest,
  });

  /// Free-text search over title, template name and occasion.
  final String text;

  /// Creation date must fall into this period.
  final DatePeriod? period;

  /// Template style key (see [templateStyleKey]); [ownTemplateKey] for a
  /// collage started from one of the user's own templates.
  final String? style;
  final String? occasion;
  final String? ratio;
  final bool hasVideo;
  final LibrarySort sort;

  bool get hasFilters =>
      text.trim().isNotEmpty ||
      period != null ||
      style != null ||
      occasion != null ||
      ratio != null ||
      hasVideo;

  /// Filters other than the free-text search (shown as removable chips).
  int get chipCount =>
      (period != null ? 1 : 0) +
      (style != null ? 1 : 0) +
      (occasion != null ? 1 : 0) +
      (ratio != null ? 1 : 0) +
      (hasVideo ? 1 : 0);

  LibraryQuery copyWith({
    String? text,
    Object? period = _unset,
    Object? style = _unset,
    Object? occasion = _unset,
    Object? ratio = _unset,
    bool? hasVideo,
    LibrarySort? sort,
  }) => LibraryQuery(
    text: text ?? this.text,
    period: identical(period, _unset) ? this.period : period as DatePeriod?,
    style: identical(style, _unset) ? this.style : style as String?,
    occasion: identical(occasion, _unset) ? this.occasion : occasion as String?,
    ratio: identical(ratio, _unset) ? this.ratio : ratio as String?,
    hasVideo: hasVideo ?? this.hasVideo,
    sort: sort ?? this.sort,
  );

  /// Same sort and search, no other filters.
  LibraryQuery clearedFilters() => LibraryQuery(text: text, sort: sort);

  @override
  bool operator ==(Object other) =>
      other is LibraryQuery &&
      other.text == text &&
      other.period == period &&
      other.style == style &&
      other.occasion == occasion &&
      other.ratio == ratio &&
      other.hasVideo == hasVideo &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(text, period, style, occasion, ratio, hasVideo, sort);
}

// ---- metadata helpers --------------------------------------------------------

/// Key for collages started from one of the user's own templates.
const ownTemplateKey = '_own';

/// The template style of a collage, parsed from its catalog template id
/// (`<style>-<count>-<ratio>-<variant>`), [ownTemplateKey] for any other
/// template id, or null when it wasn't started from a template.
String? templateStyleKey(CollageProject p) {
  final id = p.templateId;
  if (id == null || id.isEmpty) return null;
  final head = id.split('-').first;
  return TemplateStyle.values.any((s) => s.name == head) ? head : ownTemplateKey;
}

/// Localised template style name ("Birthday"), or "My template".
String templateStyleLabel(AppLocalizations l, String key) {
  if (key == ownTemplateKey) return l.t('libOwnTemplate');
  final k = 'style${key[0].toUpperCase()}${key.substring(1)}';
  return AppLocalizations.maps['en']!.containsKey(k) ? l.t(k) : _humanize(key);
}

/// Localised occasion name from the occasion calendar; falls back to an
/// `occasion<Id>` string, then a readable form of the id ("new_year" →
/// "New year").
String occasionLabel(AppLocalizations l, String id) {
  final known = OccasionService.byId(id);
  if (known != null) return l.t(known.nameKey);
  final camel = id
      .split(RegExp(r'[_\-\s]+'))
      .where((s) => s.isNotEmpty)
      .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
      .join();
  for (final k in ['occasion$camel', 'occasion_$id']) {
    if (AppLocalizations.maps['en']!.containsKey(k)) return l.t(k);
  }
  return _humanize(id);
}

String _humanize(String id) {
  final s = id.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return s.isEmpty ? id : '${s[0].toUpperCase()}${s.substring(1)}';
}

bool hasVideo(CollageProject p) => p.fills.values.any((f) => f.isVideo);

// ---- filtering, sorting, grouping ---------------------------------------------

/// Apply [q] to [all]. [l] provides the localised names searched alongside
/// the title. With [ignorePeriod] the date filter is skipped (the activity
/// strip shows the distribution of everything else).
List<CollageProject> applyLibraryQuery(
  List<CollageProject> all,
  LibraryQuery q,
  AppLocalizations l, {
  bool ignorePeriod = false,
}) {
  final needle = q.text.trim().toLowerCase();
  final out = <CollageProject>[];
  for (final p in all) {
    if (!ignorePeriod && q.period != null && !q.period!.contains(p.createdAt)) continue;
    final style = templateStyleKey(p);
    if (q.style != null && style != q.style) continue;
    if (q.occasion != null && p.occasionId != q.occasion) continue;
    if (q.ratio != null && p.ratioLabel != q.ratio) continue;
    if (q.hasVideo && !hasVideo(p)) continue;
    if (needle.isNotEmpty) {
      final hay = StringBuffer(p.title.toLowerCase());
      if (style != null) hay.write(' ${templateStyleLabel(l, style).toLowerCase()}');
      if (p.occasionId != null) hay.write(' ${occasionLabel(l, p.occasionId!).toLowerCase()}');
      if (!hay.toString().contains(needle)) continue;
    }
    out.add(p);
  }
  switch (q.sort) {
    case LibrarySort.newest:
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case LibrarySort.oldest:
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    case LibrarySort.edited:
      out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case LibrarySort.title:
      out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }
  return out;
}

/// The timestamp a collage is shown and grouped by under [sort].
int shownStamp(CollageProject p, LibrarySort sort) => sort == LibrarySort.edited ? p.updatedAt : p.createdAt;

/// One month of the library: its first day and the collages in it, in the
/// list's order.
class MonthSection {
  MonthSection(this.month, this.items);
  final DateTime month;
  final List<CollageProject> items;
}

/// Split an already-sorted list into month sections. Sorting by title gives a
/// single section with no month (headers are hidden then).
List<MonthSection> groupByMonth(List<CollageProject> sorted, LibrarySort sort) {
  if (sorted.isEmpty) return const [];
  if (sort == LibrarySort.title) return [MonthSection(DateTime(0), sorted)];
  final out = <MonthSection>[];
  for (final p in sorted) {
    final d = DateTime.fromMillisecondsSinceEpoch(shownStamp(p, sort));
    final m = DateTime(d.year, d.month);
    if (out.isEmpty || out.last.month != m) {
      out.add(MonthSection(m, [p]));
    } else {
      out.last.items.add(p);
    }
  }
  return out;
}

/// Counts of a metadata value across [list], in descending count order.
List<(String, int)> countBy(Iterable<CollageProject> list, String? Function(CollageProject) key) {
  final m = <String, int>{};
  for (final p in list) {
    final k = key(p);
    if (k != null) m[k] = (m[k] ?? 0) + 1;
  }
  final out = m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

/// Months (first day) that have collages, with their counts, newest first.
List<(DateTime, int)> monthsWithCollages(Iterable<CollageProject> list) {
  final m = <DateTime, int>{};
  for (final p in list) {
    final d = DateTime.fromMillisecondsSinceEpoch(p.createdAt);
    final k = DateTime(d.year, d.month);
    m[k] = (m[k] ?? 0) + 1;
  }
  final out = m.entries.map((e) => (e.key, e.value)).toList()..sort((a, b) => b.$1.compareTo(a.$1));
  return out;
}

/// Label of [period] for chips and confirmations, with the current locale.
String periodLabel(BuildContext context, DatePeriod period) =>
    period.label(context.l10n, dateLocaleOf(context));

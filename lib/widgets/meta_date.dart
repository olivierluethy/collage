import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../l10n/plural.dart';
import '../theme/palette.dart';
import '../theme/typography.dart';

/// The locale name for `intl` formatting, from the widget tree.
String? dateLocaleOf(BuildContext context) => Localizations.maybeLocaleOf(context)?.toString();

DateFormat _safe(DateFormat Function(String? locale) make, String? localeName) {
  try {
    return make(localeName);
  } catch (_) {
    // Locale data not loaded (e.g. a bare test app): fall back to English.
    return make('en');
  }
}

/// Formats a raw epoch-millis timestamp for display, following the current
/// locale: a short date (`3 Nov 2026`, `03.11.2026`, `2026年11月3日`) plus, when
/// [withTime] is true, the 24h time (`· 14:05`). The timestamp is always stored
/// raw; formatting happens only here.
String formatCollageDate(int epochMillis, {String? localeName, bool withTime = true}) {
  if (epochMillis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  final date = _safe(DateFormat.yMMMd, localeName).format(dt);
  if (!withTime) return date;
  return '$date · ${_safe(DateFormat.Hm, localeName).format(dt)}';
}

/// The full, unabbreviated date and time ("Tuesday, 3 November 2026 14:05"),
/// for screen readers and the details sheet.
String formatCollageDateLong(int epochMillis, {String? localeName}) {
  if (epochMillis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
  return '${_safe(DateFormat.yMMMMEEEEd, localeName).format(dt)}, '
      '${_safe(DateFormat.Hm, localeName).format(dt)}';
}

/// A short relative day: "Today", "Yesterday", "3 days ago", "2 weeks ago".
/// Returns null for dates in the future or older than about a month, where
/// the absolute date says more than a relative one.
String? relativeDayLabel(AppLocalizations l, DateTime dt, {DateTime? now}) {
  final n = now ?? DateTime.now();
  // Compare calendar days in UTC so daylight-saving shifts don't skew it.
  final days = DateTime.utc(
    n.year,
    n.month,
    n.day,
  ).difference(DateTime.utc(dt.year, dt.month, dt.day)).inDays;
  if (days < 0) return null;
  if (days == 0) return l.t('libToday');
  if (days == 1) return l.t('libYesterday');
  if (days < 7) return l.p('libDaysAgo', days);
  if (days < 35) return l.p('libWeeksAgo', days ~/ 7);
  return null;
}

/// A quiet "meta line" — a small calendar icon + the formatted date in
/// `caption`/`textLo`. Metadata stays quiet: never amber.
///
/// It never ellipsises the date. When the whole line doesn't fit, it moves the
/// relative day and the time to a second line, then drops the time, and as a
/// last resort wraps. Screen readers always get the full date and time.
class MetaDate extends StatelessWidget {
  const MetaDate({
    super.key,
    required this.epochMillis,
    this.icon = Icons.event_rounded,
    this.color,
    this.showTime = true,
    this.showRelative = false,
  });

  final int epochMillis;
  final IconData icon;

  /// Overrides the default `textLo`. Resolved against the live palette in
  /// [build] when null.
  final Color? color;

  /// Show the time of day when there's room for it.
  final bool showTime;

  /// Lead with "Today" / "3 days ago" for recent dates.
  final bool showRelative;

  @override
  Widget build(BuildContext context) {
    if (epochMillis <= 0) return const SizedBox.shrink();
    final locale = dateLocaleOf(context);
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    final date = formatCollageDate(epochMillis, localeName: locale, withTime: false);
    final time = _safe(DateFormat.Hm, locale).format(dt);
    final rel = showRelative ? relativeDayLabel(context.l10n, dt) : null;
    final c = color ?? context.colors.textLo;
    final style = context.text.caption.copyWith(color: c);
    const iconGap = 17.0; // 13 icon + 4 gap

    return Semantics(
      label: formatCollageDateLong(epochMillis, localeName: locale),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final scaler = MediaQuery.textScalerOf(context);
          final dir = Directionality.of(context);
          bool fits(String s) {
            if (!box.hasBoundedWidth) return true;
            final tp = TextPainter(
              text: TextSpan(text: s, style: style),
              textDirection: dir,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            final ok = tp.width <= box.maxWidth - iconGap;
            tp.dispose();
            return ok;
          }

          String join(List<String?> parts) =>
              parts.whereType<String>().where((s) => s.isNotEmpty).join(' · ');

          final one = join([rel, date, if (showTime) time]);
          final List<String> lines;
          if (fits(one)) {
            lines = [one];
          } else {
            final second = join([rel, if (showTime) time]);
            if (second.isEmpty) {
              lines = [date];
            } else if (fits(second)) {
              lines = [date, second];
            } else {
              lines = [date, rel ?? time];
            }
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 13, color: c),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final line in lines) Text(line, style: style, softWrap: true)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

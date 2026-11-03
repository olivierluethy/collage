import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/library_index_service.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'browse_day_screen.dart';
import 'browse_month_screen.dart';

/// Most photos a collage can hold.
const kMaxCollagePhotos = 9;

/// The year selected in "Browse by date" (null = newest year).
final discoverYearProvider = StateProvider<int?>((_) => null);

/// Route names of the browse screens, so breadcrumbs can unwind them.
const _monthRoute = 'discover/month';
const _dayRoute = 'discover/day';

bool _isBrowseRoute(Route<dynamic> r) =>
    r.settings.name == _monthRoute || r.settings.name == _dayRoute;

// ---- Formatting --------------------------------------------------------------

/// A locale intl has date data for (the app locale, else its language, else en).
String dateLocale(BuildContext context) {
  final l = Localizations.localeOf(context);
  final full = l.toString();
  if (DateFormat.localeExists(full)) return full;
  if (DateFormat.localeExists(l.languageCode)) return l.languageCode;
  return 'en';
}

String formatCount(BuildContext context, int n) =>
    NumberFormat.decimalPattern(dateLocale(context)).format(n);

/// "1 photo" / "12 photos".
String photosLabel(BuildContext context, int n) => n == 1
    ? context.l10n.t('discoverPhotosOne')
    : context.l10n.a('discoverPhotos', {'count': formatCount(context, n)});

/// "1 photo already in a collage" / "3 photos already in collages".
String usedLabel(BuildContext context, int n) => n == 1
    ? context.l10n.t('discoverUsedOne')
    : context.l10n.a('discoverUsedMany', {'count': formatCount(context, n)});

/// "12 March 2024" (or "Undated").
String dayTitle(BuildContext context, int day) => day == kUndatedDay
    ? context.l10n.t('discoverUndated')
    : DateFormat.yMMMMd(dateLocale(context)).format(dayOfKey(day));

/// "Tuesday, 12 March 2024" (or "Undated").
String dayTitleLong(BuildContext context, int day) => day == kUndatedDay
    ? context.l10n.t('discoverUndated')
    : DateFormat.yMMMMEEEEd(dateLocale(context)).format(dayOfKey(day));

String monthTitle(BuildContext context, int year, int month) =>
    DateFormat.yMMMM(dateLocale(context)).format(DateTime(year, month));

/// Stand-alone month name ("March"); [short] gives "Mar".
String monthName(BuildContext context, int month, {bool short = false}) {
  final loc = dateLocale(context);
  final d = DateTime(2000, month);
  return (short ? DateFormat.LLL(loc) : DateFormat.LLLL(loc)).format(d);
}

/// Up to [max] ids spread evenly across [ids] (keeps a day's story arc).
List<String> spreadPick(List<String> ids, {int max = kMaxCollagePhotos}) {
  if (ids.length <= max) return List.of(ids);
  final step = ids.length / max;
  return [for (var i = 0; i < max; i++) ids[(i * step).floor()]];
}

// ---- Navigation --------------------------------------------------------------

Future<void> openMonth(BuildContext context, int year, int month) {
  return Navigator.of(context).push(MaterialPageRoute(
    settings: const RouteSettings(name: _monthRoute),
    builder: (_) => BrowseMonthScreen(year: year, month: month),
  ));
}

/// Opens the day view. Returns the `yyyymm` key of the month the user ended
/// on (days can be stepped across months) when they go back via the month
/// breadcrumb.
Future<int?> openDay(BuildContext context, int day, {bool fromMonth = false}) {
  return Navigator.of(context).push<int>(MaterialPageRoute(
    settings: const RouteSettings(name: _dayRoute),
    builder: (_) => BrowseDayScreen(day: day, fromMonth: fromMonth),
  ));
}

/// Unwind every browse screen back to Discover with [year] selected.
void backToYear(BuildContext context, WidgetRef ref, int year) {
  ref.read(discoverYearProvider.notifier).state = year;
  Navigator.of(context).popUntil((r) => !_isBrowseRoute(r));
}

/// Leave a day for its month: pop when the month view is underneath,
/// otherwise replace the day view with the month view.
void dayToMonth(BuildContext context, int day, {required bool fromMonth}) {
  final d = dayOfKey(day);
  if (fromMonth) {
    Navigator.of(context).pop(monthKeyOf(d.year, d.month));
    return;
  }
  Navigator.of(context).pushReplacement(MaterialPageRoute(
    settings: const RouteSettings(name: _monthRoute),
    builder: (_) => BrowseMonthScreen(year: d.year, month: d.month),
  ));
}

// ---- Widgets -----------------------------------------------------------------

/// One step of the breadcrumb trail.
class Crumb {
  const Crumb(this.label, {this.onTap, this.semantics});
  final String label;
  final VoidCallback? onTap;
  final String? semantics;
}

/// Bottom breadcrumb bar (Year › Month › Day) with previous / next arrows —
/// kept at the bottom so the whole drill-down works one-handed.
class CrumbBar extends StatelessWidget {
  const CrumbBar({
    super.key,
    required this.crumbs,
    this.onPrev,
    this.onNext,
    required this.prevLabel,
    required this.nextLabel,
    this.top,
  });

  final List<Crumb> crumbs;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String prevLabel;
  final String nextLabel;

  /// Optional content above the crumbs (e.g. the Make collage button).
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
        boxShadow: Shadows.e2,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (top != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: top,
              ),
            SizedBox(
              height: Sizes.touchTarget + Space.sm,
              child: Row(
                children: [
                  IconButton(
                    onPressed: onPrev,
                    tooltip: prevLabel,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true, // long trails keep the current step in view
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: box.maxWidth),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < crumbs.length; i++) ...[
                                if (i > 0)
                                  Icon(Icons.chevron_right_rounded,
                                      size: 16, color: c.textLo),
                                _CrumbButton(
                                    crumb: crumbs[i], last: i == crumbs.length - 1),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onNext,
                    tooltip: nextLabel,
                    icon: const Icon(Icons.chevron_right_rounded),
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

class _CrumbButton extends StatelessWidget {
  const _CrumbButton({required this.crumb, required this.last});
  final Crumb crumb;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = context.text.labelMd.copyWith(color: last ? c.amber : c.textMid);
    if (crumb.onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: Text(crumb.label, style: style),
      );
    }
    return Semantics(
      button: true,
      label: crumb.semantics,
      child: TextButton(
        onPressed: crumb.onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          foregroundColor: c.textMid,
        ),
        child: Text(crumb.label, style: style),
      ),
    );
  }
}

/// The quiet collage marker: a small dot in the neutral `info` colour. Always
/// paired with an accessible label — never meaning by colour alone.
class UsedDot extends StatelessWidget {
  const UsedDot({super.key, this.size = 6});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: context.colors.info, shape: BoxShape.circle),
    );
  }
}

/// One-line hint row (limited access, indexing progress), matching the
/// picker's banner: `surfaceHigh`, bottom hairline, one optional action.
class DiscoverBanner extends StatelessWidget {
  const DiscoverBanner({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.progress,
    this.showProgress = false,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double? progress;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                Space.lg, Space.sm, actionLabel == null ? Space.lg : Space.sm, Space.sm),
            child: Row(
              children: [
                Icon(icon, size: 18, color: c.textMid),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(text, style: context.text.bodyMd.copyWith(color: c.textMid)),
                ),
                if (actionLabel != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(Sizes.touchTarget, Sizes.touchTarget),
                    ),
                    child: Text(actionLabel!),
                  ),
              ],
            ),
          ),
          if (showProgress)
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: c.surfaceInput,
            ),
        ],
      ),
    );
  }
}

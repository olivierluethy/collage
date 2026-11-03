import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../state/occasions.dart';
import 'occasion_service.dart';

// Plain, non-guilt-inducing copy about occasions, shared by the in-app card
// and reminders.

/// The occasion's name for display; a birthday reads "Mia's birthday".
String occasionTitle(AppLocalizations l, OccasionDate o) => o.birthday != null
    ? l.a('bdayOf', {'name': o.birthday!.name})
    : l.t(o.occasion.nameKey);

/// One plain sentence about when [o] is, relative to [today]:
/// "Halloween is on Friday", "Mia's birthday is tomorrow". Approximate dates
/// (Eid) never name a weekday.
String occasionHeadline(AppLocalizations l, OccasionDate o, DateTime today) {
  final days = o.daysFrom(today);
  final b = o.birthday;
  if (b != null) {
    final args = {'name': b.name};
    if (days <= 0) return l.a('bdayToday', args);
    if (days == 1) return l.a('bdayTomorrow', args);
    if (days < 7) return l.a('bdayOnDay', {...args, 'day': _weekday(l, o.date)});
    return l.a('bdayInDays', {...args, 'count': '$days'});
  }
  final args = {'occasion': l.t(o.occasion.nameKey)};
  if (o.occasion.approximate && days != 0) {
    return days < 0 ? l.a('occJustWas', args) : l.a('occComingUp', args);
  }
  if (days < 0) return l.a('occYesterday', args);
  if (days == 0) return l.a('occToday', args);
  if (days == 1) return l.a('occTomorrow', args);
  if (days < 7) return l.a('occOnDay', {...args, 'day': _weekday(l, o.date)});
  return l.a('occInDays', {...args, 'count': '$days'});
}

/// The second line: an open invitation, or — when the user already made one
/// this season — a neutral "another one". Never a reproach.
String occasionPrompt(AppLocalizations l, OccasionSuggestion s) {
  if (!s.madeAlready) return l.t('occWantToMake');
  final b = s.date.birthday;
  return b != null
      ? l.a('bdayMakeAnother', {'name': b.name})
      : l.a('occMakeAnother', {'occasion': l.t(s.occasion.nameKey)});
}

String _weekday(AppLocalizations l, DateTime d) {
  try {
    return DateFormat.EEEE(l.locale.toString()).format(d);
  } catch (_) {
    return DateFormat.EEEE().format(d);
  }
}

/// A date- and region-aware calendar of occasions people make collages for
/// (holidays, Mother's Day, birthdays …). Pure Dart: no Flutter, no I/O, so
/// every rule can be checked in isolation.
///
/// ## Accuracy and limits
///
/// * All dates are civil calendar days in the device's local time. Nothing
///   here depends on the time of day.
/// * **Easter** uses the Anonymous Gregorian computus (Western churches) and
///   the Meeus Julian computus + 13 days (Orthodox churches). The Julian →
///   Gregorian offset of 13 days is valid from 1900 to 2099; outside that span
///   Orthodox dates return `null` and are never shown.
/// * **Orthodox Christmas** (7 January) is only listed for regions whose
///   churches keep the Julian calendar (RU, RS, BY, GE, MK, ME, EG, ET). Greece,
///   Cyprus, Romania and Bulgaria celebrate on 25 December (Revised Julian
///   calendar) while keeping Orthodox Easter. Ukraine moved Christmas to
///   25 December in 2023.
/// * **Mother's / Father's Day** follow the commonly observed national date,
///   not every local custom (e.g. Antwerp's Mother's Day on 15 August is not
///   modelled). Regions without a well-known date get no entry at all.
/// * **Lunar New Year, Diwali and Eid** follow lunar or lunisolar calendars.
///   They come from a fixed table for 2025–2030 only and are never shown
///   outside it:
///   - Lunar New Year: the Chinese calendar date (CN, TW, HK, MO, SG, MY, ID).
///     Korea and Vietnam are deliberately excluded because their calendars
///     (computed for UTC+9 / UTC+7) can differ by a day.
///   - Diwali: the main day (Lakshmi Puja) as listed in India's central
///     government holiday calendar. Some regions celebrate a day apart.
///   - Eid al-Fitr / Eid al-Adha: the expected (astronomical / Umm al-Qura)
///     date. The actual day depends on moon sighting and may differ by one
///     day per country, so these occasions are flagged [Occasion.approximate]
///     and the UI never names an exact weekday for them.
/// * **Birthdays on 29 February** are celebrated on 28 February in common
///   years.
/// * Regions are ISO 3166-1 alpha-2 codes. An unknown or empty region only
///   gets occasions that are observed everywhere (New Year).
library;

/// Computes the date of an occasion in [year] for [region], or `null` when it
/// isn't observed there or its date isn't known for that year.
typedef OccasionDateRule = DateTime? Function(int year, String region);

/// One kind of occasion in the calendar.
class Occasion {
  const Occasion({
    required this.id,
    required this.nameKey,
    required this.rule,
    this.regions = const {},
    this.optionalRegions = const {},
    this.global = false,
    this.daysBefore = 14,
    this.daysAfter = 1,
    this.templateTags = const [],
    this.approximate = false,
  });

  /// Stable id, also stored on collages as `CollageProject.occasionId`.
  final String id;

  /// l10n key of the occasion's display name.
  final String nameKey;

  final OccasionDateRule rule;

  /// Regions where the occasion is customary.
  final Set<String> regions;

  /// Regions where it is also celebrated, but less widely. These are shown as
  /// in-app suggestions with lower priority and never trigger reminders.
  final Set<String> optionalRegions;

  /// Observed everywhere (regardless of region).
  final bool global;

  /// Suggestion window: from [daysBefore] days before the date until
  /// [daysAfter] days after it.
  final int daysBefore;
  final int daysAfter;

  /// Template tags this occasion maps to, in priority order (see
  /// `TemplateCatalog`).
  final List<String> templateTags;

  /// The date is an expectation that may move by a day (lunar calendars with
  /// moon sighting). The UI then says "coming up" rather than a weekday.
  final bool approximate;

  bool observedIn(String region) =>
      global || regions.contains(region) || optionalRegions.contains(region);

  bool isOptionalIn(String region) =>
      !global && !regions.contains(region) && optionalRegions.contains(region);

  /// The date in [year] for [region], or null if it isn't observed or known.
  DateTime? dateIn(int year, String region) =>
      observedIn(region) ? rule(year, region) : null;
}

/// A birthday the user keeps in the app (typed in, or imported from contacts).
/// Only a name and a day are stored; [year] is optional.
class Birthday {
  const Birthday({
    required this.id,
    required this.name,
    required this.month,
    required this.day,
    this.year,
    this.fromContacts = false,
  });

  final String id;
  final String name;
  final int month;
  final int day;
  final int? year;

  /// Imported from the address book (deleted when contacts are disconnected).
  final bool fromContacts;

  /// The day it falls on in [y] (29 Feb → 28 Feb in common years).
  DateTime dateIn(int y) {
    if (month == 2 && day == 29 && !_isLeap(y)) return DateTime(y, 2, 28);
    return DateTime(y, month, day);
  }

  Birthday copyWith({String? name, int? month, int? day, int? year, bool clearYear = false}) =>
      Birthday(
        id: id,
        name: name ?? this.name,
        month: month ?? this.month,
        day: day ?? this.day,
        year: clearYear ? null : (year ?? this.year),
        fromContacts: fromContacts,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'm': month,
        'd': day,
        if (year != null) 'y': year,
        if (fromContacts) 'c': true,
      };

  static Birthday? fromJson(Map<String, dynamic> j) {
    final m = j['m'], d = j['d'], name = j['name'], id = j['id'];
    if (m is! int || d is! int || name is! String || id is! String) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return Birthday(
      id: id,
      name: name,
      month: m,
      day: d,
      year: j['y'] as int?,
      fromContacts: j['c'] == true,
    );
  }
}

/// One dated instance of an occasion (or a birthday).
class OccasionDate {
  const OccasionDate({
    required this.occasion,
    required this.date,
    this.optional = false,
    this.birthday,
  });

  final Occasion occasion;

  /// Local calendar day (time is midnight).
  final DateTime date;

  /// Only "also celebrated" in the region (see [Occasion.optionalRegions]).
  final bool optional;

  /// Set for birthday occurrences.
  final Birthday? birthday;

  String get id => occasion.id;

  /// Stable key of this one occurrence, e.g. `halloween@2026-10-31` or
  /// `birthday:<id>@2026-11-06`. Used to remember dismissals.
  String get key {
    final who = birthday == null ? occasion.id : '${occasion.id}:${birthday!.id}';
    return '$who@${date.year}-${_two(date.month)}-${_two(date.day)}';
  }

  /// Whole days from [today] to this date (negative once it has passed).
  int daysFrom(DateTime today) => daysBetween(today, date);
}

/// Whole calendar days from [a] to [b], immune to DST shifts.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

class OccasionService {
  const OccasionService();

  /// Every occasion the calendar knows (birthdays are separate, see
  /// [birthdayOccasion]).
  static List<Occasion> get all => _catalog;

  static Occasion? byId(String id) {
    if (id == birthdayOccasion.id) return birthdayOccasion;
    for (final o in _catalog) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Birthdays share one occasion: shown up to a week before, until the day.
  static const Occasion birthdayOccasion = Occasion(
    id: 'birthday',
    nameKey: 'occBirthday',
    rule: _never,
    global: true,
    daysBefore: 7,
    daysAfter: 0,
    templateTags: ['occ:birthday', 'birthday', 'party'],
  );

  /// Normalises a region code (upper case; `UK` → `GB`). Empty for unknown.
  static String normalizeRegion(String? code) {
    final c = (code ?? '').trim().toUpperCase();
    if (c == 'UK') return 'GB';
    return RegExp(r'^[A-Z]{2}$').hasMatch(c) ? c : '';
  }

  /// Every region some occasion is specific to, sorted. Drives the region
  /// picker in Settings.
  static List<String> get knownRegions {
    final s = <String>{};
    for (final o in _catalog) {
      s
        ..addAll(o.regions)
        ..addAll(o.optionalRegions);
    }
    return s.toList()..sort();
  }

  /// All occurrences between [from] and [to] (inclusive, calendar days) in
  /// [region], plus the [birthdays], sorted by date.
  List<OccasionDate> occurrences({
    required DateTime from,
    required DateTime to,
    required String region,
    List<Birthday> birthdays = const [],
  }) {
    final r = normalizeRegion(region);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final out = <OccasionDate>[];
    for (var y = start.year; y <= end.year; y++) {
      for (final o in _catalog) {
        final d = o.dateIn(y, r);
        if (d == null || d.isBefore(start) || d.isAfter(end)) continue;
        out.add(OccasionDate(occasion: o, date: d, optional: o.isOptionalIn(r)));
      }
      for (final b in birthdays) {
        final d = b.dateIn(y);
        if (d.isBefore(start) || d.isAfter(end)) continue;
        out.add(OccasionDate(occasion: birthdayOccasion, date: d, birthday: b));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Occurrences whose suggestion window contains [now], most relevant first:
  /// upcoming before passed, sooner before later, customary before optional,
  /// birthdays before holidays on the same day.
  List<OccasionDate> active(
    DateTime now,
    String region, {
    List<Birthday> birthdays = const [],
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final list = occurrences(
      from: DateTime(today.year, today.month, today.day - 3),
      to: DateTime(today.year, today.month, today.day + 31),
      region: region,
      birthdays: birthdays,
    ).where((o) {
      final days = o.daysFrom(today);
      return days <= o.occasion.daysBefore && days >= -o.occasion.daysAfter;
    }).toList();
    int rank(OccasionDate o) {
      final days = o.daysFrom(today);
      return (days < 0 ? 100000 : 0) + (o.optional ? 1000 : 0) + days.abs() * 10 +
          (o.birthday != null ? 0 : 1);
    }

    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }
}

// --- the calendar ------------------------------------------------------------

DateTime? _never(int year, String region) => null;

DateTime? Function(int, String) _fixed(int month, int day) =>
    (y, _) => DateTime(y, month, day);

/// The [n]th [weekday] (1 = Monday … 7 = Sunday) of [month].
DateTime nthWeekday(int year, int month, int weekday, int n) {
  final first = DateTime(year, month, 1);
  final offset = (weekday - first.weekday + 7) % 7;
  return DateTime(year, month, 1 + offset + 7 * (n - 1));
}

/// The last [weekday] of [month].
DateTime lastWeekday(int year, int month, int weekday) {
  final last = DateTime(year, month + 1, 0);
  final back = (last.weekday - weekday + 7) % 7;
  return DateTime(year, month, last.day - back);
}

/// Western (Gregorian) Easter Sunday — Anonymous Gregorian algorithm.
DateTime westernEaster(int y) {
  final a = y % 19;
  final b = y ~/ 100;
  final c = y % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(y, month, day);
}

/// Orthodox Easter Sunday as a Gregorian date (Meeus Julian algorithm + 13
/// days). Null outside 1900–2099, where the 13-day offset isn't valid.
DateTime? orthodoxEaster(int y) {
  if (y < 1900 || y > 2099) return null;
  final a = y % 4;
  final b = y % 7;
  final c = y % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = ((d + e + 114) % 31) + 1;
  return DateTime(y, month, day + 13);
}

bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

String _two(int n) => n < 10 ? '0$n' : '$n';

const _orthodoxEasterRegions = {'GR', 'CY', 'RU', 'RO', 'BG', 'RS', 'UA', 'BY', 'GE', 'MD', 'MK', 'ME'};

const _westernEasterRegions = {
  'US', 'CA', 'GB', 'IE', 'AU', 'NZ', 'ZA', 'DE', 'CH', 'AT', 'LI', 'LU', 'FR', 'BE', 'NL',
  'IT', 'ES', 'PT', 'PL', 'CZ', 'SK', 'HU', 'HR', 'SI', 'DK', 'SE', 'NO', 'FI', 'IS',
  'MX', 'BR', 'AR', 'CL', 'CO', 'PE', 'PH',
};

DateTime? _easter(int y, String r) =>
    _orthodoxEasterRegions.contains(r) ? orthodoxEaster(y) : westernEaster(y);

const _julianChristmasRegions = {'RU', 'RS', 'BY', 'GE', 'MK', 'ME', 'EG', 'ET'};

const _christmasRegions = {
  ..._westernEasterRegions,
  'GR', 'CY', 'RO', 'BG', 'UA', 'MD',
  'IN', 'ID', 'JP', 'KR', 'SG', 'MY', 'HK', 'TW', 'LT', 'LV', 'EE',
};

DateTime? _christmas(int y, String r) =>
    _julianChristmasRegions.contains(r) ? DateTime(y, 1, 7) : DateTime(y, 12, 25);

DateTime? _valentines(int y, String r) =>
    r == 'BR' ? DateTime(y, 6, 12) : DateTime(y, 2, 14); // BR: Dia dos Namorados

DateTime? _mothersDay(int y, String r) {
  switch (r) {
    case 'GB' || 'IE':
      // Mothering Sunday: the fourth Sunday of Lent, three weeks before Easter.
      final e = westernEaster(y);
      return DateTime(e.year, e.month, e.day - 21);
    case 'FR':
      // Last Sunday of May, moved to the first Sunday of June if it falls on
      // Pentecost (Easter + 49 days).
      final last = lastWeekday(y, 5, DateTime.sunday);
      final e = westernEaster(y);
      final pentecost = DateTime(e.year, e.month, e.day + 49);
      return daysBetween(last, pentecost) == 0 ? nthWeekday(y, 6, DateTime.sunday, 1) : last;
    case 'SE':
      return lastWeekday(y, 5, DateTime.sunday);
    case 'ES' || 'PT' || 'RO' || 'HU' || 'LT':
      return nthWeekday(y, 5, DateTime.sunday, 1);
    case 'NO':
      return nthWeekday(y, 2, DateTime.sunday, 2);
    case 'MX':
      return DateTime(y, 5, 10);
    case 'PL':
      return DateTime(y, 5, 26);
    case 'AR':
      return nthWeekday(y, 10, DateTime.sunday, 3);
    case 'TH':
      return DateTime(y, 8, 12);
    case 'ID':
      return DateTime(y, 12, 22);
    case 'EG' || 'JO' || 'LB' || 'AE':
      return DateTime(y, 3, 21);
    default:
      return nthWeekday(y, 5, DateTime.sunday, 2);
  }
}

const _mothersDayRegions = {
  // second Sunday of May
  'US', 'CA', 'DE', 'CH', 'AT', 'IT', 'AU', 'NZ', 'JP', 'BE', 'NL', 'DK', 'FI', 'TR', 'BR',
  'CN', 'HK', 'TW', 'SG', 'MY', 'PH', 'IN', 'GR', 'CZ', 'SK',
  // own rules (see _mothersDay)
  'GB', 'IE', 'FR', 'SE', 'ES', 'PT', 'RO', 'HU', 'LT', 'NO', 'MX', 'PL', 'AR', 'TH', 'ID',
  'EG', 'JO', 'LB', 'AE',
};

DateTime? _fathersDay(int y, String r) {
  switch (r) {
    case 'DE':
      // Vatertag = Ascension Day, Easter + 39 days.
      final e = westernEaster(y);
      return DateTime(e.year, e.month, e.day + 39);
    case 'CH':
      return nthWeekday(y, 6, DateTime.sunday, 1);
    case 'AT' || 'BE':
      return nthWeekday(y, 6, DateTime.sunday, 2);
    case 'IT' || 'ES' || 'PT':
      return DateTime(y, 3, 19); // St Joseph's Day
    case 'AU' || 'NZ':
      return nthWeekday(y, 9, DateTime.sunday, 1);
    case 'BR':
      return nthWeekday(y, 8, DateTime.sunday, 2);
    case 'TW':
      return DateTime(y, 8, 8);
    default:
      return nthWeekday(y, 6, DateTime.sunday, 3);
  }
}

const _fathersDayRegions = {
  // third Sunday of June
  'US', 'CA', 'GB', 'IE', 'FR', 'NL', 'JP', 'IN', 'CN', 'HK', 'SG', 'MY', 'PH', 'MX', 'AR',
  'TR', 'ZA',
  // own rules (see _fathersDay)
  'DE', 'CH', 'AT', 'BE', 'IT', 'ES', 'PT', 'AU', 'NZ', 'BR', 'TW',
};

DateTime? _thanksgiving(int y, String r) => switch (r) {
      'US' => nthWeekday(y, 11, DateTime.thursday, 4),
      'CA' => nthWeekday(y, 10, DateTime.monday, 2),
      _ => null,
    };

/// National days (one per region; the most widely celebrated one).
const Map<String, (int, int)> _nationalDays = {
  'CH': (8, 1),
  'DE': (10, 3),
  'FR': (7, 14),
  'US': (7, 4),
  'CA': (7, 1),
  'AT': (10, 26),
  'IT': (6, 2),
  'ES': (10, 12),
  'PT': (6, 10),
  'BE': (7, 21),
  'MX': (9, 16),
  'BR': (9, 7),
  'AR': (7, 9),
  'IN': (8, 15),
  'ID': (8, 17),
  'CN': (10, 1),
  'TR': (10, 29),
  'IE': (3, 17),
  'GR': (3, 25),
  'PL': (11, 11),
  'NL': (4, 27),
};

DateTime? _nationalDay(int y, String r) {
  final md = _nationalDays[r];
  if (md == null) return null;
  final d = DateTime(y, md.$1, md.$2);
  // King's Day moves to Saturday 26 April when 27 April is a Sunday.
  if (r == 'NL' && d.weekday == DateTime.sunday) return DateTime(y, 4, 26);
  return d;
}

// Fixed tables for lunar / lunisolar occasions (see the library doc above).
const Map<int, (int, int)> _lunarNewYear = {
  2025: (1, 29),
  2026: (2, 17),
  2027: (2, 6),
  2028: (1, 26),
  2029: (2, 13),
  2030: (2, 3),
};

const Map<int, (int, int)> _diwali = {
  2025: (10, 20),
  2026: (11, 8),
  2027: (10, 29),
  2028: (10, 17),
  2029: (11, 5),
  2030: (10, 26),
};

const Map<int, (int, int)> _eidAlFitr = {
  2025: (3, 30),
  2026: (3, 20),
  2027: (3, 9),
  2028: (2, 26),
  2029: (2, 14),
  2030: (2, 4),
};

const Map<int, (int, int)> _eidAlAdha = {
  2025: (6, 6),
  2026: (5, 27),
  2027: (5, 16),
  2028: (5, 5),
  2029: (4, 24),
  2030: (4, 13),
};

DateTime? Function(int, String) _table(Map<int, (int, int)> t) => (y, _) {
      final md = t[y];
      return md == null ? null : DateTime(y, md.$1, md.$2);
    };

const _eidRegions = {
  'SA', 'AE', 'QA', 'KW', 'BH', 'OM', 'YE', 'EG', 'JO', 'LB', 'IQ', 'SY', 'PS', 'MA', 'DZ',
  'TN', 'LY', 'SD', 'TR', 'ID', 'MY', 'BN', 'PK', 'BD', 'AF', 'SN',
};

final List<Occasion> _catalog = [
  Occasion(
    id: 'new_year',
    nameKey: 'occNewYear',
    rule: _fixed(1, 1),
    global: true,
    daysBefore: 7,
    templateTags: const ['occ:new_year', 'party'],
  ),
  Occasion(
    id: 'lunar_new_year',
    nameKey: 'occLunarNewYear',
    rule: _table(_lunarNewYear),
    regions: const {'CN', 'TW', 'HK', 'MO', 'SG', 'MY', 'ID'},
    templateTags: const ['occ:lunar_new_year', 'party'],
  ),
  Occasion(
    id: 'valentines',
    nameKey: 'occValentines',
    rule: _valentines,
    regions: const {
      'US', 'CA', 'GB', 'IE', 'AU', 'NZ', 'ZA', 'FR', 'DE', 'CH', 'AT', 'IT', 'ES', 'PT', 'BE',
      'NL', 'LU', 'MX', 'AR', 'CL', 'CO', 'PE', 'BR', 'JP', 'KR', 'CN', 'TW', 'HK', 'PH',
      'SG', 'MY', 'IN', 'ID', 'RU', 'UA', 'PL', 'CZ', 'SK', 'HU', 'RO', 'BG', 'GR', 'TR',
    },
    templateTags: const ['occ:valentines', 'love'],
  ),
  Occasion(
    id: 'easter',
    nameKey: 'occEaster',
    rule: _easter,
    regions: {..._westernEasterRegions, ..._orthodoxEasterRegions},
    templateTags: const ['occ:easter', 'family'],
  ),
  Occasion(
    id: 'mothers_day',
    nameKey: 'occMothersDay',
    rule: _mothersDay,
    regions: _mothersDayRegions,
    templateTags: const ['occ:mothers_day', 'family', 'love'],
  ),
  Occasion(
    id: 'fathers_day',
    nameKey: 'occFathersDay',
    rule: _fathersDay,
    regions: _fathersDayRegions,
    templateTags: const ['occ:fathers_day', 'family'],
  ),
  Occasion(
    id: 'national_day',
    nameKey: 'occNationalDay',
    rule: _nationalDay,
    regions: _nationalDays.keys.toSet(),
    daysBefore: 7,
    templateTags: const ['occ:national_day', 'party', 'summer'],
  ),
  Occasion(
    id: 'halloween',
    nameKey: 'occHalloween',
    rule: _fixed(10, 31),
    regions: const {'US', 'CA', 'IE', 'GB', 'AU', 'NZ'},
    optionalRegions: const {'DE', 'CH', 'AT', 'FR', 'NL', 'BE'},
    templateTags: const ['occ:halloween', 'party'],
  ),
  Occasion(
    id: 'diwali',
    nameKey: 'occDiwali',
    rule: _table(_diwali),
    regions: const {'IN', 'SG', 'MY'},
    templateTags: const ['occ:diwali', 'party', 'family'],
  ),
  Occasion(
    id: 'thanksgiving',
    nameKey: 'occThanksgiving',
    rule: _thanksgiving,
    regions: const {'US', 'CA'},
    templateTags: const ['occ:thanksgiving', 'family'],
  ),
  Occasion(
    id: 'christmas',
    nameKey: 'occChristmas',
    rule: _christmas,
    regions: {..._christmasRegions, ..._julianChristmasRegions},
    daysBefore: 21,
    templateTags: const ['occ:christmas', 'winter'],
  ),
  Occasion(
    id: 'eid_al_fitr',
    nameKey: 'occEidAlFitr',
    rule: _table(_eidAlFitr),
    regions: _eidRegions,
    daysBefore: 10,
    daysAfter: 2,
    approximate: true,
    templateTags: const ['occ:eid', 'family'],
  ),
  Occasion(
    id: 'eid_al_adha',
    nameKey: 'occEidAlAdha',
    rule: _table(_eidAlAdha),
    regions: _eidRegions,
    daysBefore: 10,
    daysAfter: 2,
    approximate: true,
    templateTags: const ['occ:eid', 'family'],
  ),
];

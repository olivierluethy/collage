import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

import '../../data/template_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../models/collage_template.dart';
import '../../services/occasion_service.dart';

/// Category chips above the grid: everything, starred, invitations, holidays,
/// then the classic styles.
enum TemplateCategoryKind { all, favourites, invitations, occasions, style }

@immutable
class TemplateCategory {
  const TemplateCategory._(this.kind, [this.style]);

  final TemplateCategoryKind kind;
  final TemplateStyle? style;

  static const all = TemplateCategory._(TemplateCategoryKind.all);
  static const favourites = TemplateCategory._(TemplateCategoryKind.favourites);
  static const invitations = TemplateCategory._(TemplateCategoryKind.invitations);
  static const occasions = TemplateCategory._(TemplateCategoryKind.occasions);
  factory TemplateCategory.style(TemplateStyle s) => TemplateCategory._(TemplateCategoryKind.style, s);

  static List<TemplateCategory> get chips => [
        all,
        favourites,
        invitations,
        occasions,
        for (final s in TemplateStyle.values) TemplateCategory.style(s),
      ];

  String label(AppLocalizations l) => switch (kind) {
        TemplateCategoryKind.all => l.t('templatesAll'),
        TemplateCategoryKind.favourites => l.t('tplFavourites'),
        TemplateCategoryKind.invitations => l.t('tplCatInvitations'),
        TemplateCategoryKind.occasions => l.t('tplCatOccasions'),
        TemplateCategoryKind.style => l.t(styleKey(style!)),
      };

  bool matches(CollageTemplate t, Set<String> favourites) => switch (kind) {
        TemplateCategoryKind.all => true,
        TemplateCategoryKind.favourites => favourites.contains(t.id),
        TemplateCategoryKind.invitations => t.tags.contains(TemplateCatalog.invitationTag),
        TemplateCategoryKind.occasions => t.tags.contains(TemplateCatalog.occasionTag),
        TemplateCategoryKind.style => t.style == style,
      };

  @override
  bool operator ==(Object other) =>
      other is TemplateCategory && other.kind == kind && other.style == style;

  @override
  int get hashCode => Object.hash(kind, style);
}

/// Canvas shapes the filter offers (the shapes the catalog is built in).
const templateRatios = ['1:1', '4:5', '9:16'];

/// l10n key of a ratio's friendly name.
String ratioKey(String label) => switch (label) {
      '4:5' => 'ratioPortrait',
      '9:16' => 'ratioStory',
      _ => 'ratioSquare',
    };

/// Maps a template style to its l10n key (see `locales/en.dart`).
String styleKey(TemplateStyle s) => switch (s) {
      TemplateStyle.minimal => 'styleMinimal',
      TemplateStyle.birthday => 'styleBirthday',
      TemplateStyle.love => 'styleLove',
      TemplateStyle.travel => 'styleTravel',
      TemplateStyle.party => 'styleParty',
      TemplateStyle.family => 'styleFamily',
      TemplateStyle.summer => 'styleSummer',
      TemplateStyle.winter => 'styleWinter',
      TemplateStyle.social => 'styleSocial',
      TemplateStyle.aesthetic => 'styleAesthetic',
    };

/// The occasion ids a template is made for (from its `occ:<id>` tags).
Iterable<String> occasionIdsOf(CollageTemplate t) sync* {
  for (final tag in t.tags) {
    if (tag.startsWith('occ:')) yield tag.substring(4);
  }
}

/// l10n keys of the occasion names a template is made for. The catalog's
/// `occ:eid` covers both Eids.
List<String> _occasionNameKeys(CollageTemplate t) => [
      for (final id in occasionIdsOf(t))
        if (id == 'eid') ...['occEidAlFitr', 'occEidAlAdha'] else ?OccasionService.byId(id)?.nameKey,
    ];

/// A short, human name for a template in the user's language: its occasion,
/// "Invitation", or its style.
String templateDisplayName(AppLocalizations l, CollageTemplate t) {
  final occ = _occasionNameKeys(t);
  final base = occ.isNotEmpty ? l.t(occ.first) : l.t(styleKey(t.style));
  return t.tags.contains(TemplateCatalog.invitationTag) ? '${l.t('tplCatInvitations')} · $base' : base;
}

/// The active query of the browser.
@immutable
class TemplateQuery {
  const TemplateQuery({
    this.text = '',
    this.category = TemplateCategory.all,
    this.count,
    this.ratio,
  });

  final String text;
  final TemplateCategory category;
  final int? count;
  final String? ratio;

  /// Count + ratio filters set (the badge on the Filters button).
  int get filterCount => (count == null ? 0 : 1) + (ratio == null ? 0 : 1);

  /// Nothing narrows the list: the browse view with its rows is shown.
  bool get isBrowsing =>
      text.trim().isEmpty && category == TemplateCategory.all && filterCount == 0;

  TemplateQuery copyWith({
    String? text,
    TemplateCategory? category,
    int? count,
    bool clearCount = false,
    String? ratio,
    bool clearRatio = false,
  }) =>
      TemplateQuery(
        text: text ?? this.text,
        category: category ?? this.category,
        count: clearCount ? null : (count ?? this.count),
        ratio: clearRatio ? null : (ratio ?? this.ratio),
      );
}

/// Locale-aware full-text matching over templates. For every template it
/// keeps one folded string with its English name and tags plus the
/// translated style, occasion and category names, so "Weihnachten",
/// "christmas" and "noel" all find the Christmas designs.
class TemplateSearchIndex {
  TemplateSearchIndex._(this._text);

  final Map<String, String> _text;

  static final Map<String, TemplateSearchIndex> _cache = {};

  /// The index for [l]'s language, built once per language.
  static TemplateSearchIndex of(AppLocalizations l) {
    final code = l.locale.languageCode;
    return _cache.putIfAbsent(code, () {
      final en = AppLocalizations(const Locale('en'));
      final langs = code == 'en' ? [en] : [en, l];
      final map = <String, String>{};
      for (final t in TemplateCatalog.all()) {
        final parts = <String>[t.name, ...t.tags, '${t.photoCount}'];
        for (final x in langs) {
          parts
            ..add(x.t(styleKey(t.style)))
            ..add(x.t(ratioKey(t.ratioLabel)));
          for (final k in _occasionNameKeys(t)) {
            parts.add(x.t(k));
          }
          if (t.tags.contains(TemplateCatalog.invitationTag)) parts.add(x.t('tplCatInvitations'));
          if (t.tags.contains(TemplateCatalog.occasionTag)) parts.add(x.t('tplCatOccasions'));
        }
        map[t.id] = fold(parts.join(' '));
      }
      return TemplateSearchIndex._(map);
    });
  }

  /// True when every word of [query] occurs in the template's text.
  bool matches(CollageTemplate t, List<String> words) {
    if (words.isEmpty) return true;
    final hay = _text[t.id] ?? fold(t.name);
    return words.every(hay.contains);
  }

  /// Splits and folds a user query into words.
  static List<String> words(String query) =>
      fold(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  /// Lower case without Latin diacritics, so "Noël" matches "noel" and
  /// "Muttertag" matches "MUTTERTAG". Other scripts pass through unchanged.
  static String fold(String s) {
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final r in lower.runes) {
      final ch = String.fromCharCode(r);
      b.write(_fold[ch] ?? ch);
    }
    return b.toString();
  }

  static const Map<String, String> _fold = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'ç': 'c', 'č': 'c', 'ć': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i', 'İ': 'i',
    'ñ': 'n', 'ń': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ş': 's', 'š': 's', 'ś': 's', 'ß': 'ss',
    'ğ': 'g', 'ž': 'z', 'ź': 'z', 'ż': 'z', 'ł': 'l', 'œ': 'oe', 'æ': 'ae',
    '’': "'",
  };
}

/// Templates for [q], in a browsable order (photo count, then style).
List<CollageTemplate> searchTemplates(
  TemplateQuery q, {
  required TemplateSearchIndex index,
  required Set<String> favourites,
}) {
  final words = TemplateSearchIndex.words(q.text);
  final out = [
    for (final t in TemplateCatalog.all())
      if ((q.count == null || t.photoCount == q.count) &&
          (q.ratio == null || t.ratioLabel == q.ratio) &&
          q.category.matches(t, favourites) &&
          index.matches(t, words))
        t,
  ];
  // Stable sort keeps the catalog's own order inside each photo count.
  mergeSort(out, compare: (a, b) => a.photoCount.compareTo(b.photoCount));
  return out;
}

/// Catalog templates the user started collages from, newest first.
List<CollageTemplate> recentTemplates(List<CollageProject> collages, {int max = 10}) {
  final sorted = [...collages]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final seen = <String>{};
  final out = <CollageTemplate>[];
  for (final c in sorted) {
    final id = c.templateId;
    if (id == null || !seen.add(id)) continue;
    final t = TemplateCatalog.byId(id);
    if (t != null) out.add(t);
    if (out.length >= max) break;
  }
  return out;
}

/// "For you": templates for the photo count (and canvas shape) the user uses
/// most, one per style so the row stays varied. Returns that count with the
/// list (null and empty when there is no history yet).
(int?, List<CollageTemplate>) recommendedTemplates(
  List<CollageProject> collages, {
  Set<String> exclude = const {},
  int max = 8,
}) {
  if (collages.isEmpty) return (null, const []);
  final counts = <int, int>{};
  final ratios = <String, int>{};
  for (final c in collages) {
    final n = c.layout.slots.length.clamp(1, 9);
    counts[n] = (counts[n] ?? 0) + 1;
    ratios[c.ratioLabel] = (ratios[c.ratioLabel] ?? 0) + 1;
  }
  int? best;
  for (final e in counts.entries) {
    if (best == null || e.value > counts[best]!) best = e.key;
  }
  String? shape;
  for (final e in ratios.entries) {
    if (!templateRatios.contains(e.key)) continue;
    if (shape == null || e.value > ratios[shape]!) shape = e.key;
  }
  final pool = [
    for (final t in TemplateCatalog.all())
      if (t.photoCount == best && !exclude.contains(t.id)) t,
  ];
  // Preferred shape first, then one design per style.
  mergeSort(pool, compare: (a, b) => (a.ratioLabel == shape ? 0 : 1).compareTo(b.ratioLabel == shape ? 0 : 1));
  final styles = <TemplateStyle>{};
  final out = <CollageTemplate>[];
  for (final t in pool) {
    if (styles.add(t.style)) out.add(t);
    if (out.length >= max) break;
  }
  return (best, out);
}

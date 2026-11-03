import 'package:flutter/widgets.dart';

import '../models/canvas_element.dart';
import '../models/collage_project.dart';
import '../models/collage_template.dart';
import '../models/layout_template.dart';
import 'layout_templates.dart';
import 'sticker_catalog.dart';

/// The bundled, ready-made template library — around a thousand designs built
/// combinatorially from a layout, a colour look, a border treatment and a
/// decoration set, all keyed by photo count and style so the browser can filter
/// down to exactly what the user needs.
///
/// Everything is derived in code (no giant asset list) and produced lazily the
/// first time the Templates tab asks for it, so app startup pays nothing.
class TemplateCatalog {
  TemplateCatalog._();

  /// Photo counts the browser offers (level 1).
  static const List<int> counts = [1, 2, 3, 4, 5, 6, 7, 8, 9];

  /// Styles the browser offers (level 2).
  static List<TemplateStyle> get styles => TemplateStyle.values;

  static List<CollageTemplate>? _all;
  static Map<String, CollageTemplate>? _byId;

  /// The whole library. Built once, then cached.
  static List<CollageTemplate> all() => _all ??= _generate();

  /// One template by id, or null (e.g. an id from an older app version).
  static CollageTemplate? byId(String id) =>
      (_byId ??= {for (final t in all()) t.id: t})[id];

  /// Templates carrying any of [tags], ordered by the first tag they match
  /// (so an occasion's own designs come before related styles).
  static List<CollageTemplate> withAnyTag(List<String> tags) {
    final buckets = [for (final _ in tags) <CollageTemplate>[]];
    for (final t in all()) {
      for (var i = 0; i < tags.length; i++) {
        if (t.tags.contains(tags[i])) {
          buckets[i].add(t);
          break;
        }
      }
    }
    return [for (final b in buckets) ...b];
  }

  /// Tag on every occasion design (holidays, birthdays …).
  static const String occasionTag = 'occasion';

  /// Tag on invitation designs (text placeholders for what, when, where).
  static const String invitationTag = 'invitation';

  /// The `occ:<id>` tag for an occasion id (see `OccasionService`).
  static String occasionTagFor(String occasionId) => 'occ:$occasionId';

  /// Templates for one photo count, optionally narrowed to one style.
  static List<CollageTemplate> forBucket(int count, TemplateStyle? style) => [
        for (final t in all())
          if (t.photoCount == count && (style == null || t.style == style)) t,
      ];

  static int get total => all().length;

  // --- generation ----------------------------------------------------------

  static List<CollageTemplate> _generate() {
    final out = <CollageTemplate>[];
    for (final style in TemplateStyle.values) {
      final spec = _specs[style]!;
      final stickerPaths = _stickerPaths(spec);
      for (final count in counts) {
        final layouts = LayoutTemplates.forCount(count);
        for (var ri = 0; ri < _ratios.length; ri++) {
          final ratio = _ratios[ri];
          for (var v = 0; v < _variants; v++) {
            out.add(_build(
              style: style,
              spec: spec,
              stickerPaths: stickerPaths,
              count: count,
              ratio: ratio,
              layout: layouts[(ri + v) % layouts.length],
              variant: v,
              salt: ri,
            ));
          }
        }
      }
    }
    out
      ..addAll(_occasionTemplates())
      ..addAll(_invitationTemplates());
    return out;
  }

  static const int _variants = 4;

  /// Three canvas shapes per style: square (Instagram feed), portrait (Facebook
  /// feed) and story (Instagram / Snapchat).
  static const List<CanvasRatio> _ratios = [
    CanvasRatio.square,
    CanvasRatio.portrait,
    CanvasRatio.story,
  ];

  static CollageTemplate _build({
    required TemplateStyle style,
    required _StyleSpec spec,
    required List<String> stickerPaths,
    required int count,
    required CanvasRatio ratio,
    required LayoutTemplate layout,
    required int variant,
    required int salt,
  }) {
    final look = spec.looks[(variant + salt) % spec.looks.length];
    final id = '${style.name}-$count-${ratio.label.replaceAll(':', 'x')}-$variant';
    final elements = _decorate(
      id: id,
      spec: spec,
      look: look,
      stickerPaths: stickerPaths,
      variant: variant,
      salt: salt,
    );

    return CollageTemplate(
      id: id,
      name: '${_styleName(style)} ${layout.name}',
      style: style,
      photoCount: count,
      ratioLabel: ratio.label,
      layout: layout,
      border: _border(look, variant),
      background: _background(look, variant),
      elements: elements,
      tags: [style.name, ratio.label, '${count}p'],
    );
  }

  /// The decoration set for one variant: text always, plus stickers / a shape
  /// accent depending on the variant, placed in normalised canvas coordinates.
  static List<CanvasElement> _decorate({
    required String id,
    required _StyleSpec spec,
    required _Look look,
    required List<String> stickerPaths,
    required int variant,
    required int salt,
  }) {
    final list = <CanvasElement>[];
    final top = salt.isEven; // title at the top or the bottom

    // Optional soft shape behind the title (variant 2 and 3).
    if (variant >= 2) {
      list.add(ShapeElement(
        id: '${id}_shape',
        cx: 0.5,
        cy: top ? 0.17 : 0.83,
        shapeKind: _shapeKinds[(variant + salt) % _shapeKinds.length],
        fill: look.deco.withValues(alpha: 0.22),
        scale: 3.4,
        z: 0,
      ));
    }

    // Stickers (variant 1+: two; variant 3: three).
    if (variant >= 1 && stickerPaths.isNotEmpty) {
      final n = variant == 3 ? 3 : 2;
      for (var i = 0; i < n; i++) {
        final p = _stickerSpots[(i + salt) % _stickerSpots.length];
        list.add(StickerElement(
          id: '${id}_st$i',
          cx: p.$1,
          cy: p.$2,
          assetPath: stickerPaths[(i + salt + variant) % stickerPaths.length],
          scale: 0.7 + 0.12 * ((i + salt) % 3),
          rotation: ((i + salt) % 5 - 2) * 0.08,
          z: 1,
        ));
      }
    }

    // Title + subtitle text on top.
    final title = spec.titles[salt % spec.titles.length];
    final font = spec.fonts[(variant + salt) % spec.fonts.length];
    list.add(TextElement(
      id: '${id}_title',
      cx: 0.5,
      cy: top ? 0.12 : 0.88,
      text: title,
      color: look.text,
      fontKey: font,
      bold: true,
      scale: 1.5,
      z: 2,
    ));
    final sub = spec.subtitles[(variant + salt) % spec.subtitles.length];
    if (sub.isNotEmpty) {
      list.add(TextElement(
        id: '${id}_sub',
        cx: 0.5,
        cy: top ? 0.205 : 0.795,
        text: sub,
        color: look.text.withValues(alpha: 0.85),
        fontKey: _metaFonts[(variant + salt) % _metaFonts.length],
        scale: 0.8,
        z: 2,
      ));
    }
    return list;
  }

  static const List<String> _shapeKinds = ['circle', 'rounded', 'bubble', 'star'];

  static const List<String> _metaFonts = ['inter', 'oswald', 'bebas', 'caveat'];

  /// Normalised spots for stickers / accents, kept clear of the centre.
  static const List<(double, double)> _stickerSpots = [
    (0.12, 0.16),
    (0.88, 0.16),
    (0.12, 0.84),
    (0.88, 0.84),
    (0.5, 0.5),
    (0.2, 0.5),
    (0.8, 0.5),
  ];

  static BackgroundSettings _background(_Look look, int variant) {
    final bg = BackgroundSettings();
    if (look.pattern != null && variant.isOdd) {
      bg.kind = BackgroundKind.pattern;
      bg.patternKey = look.pattern!;
      bg.patternColor = look.bg2;
      bg.patternBg = look.bg;
      return bg;
    }
    if (variant == 2) {
      bg.kind = BackgroundKind.solid;
      bg.color = look.bg;
      return bg;
    }
    bg.kind = BackgroundKind.gradient;
    bg.gradientStart = look.bg;
    bg.gradientEnd = look.bg2;
    bg.gradientAngle = 0.785 + variant * 0.35;
    return bg;
  }

  static BorderSettings _border(_Look look, int variant) {
    // Border colour is the "mat" between photos: light on dark looks, ink /
    // accent on light looks.
    final mat = look.light ? look.accent : const Color(0xFFFFFFFF);
    switch (variant) {
      case 0:
        return BorderSettings(gap: 6, margin: 18, radius: 10, thickness: 0, color: mat);
      case 1:
        return BorderSettings(gap: 16, margin: 26, radius: 4, thickness: 8, color: mat);
      case 2:
        return BorderSettings(gap: 4, margin: 6, radius: 16, thickness: 0, color: mat);
      default:
        return BorderSettings(gap: 10, margin: 20, radius: 22, thickness: 3, color: mat);
    }
  }

  static String _styleName(TemplateStyle s) => switch (s) {
        TemplateStyle.minimal => 'Minimal',
        TemplateStyle.birthday => 'Birthday',
        TemplateStyle.love => 'Love',
        TemplateStyle.travel => 'Travel',
        TemplateStyle.party => 'Party',
        TemplateStyle.family => 'Family',
        TemplateStyle.summer => 'Summer',
        TemplateStyle.winter => 'Winter',
        TemplateStyle.social => 'Social',
        TemplateStyle.aesthetic => 'Aesthetic',
      };

  /// Every bundled sticker asset the style draws from, in a stable order.
  static final Map<TemplateStyle, List<String>> _stickerCache = {};

  static List<String> _stickerPaths(_StyleSpec spec) {
    return _stickerCache.putIfAbsent(spec.style, () {
      final out = <String>[];
      for (final cat in StickerCatalog.categories) {
        if (spec.stickers.contains(cat.dir)) out.addAll(cat.assetPaths);
      }
      return out;
    });
  }

  // --- occasion and invitation designs --------------------------------------

  /// A handful of designs per occasion (5 each: 1, 2, 3, 4 and 6 photos),
  /// tagged `occasion` + `occ:<id>` so the occasion flow can list them. They
  /// sit in the closest existing style bucket, so style filters still work.
  static List<CollageTemplate> _occasionTemplates() {
    final out = <CollageTemplate>[];
    for (final o in _occasionSpecs) {
      final stickerPaths = _stickerPathsFor(o.stickers);
      for (var i = 0; i < _occasionCounts.length; i++) {
        final count = _occasionCounts[i];
        final ratio = _ratios[i % _ratios.length];
        final layouts = LayoutTemplates.forCount(count);
        final variant = i % _variants;
        final look = o.looks[i % o.looks.length];
        final id = 'occ-${o.id}-$count-${ratio.label.replaceAll(':', 'x')}';
        final top = i.isEven;
        final elements = <CanvasElement>[
          if (variant >= 2)
            ShapeElement(
              id: '${id}_shape',
              cx: 0.5,
              cy: top ? 0.15 : 0.85,
              shapeKind: _shapeKinds[i % _shapeKinds.length],
              fill: look.deco.withValues(alpha: 0.25),
              scale: 3.4,
              z: 0,
            ),
          for (var s = 0; s < (stickerPaths.isEmpty ? 0 : 2); s++)
            StickerElement(
              id: '${id}_st$s',
              cx: _stickerSpots[(s + i) % 4].$1,
              cy: _stickerSpots[(s + i) % 4].$2,
              assetPath: stickerPaths[(s + i) % stickerPaths.length],
              scale: 0.75,
              rotation: (s.isEven ? -1 : 1) * 0.1,
              z: 1,
            ),
          for (var e = 0; e < o.emoji.length && e < 2; e++)
            EmojiElement(
              id: '${id}_em$e',
              cx: _stickerSpots[(e + i + 2) % 4].$1,
              cy: _stickerSpots[(e + i + 2) % 4].$2,
              emoji: o.emoji[(e + i) % o.emoji.length],
              scale: 0.9,
              z: 1,
            ),
          TextElement(
            id: '${id}_title',
            cx: 0.5,
            cy: top ? 0.11 : 0.89,
            text: o.title,
            color: look.text,
            fontKey: o.fonts[i % o.fonts.length],
            bold: true,
            scale: 1.4,
            z: 2,
          ),
        ];
        out.add(CollageTemplate(
          id: id,
          name: '${o.name} ${layouts[i % layouts.length].name}',
          style: o.style,
          photoCount: count,
          ratioLabel: ratio.label,
          layout: layouts[i % layouts.length],
          border: _border(look, variant),
          background: _background(look, variant),
          elements: elements,
          tags: [occasionTag, occasionTagFor(o.id), o.style.name, ratio.label, '${count}p'],
        ));
      }
    }
    return out;
  }

  static const List<int> _occasionCounts = [1, 2, 3, 4, 6];

  /// Invitation cards: photos on top, then "You're invited", a date line and a
  /// place line as editable text placeholders. Two per theme (1 photo in 4:5,
  /// 2 photos in 9:16).
  static List<CollageTemplate> _invitationTemplates() {
    final out = <CollageTemplate>[];
    for (final inv in _invitationSpecs) {
      final stickerPaths = _stickerPathsFor(inv.stickers);
      for (var i = 0; i < 2; i++) {
        final count = i + 1;
        final ratio = i == 0 ? CanvasRatio.portrait : CanvasRatio.story;
        final look = inv.looks[i % inv.looks.length];
        final id = 'inv-${inv.id}-$count';
        final layout = LayoutTemplate(
          id: 'invitation-$count',
          name: 'Invitation',
          family: LayoutFamily.featured,
          slots: [
            for (var s = 0; s < count; s++)
              LayoutSlot(id: 's$s', rect: Rect.fromLTRB(s / count, 0, (s + 1) / count, 0.58)),
          ],
        );
        out.add(CollageTemplate(
          id: id,
          name: '${inv.name} invitation',
          style: inv.style,
          photoCount: count,
          ratioLabel: ratio.label,
          layout: layout,
          border: BorderSettings(
            gap: 8,
            margin: 22,
            radius: 12,
            thickness: 0,
            color: look.light ? look.accent : const Color(0xFFFFFFFF),
          ),
          background: _background(look, 0),
          elements: [
            if (stickerPaths.isNotEmpty)
              StickerElement(
                id: '${id}_st',
                cx: 0.86,
                cy: 0.62,
                assetPath: stickerPaths[i % stickerPaths.length],
                scale: 0.7,
                rotation: 0.12,
                z: 1,
              ),
            if (inv.emoji != null)
              EmojiElement(id: '${id}_em', cx: 0.14, cy: 0.62, emoji: inv.emoji!, scale: 0.8, z: 1),
            TextElement(
              id: '${id}_title',
              cx: 0.5,
              cy: 0.70,
              text: TemplateText.invited,
              color: look.text,
              fontKey: inv.font,
              bold: true,
              scale: 1.3,
              z: 2,
            ),
            TextElement(
              id: '${id}_date',
              cx: 0.5,
              cy: 0.80,
              text: TemplateText.dateTime,
              color: look.text.withValues(alpha: 0.9),
              fontKey: 'inter',
              bold: true,
              scale: 0.8,
              z: 2,
            ),
            TextElement(
              id: '${id}_place',
              cx: 0.5,
              cy: 0.87,
              text: TemplateText.place,
              color: look.text.withValues(alpha: 0.85),
              fontKey: 'inter',
              scale: 0.75,
              z: 2,
            ),
          ],
          tags: [
            invitationTag,
            if (inv.occasion != null) ...[occasionTag, occasionTagFor(inv.occasion!)],
            inv.style.name,
            ratio.label,
            '${count}p',
          ],
        ));
      }
    }
    return out;
  }

  static List<String> _stickerPathsFor(List<String> dirs) => [
        for (final cat in StickerCatalog.categories)
          if (dirs.contains(cat.dir)) ...cat.assetPaths,
      ];

  static const List<_OccasionSpec> _occasionSpecs = [
    _OccasionSpec('new_year', 'New Year', TemplateStyle.party, TemplateText.newYear,
        stickers: ['newyear'], fonts: ['bebas', 'playfair', 'lobster'], looks: [_gold, _midnight, _dusk]),
    _OccasionSpec('lunar_new_year', 'Lunar New Year', TemplateStyle.party, TemplateText.lunarNewYear,
        emoji: ['🧧', '🏮', '🐉'], fonts: ['playfair', 'bebas'], looks: [_lantern, _sunset]),
    _OccasionSpec('valentines', "Valentine's", TemplateStyle.love, TemplateText.valentines,
        stickers: ['love'], fonts: ['pacifico', 'fraunces', 'lobster'], looks: [_rose, _candy, _paper]),
    _OccasionSpec('easter', 'Easter', TemplateStyle.family, TemplateText.easter,
        emoji: ['🐣', '🌷', '🥚'], stickers: ['paint'], fonts: ['caveat', 'pacifico'], looks: [_pastel, _cream, _dots]),
    _OccasionSpec('mothers_day', "Mother's Day", TemplateStyle.family, TemplateText.mothersDay,
        emoji: ['💐', '🌸'], stickers: ['love'], fonts: ['fraunces', 'pacifico', 'playfair'], looks: [_pastel, _cream, _rose]),
    _OccasionSpec('fathers_day', "Father's Day", TemplateStyle.family, TemplateText.fathersDay,
        emoji: ['⭐', '🏆'], stickers: ['notes'], fonts: ['oswald', 'bebas', 'playfair'], looks: [_cocoa, _ink, _lagoon]),
    _OccasionSpec('national_day', 'National Day', TemplateStyle.party, TemplateText.nationalDay,
        emoji: ['🎆', '🎉'], stickers: ['newyear'], fonts: ['bebas', 'oswald'], looks: [_sunset, _midnight, _paper]),
    _OccasionSpec('halloween', 'Halloween', TemplateStyle.party, TemplateText.halloween,
        emoji: ['🎃', '👻', '🦇'], fonts: ['lobster', 'bebas', 'caveat'], looks: [_pumpkin, _ink]),
    _OccasionSpec('diwali', 'Diwali', TemplateStyle.party, TemplateText.diwali,
        emoji: ['🪔', '✨'], fonts: ['playfair', 'fraunces'], looks: [_diya, _sunset]),
    _OccasionSpec('thanksgiving', 'Thanksgiving', TemplateStyle.family, TemplateText.thanksgiving,
        emoji: ['🍂', '🥧', '🦃'], fonts: ['fraunces', 'caveat'], looks: [_harvest, _cream]),
    _OccasionSpec('christmas', 'Christmas', TemplateStyle.winter, TemplateText.christmas,
        stickers: ['christmas', 'winter'], fonts: ['fraunces', 'lobster', 'playfair'], looks: [_festive, _midnight, _cream]),
    _OccasionSpec('eid', 'Eid', TemplateStyle.family, TemplateText.eid,
        emoji: ['🌙', '✨', '🕌'], fonts: ['playfair', 'fraunces'], looks: [_oasis, _midnight]),
    _OccasionSpec('birthday', 'Birthday', TemplateStyle.birthday, TemplateText.birthday,
        stickers: ['birthday'], fonts: ['pacifico', 'lobster', 'bebas'], looks: [_sunset, _candy, _cream]),
  ];

  static const List<_InvitationSpec> _invitationSpecs = [
    _InvitationSpec('birthday', 'Birthday', TemplateStyle.birthday, 'birthday',
        stickers: ['birthday'], font: 'pacifico', looks: [_candy, _sunset]),
    _InvitationSpec('party', 'Party', TemplateStyle.party, null,
        stickers: ['newyear'], font: 'bebas', looks: [_dusk, _midnight]),
    _InvitationSpec('halloween', 'Halloween', TemplateStyle.party, 'halloween',
        emoji: '🎃', font: 'lobster', looks: [_pumpkin, _ink]),
    _InvitationSpec('christmas', 'Christmas', TemplateStyle.winter, 'christmas',
        stickers: ['christmas'], font: 'fraunces', looks: [_festive, _cream]),
    _InvitationSpec('new_year', 'New Year', TemplateStyle.party, 'new_year',
        stickers: ['newyear'], font: 'playfair', looks: [_gold, _midnight]),
    _InvitationSpec('simple', 'Simple', TemplateStyle.minimal, null,
        stickers: ['tape'], font: 'fraunces', looks: [_paper, _cream]),
  ];

  // --- style data ----------------------------------------------------------

  static final Map<TemplateStyle, _StyleSpec> _specs = {
    TemplateStyle.minimal: _StyleSpec(
      style: TemplateStyle.minimal,
      stickers: const ['tape'],
      titles: const ['less is more', 'keep it simple', 'just be'],
      subtitles: const ['', '', ''],
      fonts: const ['inter', 'playfair', 'oswald'],
      looks: const [_paper, _ink, _grid],
    ),
    TemplateStyle.birthday: _StyleSpec(
      style: TemplateStyle.birthday,
      stickers: const ['birthday', 'paint'],
      titles: const ['Happy Birthday', 'Make a wish', 'Party time'],
      subtitles: const ['best day ever', 'cheers', 'hooray'],
      fonts: const ['pacifico', 'lobster', 'bebas'],
      looks: const [_sunset, _candy, _cream],
    ),
    TemplateStyle.love: _StyleSpec(
      style: TemplateStyle.love,
      stickers: const ['love', 'tape'],
      titles: const ['Love you', 'Together', 'My favourite'],
      subtitles: const ['always', 'forever', 'xoxo'],
      fonts: const ['fraunces', 'pacifico', 'playfair'],
      looks: const [_rose, _candy, _paper],
    ),
    TemplateStyle.travel: _StyleSpec(
      style: TemplateStyle.travel,
      stickers: const ['notes', 'tape'],
      titles: const ['Wander', 'Adventures', 'On the road'],
      subtitles: const ['travel diary', 'the journey', 'explore'],
      fonts: const ['oswald', 'bebas', 'caveat'],
      looks: const [_lagoon, _cocoa, _midnight],
    ),
    TemplateStyle.party: _StyleSpec(
      style: TemplateStyle.party,
      stickers: const ['birthday', 'newyear', 'paint'],
      titles: const ["Let's party", 'Good vibes', 'Cheers'],
      subtitles: const ['best night ever', 'party time', 'woo!'],
      fonts: const ['bebas', 'lobster', 'oswald'],
      looks: const [_dusk, _sunset, _candy],
    ),
    TemplateStyle.family: _StyleSpec(
      style: TemplateStyle.family,
      stickers: const ['notes', 'love', 'tape'],
      titles: const ['Family', 'Together', 'Our little world'],
      subtitles: const ['home sweet home', 'always', 'with love'],
      fonts: const ['fraunces', 'playfair', 'inter'],
      looks: const [_cream, _paper, _cocoa],
    ),
    TemplateStyle.summer: _StyleSpec(
      style: TemplateStyle.summer,
      stickers: const ['paint', 'tape'],
      titles: const ['Summer', 'Sunny days', 'Good vibes'],
      subtitles: const ['beach days', 'holiday', 'sunshine'],
      fonts: const ['caveat', 'pacifico', 'bebas'],
      looks: const [_lagoon, _sunset, _dots],
    ),
    TemplateStyle.winter: _StyleSpec(
      style: TemplateStyle.winter,
      stickers: const ['winter', 'christmas', 'newyear'],
      titles: const ['Winter', 'Let it snow', 'Cosy'],
      subtitles: const ['happy holidays', "season's greetings", 'brrr'],
      fonts: const ['fraunces', 'caveat', 'playfair'],
      looks: const [_midnight, _dots, _grid],
    ),
    TemplateStyle.social: _StyleSpec(
      style: TemplateStyle.social,
      stickers: const ['notes', 'tape', 'love'],
      titles: const ['#vibes', 'Good times', 'Life lately'],
      subtitles: const ['@me', 'today', 'new post'],
      fonts: const ['bebas', 'inter', 'oswald'],
      looks: const [_ink, _dusk, _midnight],
    ),
    TemplateStyle.aesthetic: _StyleSpec(
      style: TemplateStyle.aesthetic,
      stickers: const ['paint', 'tape', 'notes'],
      titles: const ['dream', 'mood', 'moments'],
      subtitles: const ['aesthetic', 'soft', 'slow days'],
      fonts: const ['fraunces', 'playfair', 'caveat'],
      looks: const [_paper, _grid, _cream],
    ),
  };
}

/// The decorative vocabulary of one occasion's designs.
class _OccasionSpec {
  const _OccasionSpec(
    this.id,
    this.name,
    this.style,
    this.title, {
    this.stickers = const [],
    this.emoji = const [],
    required this.fonts,
    required this.looks,
  });

  final String id; // occasion id (see OccasionService), 'eid' covers both Eids
  final String name; // English template name prefix (search, fallback)
  final TemplateStyle style;
  final String title; // a TemplateText placeholder, localised at display time
  final List<String> stickers;
  final List<String> emoji;
  final List<String> fonts;
  final List<_Look> looks;
}

class _InvitationSpec {
  const _InvitationSpec(
    this.id,
    this.name,
    this.style,
    this.occasion, {
    this.stickers = const [],
    this.emoji,
    required this.font,
    required this.looks,
  });

  final String id;
  final String name;
  final TemplateStyle style;
  final String? occasion;
  final List<String> stickers;
  final String? emoji;
  final String font;
  final List<_Look> looks;
}

/// Template text that is shown in the user's language. The catalog stores the
/// English text; [localize] swaps in the translation (l10n key in [keys]) for
/// previews and when a collage is started, so the user edits their own
/// language. Any other text is left as it is.
class TemplateText {
  TemplateText._();

  static const invited = "You're invited";
  static const dateTime = 'Date · time';
  static const place = 'Place';
  static const newYear = 'Happy New Year';
  static const lunarNewYear = 'Happy Lunar New Year';
  static const valentines = "Happy Valentine's Day";
  static const easter = 'Happy Easter';
  static const mothersDay = "Happy Mother's Day";
  static const fathersDay = "Happy Father's Day";
  static const nationalDay = "Let's celebrate";
  static const halloween = 'Happy Halloween';
  static const diwali = 'Happy Diwali';
  static const thanksgiving = 'Happy Thanksgiving';
  static const christmas = 'Merry Christmas';
  static const eid = 'Eid Mubarak';
  static const birthday = 'Happy Birthday';

  /// English text → l10n key (see lib/l10n/strings/templates.dart).
  static const Map<String, String> keys = {
    invited: 'tplTextInvited',
    dateTime: 'tplTextDate',
    place: 'tplTextPlace',
    newYear: 'tplTextNewYear',
    lunarNewYear: 'tplTextLunarNewYear',
    valentines: 'tplTextValentines',
    easter: 'tplTextEaster',
    mothersDay: 'tplTextMothersDay',
    fathersDay: 'tplTextFathersDay',
    nationalDay: 'tplTextNationalDay',
    halloween: 'tplTextHalloween',
    diwali: 'tplTextDiwali',
    thanksgiving: 'tplTextThanksgiving',
    christmas: 'tplTextChristmas',
    eid: 'tplTextEid',
    birthday: 'tplTextBirthday',
  };

  /// [text] in the user's language when it is a known placeholder.
  static String localize(String text, String Function(String key) translate) {
    final key = keys[text];
    return key == null ? text : translate(key);
  }

  /// Localises every known placeholder in [elements] in place (they must be
  /// the project's own clones, never the shared catalog entries).
  static void localizeAll(List<CanvasElement> elements, String Function(String key) translate) {
    for (final e in elements) {
      if (e is TextElement) e.text = localize(e.text, translate);
    }
  }
}

/// A style's decorative vocabulary.
class _StyleSpec {
  const _StyleSpec({
    required this.style,
    required this.stickers,
    required this.titles,
    required this.subtitles,
    required this.fonts,
    required this.looks,
  });

  final TemplateStyle style;
  final List<String> stickers; // bundled sticker category dirs
  final List<String> titles;
  final List<String> subtitles;
  final List<String> fonts;
  final List<_Look> looks;
}

/// One colour treatment: background pair, accent, text and decoration colours.
class _Look {
  const _Look(
    this.bg,
    this.bg2,
    this.accent,
    this.text,
    this.deco, {
    this.light = false,
    this.pattern,
  });

  final Color bg;
  final Color bg2;
  final Color accent;
  final Color text;
  final Color deco;
  final bool light;
  final String? pattern;
}

// --- shared looks ----------------------------------------------------------

const _paper = _Look(Color(0xFFF7F4EF), Color(0xFFEDE7DD), Color(0xFF1A1714),
    Color(0xFF1A1714), Color(0xFFB8AFA2), light: true);
const _ink = _Look(Color(0xFF131110), Color(0xFF2A2521), Color(0xFFFFB454),
    Color(0xFFF5EFE7), Color(0xFF4E463D));
const _sunset = _Look(Color(0xFFFFB454), Color(0xFFF5665E), Color(0xFFFFFFFF),
    Color(0xFFFFFFFF), Color(0xFFFFE0B0));
const _dusk = _Look(Color(0xFF6C63FF), Color(0xFFB388FF), Color(0xFFFFD75E),
    Color(0xFFFFFFFF), Color(0xFFE6DFFF));
const _lagoon = _Look(Color(0xFF3DD6C4), Color(0xFF6FB2FF), Color(0xFFFFFFFF),
    Color(0xFFFFFFFF), Color(0xFFD6F6F1));
const _candy = _Look(Color(0xFFFF8FB1), Color(0xFFFFD75E), Color(0xFFFFFFFF),
    Color(0xFF2A1B08), Color(0xFFFFF0D6), light: true);
const _rose = _Look(Color(0xFFE23E57), Color(0xFFFF8FB1), Color(0xFFFFFFFF),
    Color(0xFFFFFFFF), Color(0xFFFFDCE4));
const _cocoa = _Look(Color(0xFF8D6E63), Color(0xFFF5EFE7), Color(0xFFFFB454),
    Color(0xFFF5EFE7), Color(0xFF4E463D));
const _midnight = _Look(Color(0xFF131110), Color(0xFF3D362F), Color(0xFF6FB2FF),
    Color(0xFFF5EFE7), Color(0xFF3D362F));
const _cream = _Look(Color(0xFFF5EFE7), Color(0xFFFFE7C2), Color(0xFFE08A1E),
    Color(0xFF221C15), Color(0xFFD8CFC0), light: true);
const _grid = _Look(Color(0xFF1A1714), Color(0xFF3D362F), Color(0xFFFFB454),
    Color(0xFFF5EFE7), Color(0xFF3D362F), pattern: 'grid');
const _dots = _Look(Color(0xFFF7F3ED), Color(0xFFD8CFC0), Color(0xFFE08A1E),
    Color(0xFF221C15), Color(0xFFD8CFC0), light: true, pattern: 'dots');

// --- occasion looks (design content, not app chrome) --------------------------

const _pumpkin = _Look(Color(0xFF1E1230), Color(0xFFFF7A1A), Color(0xFFFF9F43),
    Color(0xFFFFE8CC), Color(0xFF6B3FA0));
const _festive = _Look(Color(0xFF0F3D2E), Color(0xFF1F6B4A), Color(0xFFE23E57),
    Color(0xFFFFF4E0), Color(0xFFE23E57), pattern: 'dots');
const _gold = _Look(Color(0xFF0E1630), Color(0xFF3A2C10), Color(0xFFF2C14E),
    Color(0xFFF7E3A1), Color(0xFFF2C14E));
const _lantern = _Look(Color(0xFFB3121F), Color(0xFFE23E2B), Color(0xFFFFD166),
    Color(0xFFFFE8A3), Color(0xFFFFD166));
const _diya = _Look(Color(0xFF3B0F4F), Color(0xFFE07A1F), Color(0xFFFFC94D),
    Color(0xFFFFF1C9), Color(0xFFFFC94D));
const _oasis = _Look(Color(0xFF0B4F4A), Color(0xFF13315C), Color(0xFFE9C46A),
    Color(0xFFF7EBCB), Color(0xFFE9C46A));
const _harvest = _Look(Color(0xFF8C3B12), Color(0xFFD9822B), Color(0xFFFFE0B0),
    Color(0xFFFFF4E2), Color(0xFFF2B880));
const _pastel = _Look(Color(0xFFFCE4EC), Color(0xFFE3F2FD), Color(0xFF7E57C2),
    Color(0xFF4A3B66), Color(0xFFD1C4E9), light: true);

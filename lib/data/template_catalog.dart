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

  /// The whole library. Built once, then cached.
  static List<CollageTemplate> all() => _all ??= _generate();

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

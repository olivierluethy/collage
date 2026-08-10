/// A named starter look applied on top of a photo. Adjustments (below) fine-tune
/// the result, so a preset is just a sensible starting matrix.
enum FilterPreset {
  none('Original'),
  grayscale('Mono'),
  sepia('Sepia'),
  vintage('Vintage'),
  cool('Cool'),
  highContrast('Punch'),
  fade('Fade');

  const FilterPreset(this.label);
  final String label;
}

/// Per-photo colour treatment: a preset plus four manual adjustments, each in a
/// symmetric −1..1 range where 0 is neutral. Rendered as a single
/// `ColorFilter.matrix`, so what shows on screen is exactly what the export
/// bakes into the saved image.
class PhotoFilter {
  PhotoFilter({
    this.preset = FilterPreset.none,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
  });

  FilterPreset preset;
  double brightness; // −1..1
  double contrast; // −1..1
  double saturation; // −1..1
  double warmth; // −1..1 (cool → warm)

  /// True when this filter would leave the image untouched, so callers can skip
  /// wrapping the photo in a [ColorFiltered] at all.
  bool get isIdentity =>
      preset == FilterPreset.none &&
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      warmth == 0;

  bool get hasAdjustments =>
      brightness != 0 || contrast != 0 || saturation != 0 || warmth != 0;

  PhotoFilter clone() => PhotoFilter(
        preset: preset,
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
        warmth: warmth,
      );

  void resetAdjustments() {
    brightness = 0;
    contrast = 0;
    saturation = 0;
    warmth = 0;
  }

  /// The composed 4×5 colour matrix (20 values) for `ColorFilter.matrix`.
  /// The preset is applied to each pixel first, then the manual adjustments.
  List<double> matrix() {
    var m = _presetMatrix(preset);
    // Manual adjustments compose on top of the preset look.
    if (brightness != 0) m = _mul(_brightness(brightness), m);
    if (contrast != 0) m = _mul(_contrast(contrast), m);
    if (warmth != 0) m = _mul(_warmth(warmth), m);
    if (saturation != 0) m = _mul(_saturation(saturation), m);
    return m;
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'warmth': warmth,
      };

  factory PhotoFilter.fromJson(Map<String, dynamic> j) => PhotoFilter(
        preset: FilterPreset.values.asNameMap()[j['preset'] as String?] ??
            FilterPreset.none,
        brightness: (j['brightness'] as num?)?.toDouble() ?? 0,
        contrast: (j['contrast'] as num?)?.toDouble() ?? 0,
        saturation: (j['saturation'] as num?)?.toDouble() ?? 0,
        warmth: (j['warmth'] as num?)?.toDouble() ?? 0,
      );

  // --- matrix primitives ---------------------------------------------------
  // All matrices are 4×5, row-major, operating on 0..255 channel values:
  //   R' = m0*R + m1*G + m2*B + m3*A + m4  (and so on per row).

  static const List<double> _identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  /// Additive brightness: b in −1..1 → offset of ±90 on 0..255.
  static List<double> _brightness(double b) {
    final o = b * 90.0;
    return [
      1, 0, 0, 0, o, //
      0, 1, 0, 0, o, //
      0, 0, 1, 0, o, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Contrast around mid-grey: c in −1..1 → factor 0..2.
  static List<double> _contrast(double c) {
    final f = 1 + c;
    final t = 128 * (1 - f);
    return [
      f, 0, 0, 0, t, //
      0, f, 0, 0, t, //
      0, 0, f, 0, t, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Saturation using Rec.709 luma weights: s in −1..1 → sat 0..2.
  static List<double> _saturation(double s) {
    final sat = 1 + s;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final ir = (1 - sat);
    return [
      lr * ir + sat, lg * ir, lb * ir, 0, 0, //
      lr * ir, lg * ir + sat, lb * ir, 0, 0, //
      lr * ir, lg * ir, lb * ir + sat, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Warmth: push red up and blue down (warm) or the reverse (cool).
  static List<double> _warmth(double w) {
    final r = w * 42.0;
    final b = -w * 42.0;
    return [
      1, 0, 0, 0, r, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, b, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Lift the blacks for a faded, matte look: scale the range down and add a
  /// flat offset so shadows never reach pure black.
  static List<double> _lift(double amount) {
    final k = 1 - amount / 255;
    return [
      k, 0, 0, 0, amount, //
      0, k, 0, 0, amount, //
      0, 0, k, 0, amount, //
      0, 0, 0, 1, 0, //
    ];
  }

  static const List<double> _sepia = [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  static List<double> _presetMatrix(FilterPreset p) {
    switch (p) {
      case FilterPreset.none:
        return List<double>.of(_identity);
      case FilterPreset.grayscale:
        return _saturation(-1); // sat 0
      case FilterPreset.sepia:
        return List<double>.of(_sepia);
      case FilterPreset.vintage:
        // Warm, gently faded, slightly muted.
        var m = _lift(14);
        m = _mul(_contrast(-0.08), m);
        m = _mul(_saturation(-0.18), m);
        m = _mul(_warmth(0.32), m);
        return m;
      case FilterPreset.cool:
        var m = _warmth(-0.30);
        m = _mul(_saturation(0.08), m);
        m = _mul(_contrast(0.06), m);
        return m;
      case FilterPreset.highContrast:
        var m = _contrast(0.34);
        m = _mul(_saturation(0.12), m);
        return m;
      case FilterPreset.fade:
        var m = _lift(30);
        m = _mul(_contrast(-0.18), m);
        m = _mul(_saturation(-0.12), m);
        return m;
    }
  }

  /// Compose two 4×5 colour matrices: applies [b] first, then [a] (a·b).
  static List<double> _mul(List<double> a, List<double> b) {
    // Treat each as 5×5 with an implicit last row [0,0,0,0,1].
    double av(int r, int c) => r < 4 ? a[r * 5 + c] : (c == 4 ? 1 : 0);
    double bv(int r, int c) => r < 4 ? b[r * 5 + c] : (c == 4 ? 1 : 0);
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var sum = 0.0;
        for (var k = 0; k < 5; k++) {
          sum += av(r, k) * bv(k, c);
        }
        out[r * 5 + c] = sum;
      }
    }
    return out;
  }
}

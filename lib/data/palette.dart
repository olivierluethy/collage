import 'package:flutter/widgets.dart';

/// A curated colour palette used by every colour picker (text, shapes,
/// borders, backgrounds) so colour choices feel consistent across the app.
class Palette {
  Palette._();

  static const List<Color> swatches = [
    Color(0xFFF5EFE7), // paper white
    Color(0xFF131110), // ink
    Color(0xFF8A7F71), // taupe
    Color(0xFFFFB454), // safelight amber
    Color(0xFFF59E2E), // deep amber
    Color(0xFFFF6B5E), // coral
    Color(0xFFE23E57), // rose red
    Color(0xFFFF8FB1), // pink
    Color(0xFFB388FF), // lavender
    Color(0xFF6C63FF), // indigo
    Color(0xFF6FB2FF), // sky
    Color(0xFF3DD6C4), // teal
    Color(0xFF6FD08C), // mint
    Color(0xFFB6D94C), // lime
    Color(0xFFFFD75E), // sunflower
    Color(0xFF8D6E63), // cocoa
  ];

  /// Preset gradients (start, end) for backgrounds.
  static const List<(Color, Color)> gradients = [
    (Color(0xFFFFB454), Color(0xFFF5665E)), // sunset
    (Color(0xFF6C63FF), Color(0xFFB388FF)), // dusk
    (Color(0xFF3DD6C4), Color(0xFF6FB2FF)), // lagoon
    (Color(0xFFFF8FB1), Color(0xFFFFD75E)), // candy
    (Color(0xFF211D19), Color(0xFF4E463D)), // graphite
    (Color(0xFF6FD08C), Color(0xFFB6D94C)), // meadow
  ];

  /// Pattern keys drawn by PatternPainter (no asset files).
  static const List<String> patterns = [
    'dots',
    'grid',
    'stripes',
    'chevron',
    'hearts',
    'triangles',
    'confetti',
    'crosses',
  ];
}

import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Curated font choices for text elements. Keys are stored in the project so
/// text keeps its font when re-opened.
class AppFonts {
  AppFonts._();

  static const List<(String, String)> choices = [
    ('inter', 'Inter'),
    ('fraunces', 'Fraunces'),
    ('pacifico', 'Pacifico'),
    ('lobster', 'Lobster'),
    ('oswald', 'Oswald'),
    ('caveat', 'Caveat'),
    ('bebas', 'Bebas Neue'),
    ('playfair', 'Playfair'),
  ];

  static TextStyle style(
    String key, {
    required double fontSize,
    required Color color,
    bool bold = false,
    bool italic = false,
  }) {
    final weight = bold ? FontWeight.w700 : FontWeight.w500;
    final fs = italic ? FontStyle.italic : FontStyle.normal;
    switch (key) {
      case 'fraunces':
        return GoogleFonts.fraunces(fontSize: fontSize, color: color, fontWeight: weight, fontStyle: fs);
      case 'pacifico':
        return GoogleFonts.pacifico(fontSize: fontSize, color: color, fontStyle: fs);
      case 'lobster':
        return GoogleFonts.lobster(fontSize: fontSize, color: color, fontStyle: fs);
      case 'oswald':
        return GoogleFonts.oswald(fontSize: fontSize, color: color, fontWeight: weight, fontStyle: fs);
      case 'caveat':
        return GoogleFonts.caveat(fontSize: fontSize, color: color, fontWeight: weight, fontStyle: fs);
      case 'bebas':
        return GoogleFonts.bebasNeue(fontSize: fontSize, color: color, fontStyle: fs);
      case 'playfair':
        return GoogleFonts.playfairDisplay(fontSize: fontSize, color: color, fontWeight: weight, fontStyle: fs);
      case 'inter':
      default:
        return GoogleFonts.inter(fontSize: fontSize, color: color, fontWeight: weight, fontStyle: fs);
    }
  }
}

import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/remote_catalog.dart';

/// Curated font choices for text elements. Keys are stored in the project so
/// text keeps its font when re-opened.
///
/// [choices] are the bundled set. Extra fonts can be supplied at runtime from a
/// remote catalog (see [registerRemote]): either a Google Fonts family name or
/// a direct font-file URL that has been loaded into the engine.
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

  static final List<(String, String)> _remoteChoices = [];
  static final Map<String, RemoteFont> _remoteByKey = {};

  /// Bundled choices followed by any remote ones, for the text panel.
  static List<(String, String)> get allChoices => [...choices, ..._remoteChoices];

  /// Replace the registered remote fonts (called when the catalog loads).
  static void registerRemote(List<RemoteFont> fonts) {
    _remoteChoices.clear();
    _remoteByKey.clear();
    for (final f in fonts) {
      _remoteByKey[f.key] = f;
      _remoteChoices.add((f.key, f.family));
    }
  }

  static TextStyle style(
    String key, {
    required double fontSize,
    required Color color,
    bool bold = false,
    bool italic = false,
  }) {
    final weight = bold ? FontWeight.w700 : FontWeight.w500;
    final fs = italic ? FontStyle.italic : FontStyle.normal;

    final remote = _remoteByKey[key];
    if (remote != null) {
      return _remoteStyle(remote, fontSize: fontSize, color: color, weight: weight, fs: fs);
    }

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

  /// Resolve a remote font: a Google Fonts family name when given, else a
  /// preloaded font-file family. Unknown Google families fall back to Inter.
  static TextStyle _remoteStyle(
    RemoteFont f, {
    required double fontSize,
    required Color color,
    required FontWeight weight,
    required FontStyle fs,
  }) {
    final google = f.googleFont;
    if (google != null && google.isNotEmpty) {
      try {
        return GoogleFonts.getFont(
          google,
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          fontStyle: fs,
        );
      } catch (_) {
        // Unknown family name — fall through to the file/default path.
      }
    }
    if (f.url != null) {
      return TextStyle(
        fontFamily: f.family,
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
        fontStyle: fs,
      );
    }
    return GoogleFonts.inter(fontSize: fontSize, color: color, fontWeight: weight, fontStyle: fs);
  }
}

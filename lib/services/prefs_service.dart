import 'package:shared_preferences/shared_preferences.dart';

/// Small key/value store for first-run flags (onboarding, coach-marks).
class PrefsService {
  PrefsService(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsService> create() async =>
      PrefsService(await SharedPreferences.getInstance());

  static const _kOnboardingDone = 'onboarding_done';
  static const _kCoachPrefix = 'coach_';
  static const _kThemeMode = 'theme_mode';
  static const _kLocale = 'locale';
  static const _kCatalogFonts = 'catalog_fonts_json';
  static const _kCatalogStickers = 'catalog_stickers_json';

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboardingDone, true);

  bool coachSeen(String id) => _prefs.getBool('$_kCoachPrefix$id') ?? false;
  Future<void> setCoachSeen(String id) => _prefs.setBool('$_kCoachPrefix$id', true);

  /// Persisted theme preference: 'system' | 'light' | 'dark' (absent = system).
  String? get themeModeName => _prefs.getString(_kThemeMode);
  Future<void> setThemeModeName(String name) => _prefs.setString(_kThemeMode, name);

  /// Persisted language code (absent = follow the device).
  String? get localeCode => _prefs.getString(_kLocale);
  Future<void> setLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, code);
    }
  }

  Future<void> resetGuides() async {
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(_kCoachPrefix) || k == _kOnboardingDone) {
        await _prefs.remove(k);
      }
    }
  }

  /// Raw JSON of the remote font catalog, cached from the last successful fetch.
  String? get catalogFontsJson => _prefs.getString(_kCatalogFonts);

  /// Raw JSON of the remote sticker catalog, cached from the last fetch.
  String? get catalogStickersJson => _prefs.getString(_kCatalogStickers);

  Future<void> setCatalogCache({
    required String fonts,
    required String stickers,
  }) async {
    await _prefs.setString(_kCatalogFonts, fonts);
    await _prefs.setString(_kCatalogStickers, stickers);
  }
}

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
  static const _kExportFormat = 'export_format';
  static const _kExportSize = 'export_size';

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

  /// Last export choice ('png' | 'jpg', 'small' | 'standard' | 'large'), so
  /// the Save sheet opens on what the user picked before.
  String? get exportFormatName => _prefs.getString(_kExportFormat);
  String? get exportSizeName => _prefs.getString(_kExportSize);
  Future<void> setExportChoice({required String format, required String size}) async {
    await _prefs.setString(_kExportFormat, format);
    await _prefs.setString(_kExportSize, size);
  }

  /// Show every in-app tip and the editor tour again (onboarding stays done).
  Future<void> resetCoachMarks() async {
    for (final k in _prefs.getKeys().toList()) {
      if (k.startsWith(_kCoachPrefix)) await _prefs.remove(k);
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

  // --- v1.7 templates, occasions, birthdays, reminders ----------------------
  // Generic typed access for the keys below; lib/state/occasions.dart owns
  // their meaning and defaults.

  static const kTemplateFavourites = 'template_favourites';
  static const kOccasionSuggestions = 'occasion_suggestions';
  static const kOccasionRegion = 'occasion_region';
  static const kOccasionDismissed = 'occasion_dismissed';
  static const kBirthdays = 'birthdays_json';
  static const kContactsConnected = 'birthdays_contacts';
  static const kRemindersOn = 'reminders_on';
  static const kRemindOccasions = 'reminders_occasions';
  static const kRemindBirthdays = 'reminders_birthdays';
  static const kReminderFrequency = 'reminders_frequency';
  static const kQuietStart = 'reminders_quiet_start';
  static const kQuietEnd = 'reminders_quiet_end';

  bool? getBool(String key) => _prefs.getBool(key);
  int? getInt(String key) => _prefs.getInt(key);
  String? getString(String key) => _prefs.getString(key);
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  Future<void> setBool(String key, bool v) => _prefs.setBool(key, v);
  Future<void> setInt(String key, int v) => _prefs.setInt(key, v);
  Future<void> setStringList(String key, List<String> v) => _prefs.setStringList(key, v);

  /// Stores [v], or removes the key when [v] is null.
  Future<void> setStringOrRemove(String key, String? v) async {
    if (v == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, v);
    }
  }
}

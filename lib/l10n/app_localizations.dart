import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'locales/ar.dart';
import 'locales/bn.dart';
import 'locales/de.dart';
import 'locales/en.dart';
import 'locales/es.dart';
import 'locales/fr.dart';
import 'locales/hi.dart';
import 'locales/id.dart';
import 'locales/it.dart';
import 'locales/ja.dart';
import 'locales/ko.dart';
import 'locales/pt.dart';
import 'locales/ru.dart';
import 'locales/tr.dart';
import 'locales/zh.dart';

/// One supported language: its [code] (matching the locale files) and its
/// endonym [name] (shown in the language picker in the language itself).
class AppLanguage {
  const AppLanguage(this.code, this.name);
  final String code;
  final String name;
}

/// Lightweight, dependency-free localization. Each locale is a
/// `Map<String, String>` in `lib/l10n/locales/<code>.dart`, keyed by the same
/// keys as the English source of truth (`locales/en.dart`). Missing keys fall
/// back to English, and an assertion flags typos in debug builds.
class AppLocalizations {
  AppLocalizations(this.locale) : _map = maps[locale.languageCode] ?? en;

  final Locale locale;
  final Map<String, String> _map;

  static const delegate = _AppLocalizationsDelegate();

  /// The 15 most widely spoken languages, in a display order that puts English
  /// first. Order here drives the picker and [supportedLocales].
  static const languages = <AppLanguage>[
    AppLanguage('en', 'English'),
    AppLanguage('zh', '中文'),
    AppLanguage('hi', 'हिन्दी'),
    AppLanguage('es', 'Español'),
    AppLanguage('ar', 'العربية'),
    AppLanguage('bn', 'বাংলা'),
    AppLanguage('fr', 'Français'),
    AppLanguage('ru', 'Русский'),
    AppLanguage('pt', 'Português'),
    AppLanguage('id', 'Bahasa Indonesia'),
    AppLanguage('de', 'Deutsch'),
    AppLanguage('ja', '日本語'),
    AppLanguage('tr', 'Türkçe'),
    AppLanguage('it', 'Italiano'),
    AppLanguage('ko', '한국어'),
  ];

  static List<Locale> get supportedLocales =>
      [for (final l in languages) Locale(l.code)];

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizations(const Locale('en'));

  /// Translate [key]; falls back to English, then to the key itself.
  String t(String key) {
    final v = _map[key];
    if (v != null) return v;
    assert(en.containsKey(key), 'Missing string key: $key');
    return en[key] ?? key;
  }

  /// Translate [key] and substitute `{placeholders}` from [args].
  String a(String key, Map<String, String> args) {
    var s = t(key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  /// Every locale map, keyed by language code. Public so tests can assert that
  /// each one carries exactly the English key set.
  static const Map<String, Map<String, String>> maps = {
    'en': en,
    'zh': zh,
    'hi': hi,
    'es': es,
    'ar': ar,
    'bn': bn,
    'fr': fr,
    'ru': ru,
    'pt': pt,
    'id': id,
    'de': de,
    'ja': ja,
    'tr': tr,
    'it': it,
    'ko': ko,
  };
}

/// `context.l10n.t('save')`.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.languages.any((l) => l.code == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

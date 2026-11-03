import 'package:intl/intl.dart';

import 'app_localizations.dart';

/// Plural-aware lookups on top of [AppLocalizations].
///
/// A plural phrase is stored as four keys — `<key>_one`, `<key>_few`,
/// `<key>_many` and `<key>_other` — each carrying `{n}`. Every language has all
/// four (identical key sets); languages without a distinct form simply repeat
/// the `other` text. The form is chosen with the CLDR rules of the current
/// language via [Intl.pluralLogic], so "1 collage", "3 коллажа", "5 коллажей"
/// all come out right.
extension PluralL10n on AppLocalizations {
  String p(String key, int n, [Map<String, String> args = const {}]) {
    String form(String f) => a('${key}_$f', {...args, 'n': '$n'});
    try {
      return Intl.pluralLogic<String>(
        n,
        one: form('one'),
        few: form('few'),
        many: form('many'),
        other: form('other'),
        locale: locale.languageCode,
      );
    } catch (_) {
      return n == 1 ? form('one') : form('other');
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/occasion_service.dart';
import '../../state/occasions.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'birthdays_screen.dart';
import 'reminders_screen.dart';

/// The "Notifications & suggestions" group of the More tab: notifications
/// (all off by default) first, then in-app suggestions — which never need
/// notification or contacts permission — region and birthdays.
List<Widget> occasionSettingsRows(BuildContext context, WidgetRef ref) {
  final l = context.l10n;
  final p = ref.watch(occasionPrefsProvider);
  final region = ref.watch(occasionRegionProvider);
  final birthdays = ref.watch(birthdaysProvider).length;
  return [
    SettingsRow(
      icon: Icons.notifications_none_rounded,
      title: l.t('remTitle'),
      value: p.remindersOn || p.notifyExports ? l.t('remOn') : l.t('remOff'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RemindersScreen())),
    ),
    SettingsSwitchRow(
      icon: Icons.event_available_rounded,
      title: l.t('setOccasionSuggestions'),
      subtitle: l.t('setOccasionSuggestionsHint'),
      value: p.suggestions,
      onChanged: ref.read(occasionPrefsProvider.notifier).setSuggestions,
    ),
    SettingsSwitchRow(
      icon: Icons.auto_awesome_outlined,
      title: l.t('setMemorySuggestions'),
      subtitle: l.t('setMemorySuggestionsHint'),
      value: p.discoverSuggestions,
      onChanged: ref.read(occasionPrefsProvider.notifier).setDiscoverSuggestions,
    ),
    SettingsRow(
      icon: Icons.public_rounded,
      title: l.t('setRegion'),
      value: p.region == null
          ? (region.isEmpty ? l.t('setRegionAuto') : l.a('setRegionAutoIs', {'region': regionName(region)}))
          : regionName(region),
      onTap: () => showRegionPicker(context, ref),
    ),
    SettingsRow(
      icon: Icons.cake_outlined,
      title: l.t('bdayTitle'),
      subtitle: birthdays == 0 ? l.t('setBirthdaysNone') : l.a('setBirthdaysCount', {'count': '$birthdays'}),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BirthdaysScreen())),
    ),
  ];
}

/// A settings row in the More-tab style: icon, title, then either a quiet
/// subtitle or the current [value] in amber, and a chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = value ?? subtitle;
    return ListTile(
      minTileHeight: 56,
      leading: Icon(icon, color: c.textMid),
      title: Text(title, style: context.text.bodyLg),
      subtitle: sub == null
          ? null
          : Text(sub, style: context.text.caption.copyWith(color: value != null ? c.amber : c.textMid)),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textLo),
      onTap: onTap,
    );
  }
}

/// A settings row with a switch; tapping anywhere on the row toggles it.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SwitchListTile(
      secondary: icon == null ? null : Icon(icon, color: enabled ? c.textMid : c.textDisabled),
      title: Text(title, style: context.text.bodyLg.copyWith(color: enabled ? c.textHi : c.textDisabled)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: context.text.caption.copyWith(color: enabled ? c.textMid : c.textDisabled)),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// Region picker sheet: automatic (device) or one of the regions the
/// occasion calendar knows.
Future<void> showRegionPicker(BuildContext context, WidgetRef ref) async {
  final chosen = ref.read(occasionPrefsProvider).region;
  final device = deviceRegion();
  final l = context.l10n;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      Widget check(bool on) => on ? Icon(Icons.check_rounded, color: c.amber) : const SizedBox.shrink();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xs),
                child: Text(l.t('setRegion'), style: sheet.text.titleMd),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
                child: Text(l.t('setRegionHint'), style: sheet.text.bodyMd.copyWith(color: c.textMid)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.my_location_rounded),
                      title: Text(l.t('setRegionAuto')),
                      subtitle: device.isEmpty ? null : Text(regionName(device)),
                      trailing: check(chosen == null),
                      onTap: () {
                        ref.read(occasionPrefsProvider.notifier).setRegion(null);
                        Navigator.pop(sheet);
                      },
                    ),
                    for (final r in OccasionService.knownRegions)
                      ListTile(
                        leading: Text(regionFlag(r), style: const TextStyle(fontSize: 22)),
                        title: Text(regionName(r)),
                        trailing: check(chosen == r),
                        onTap: () {
                          ref.read(occasionPrefsProvider.notifier).setRegion(r);
                          Navigator.pop(sheet);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The flag emoji for an ISO country code.
String regionFlag(String code) {
  if (code.length != 2) return '';
  final a = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
  final b = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
  return String.fromCharCodes([a, b]);
}

/// A region's own name (endonym, like the language picker), else its code.
String regionName(String code) => _endonyms[code] ?? code;

const Map<String, String> _endonyms = {
  'AE': 'الإمارات',
  'AF': 'افغانستان',
  'AR': 'Argentina',
  'AT': 'Österreich',
  'AU': 'Australia',
  'BD': 'বাংলাদেশ',
  'BE': 'België · Belgique',
  'BG': 'България',
  'BH': 'البحرين',
  'BN': 'Brunei',
  'BR': 'Brasil',
  'BY': 'Беларусь',
  'CA': 'Canada',
  'CH': 'Schweiz · Suisse · Svizzera',
  'CL': 'Chile',
  'CN': '中国',
  'CO': 'Colombia',
  'CY': 'Κύπρος',
  'CZ': 'Česko',
  'DE': 'Deutschland',
  'DK': 'Danmark',
  'DZ': 'الجزائر',
  'EE': 'Eesti',
  'EG': 'مصر',
  'ES': 'España',
  'ET': 'ኢትዮጵያ',
  'FI': 'Suomi',
  'FR': 'France',
  'GB': 'United Kingdom',
  'GE': 'საქართველო',
  'GR': 'Ελλάδα',
  'HK': '香港',
  'HR': 'Hrvatska',
  'HU': 'Magyarország',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IN': 'भारत · India',
  'IQ': 'العراق',
  'IS': 'Ísland',
  'IT': 'Italia',
  'JO': 'الأردن',
  'JP': '日本',
  'KR': '대한민국',
  'KW': 'الكويت',
  'LB': 'لبنان',
  'LI': 'Liechtenstein',
  'LT': 'Lietuva',
  'LU': 'Lëtzebuerg',
  'LV': 'Latvija',
  'LY': 'ليبيا',
  'MA': 'المغرب',
  'MD': 'Moldova',
  'ME': 'Crna Gora',
  'MK': 'Северна Македонија',
  'MO': '澳門',
  'MX': 'México',
  'MY': 'Malaysia',
  'NL': 'Nederland',
  'NO': 'Norge',
  'NZ': 'New Zealand',
  'OM': 'عُمان',
  'PE': 'Perú',
  'PH': 'Pilipinas',
  'PK': 'پاکستان',
  'PL': 'Polska',
  'PS': 'فلسطين',
  'PT': 'Portugal',
  'QA': 'قطر',
  'RO': 'România',
  'RS': 'Србија',
  'RU': 'Россия',
  'SA': 'السعودية',
  'SD': 'السودان',
  'SE': 'Sverige',
  'SG': 'Singapore',
  'SI': 'Slovenija',
  'SK': 'Slovensko',
  'SN': 'Sénégal',
  'SY': 'سوريا',
  'TH': 'ประเทศไทย',
  'TN': 'تونس',
  'TR': 'Türkiye',
  'TW': '臺灣',
  'UA': 'Україна',
  'US': 'United States',
  'YE': 'اليمن',
  'ZA': 'South Africa',
};

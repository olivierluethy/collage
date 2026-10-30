import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../state/settings.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'backup_actions.dart';

/// The "Information" hub: About, Privacy Policy, Terms of Service, Language and
/// Theme. Opened from the ⓘ button on the home screen.
class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final activeCode = settings.locale?.languageCode ??
        Localizations.localeOf(context).languageCode;
    final themeLabel = switch (settings.themeMode) {
      ThemeMode.light => l.t('themeLight'),
      ThemeMode.dark => l.t('themeDark'),
      ThemeMode.system => l.t('themeSystem'),
    };

    return Scaffold(
      appBar: AppBar(title: Text(l.t('infoTitle'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        children: [
          _Tile(
            icon: Icons.info_outline_rounded,
            title: l.t('about'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          _Tile(
            icon: Icons.language_rounded,
            title: l.t('language'),
            value: _languageName(activeCode),
            onTap: () => _pickLanguage(context, ref, activeCode),
          ),
          _Tile(
            icon: Icons.brightness_6_rounded,
            title: l.t('theme'),
            value: themeLabel,
            onTap: () => _pickTheme(context, ref),
          ),
          const Divider(),
          _Tile(
            icon: Icons.backup_outlined,
            title: l.t('backupCreate'),
            onTap: () => createBackup(context, ref),
          ),
          _Tile(
            icon: Icons.settings_backup_restore_rounded,
            title: l.t('backupRestore'),
            onTap: () => restoreBackup(context, ref),
          ),
          const Divider(),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: l.t('privacyPolicy'),
            onTap: () => _open(context, Config.privacyPolicyUrl),
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: l.t('termsOfService'),
            onTap: () => _open(context, Config.termsOfServiceUrl),
          ),
        ],
      ),
    );
  }

  static String? _languageName(String code) {
    for (final lang in AppLocalizations.languages) {
      if (lang.code == code) return lang.name;
    }
    return null;
  }

  Future<void> _pickLanguage(
      BuildContext context, WidgetRef ref, String activeCode) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final lang in AppLocalizations.languages)
              ListTile(
                title: Text(lang.name),
                trailing: lang.code == activeCode
                    ? Icon(Icons.check_rounded, color: sheetContext.colors.amber)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setLocale(Locale(lang.code));
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final current = ref.read(settingsProvider).themeMode;
    final options = <(ThemeMode, String)>[
      (ThemeMode.system, l.t('themeSystem')),
      (ThemeMode.light, l.t('themeLight')),
      (ThemeMode.dark, l.t('themeDark')),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (mode, label) in options)
              ListTile(
                title: Text(label),
                trailing: mode == current
                    ? Icon(Icons.check_rounded, color: sheetContext.colors.amber)
                    : null,
                onTap: () {
                  ref.read(settingsProvider.notifier).setThemeMode(mode);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('linkError'))),
        );
      }
    }
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final t = context.text;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('about'))),
      body: ListView(
        padding: const EdgeInsets.all(Space.xl),
        children: [
          Center(
            child: Image.asset('assets/icon/icon.png', width: 96, height: 96),
          ),
          const SizedBox(height: Space.lg),
          Center(child: Text(l.t('appTitle'), style: t.displayMd)),
          const SizedBox(height: Space.xs),
          Center(
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Text(
                l.a('appVersion', {'version': snap.data?.version ?? '—'}),
                style: t.caption.copyWith(color: c.textLo),
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          Text(l.t('aboutBody'), style: t.bodyMd, textAlign: TextAlign.center),
          const SizedBox(height: Space.lg),
          Center(
            child: Text(
              l.a('madeBy', {'name': 'Olivier Lüthy'}),
              style: t.caption.copyWith(color: c.textLo),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      leading: Icon(icon, color: c.textMid),
      title: Text(title, style: context.text.bodyLg),
      subtitle: value == null
          ? null
          : Text(value!, style: context.text.caption.copyWith(color: c.textMid)),
      trailing: Icon(Icons.chevron_right_rounded, color: c.textLo),
      onTap: onTap,
    );
  }
}

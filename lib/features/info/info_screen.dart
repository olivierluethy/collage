import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/draft_service.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../books/books_screen.dart';
import '../trash/trash_screen.dart';
import 'backup_actions.dart';
import 'settings_pickers.dart';

/// The "More" tab: everything that isn't making a collage, grouped by what the
/// user wants to do — find things (photo books, trash), keep them safe
/// (backup), adjust the app (language, theme, tips) and read about it.
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final settings = ref.watch(settingsProvider);
    final code = activeLanguageCode(context, ref);
    final trashCount = ref.watch(trashProvider).valueOrNull?.length ?? 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        _Group(l.t('moreLibrary'), [
          _Tile(
            icon: Icons.menu_book_rounded,
            title: l.t('booksTitle'),
            subtitle: l.t('moreBooksHint'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BooksScreen()),
            ),
          ),
          _Tile(
            icon: Icons.delete_outline_rounded,
            title: l.t('trashTitle'),
            subtitle: l.a('moreTrashHint', {'days': '${DraftService.trashDays}'}),
            badge: trashCount > 0 ? '$trashCount' : null,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TrashScreen()),
            ),
          ),
        ]),
        _Group(l.t('moreBackup'), [
          _Tile(
            icon: Icons.backup_outlined,
            title: l.t('backupCreate'),
            subtitle: l.t('moreBackupHint'),
            onTap: () => createBackup(context, ref),
          ),
          _Tile(
            icon: Icons.settings_backup_restore_rounded,
            title: l.t('backupRestore'),
            subtitle: l.t('moreRestoreHint'),
            onTap: () => restoreBackup(context, ref),
          ),
        ]),
        _Group(l.t('moreSettings'), [
          _Tile(
            icon: Icons.language_rounded,
            title: l.t('language'),
            value: languageName(code),
            onTap: () => showLanguagePicker(context, ref),
          ),
          _Tile(
            icon: Icons.brightness_6_rounded,
            title: l.t('theme'),
            value: themeLabel(context, settings.themeMode),
            onTap: () => showThemePicker(context, ref),
          ),
          _Tile(
            icon: Icons.lightbulb_outline_rounded,
            title: l.t('moreShowTips'),
            subtitle: l.t('moreShowTipsHint'),
            chevron: false,
            onTap: () async {
              await ref.read(prefsProvider).resetCoachMarks();
              if (context.mounted) {
                showAppSnack(context, l.t('moreTipsReset'), kind: SnackKind.success);
              }
            },
          ),
        ]),
        _Group(l.t('moreAbout'), [
          _Tile(
            icon: Icons.info_outline_rounded,
            title: l.t('about'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          _Tile(
            icon: Icons.privacy_tip_outlined,
            title: l.t('privacyPolicy'),
            external: true,
            onTap: () => _open(context, Config.privacyPolicyUrl),
          ),
          _Tile(
            icon: Icons.description_outlined,
            title: l.t('termsOfService'),
            external: true,
            onTap: () => _open(context, Config.termsOfServiceUrl),
          ),
        ]),
        const SizedBox(height: Space.lg),
        Center(
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Text(
              l.a('appVersion', {'version': snap.data?.version ?? '—'}),
              style: context.text.caption.copyWith(color: context.colors.textLo),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        showAppSnack(context, context.l10n.t('linkError'), kind: SnackKind.error);
      }
    }
  }
}

/// A titled group of rows on one surface card.
class _Group extends StatelessWidget {
  const _Group(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.sm),
          child: Text(title, style: context.text.labelMd.copyWith(color: c.textMid)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          // A Material (not a decorated box) so the rows' ink splashes show.
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.card),
              side: BorderSide(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 56, color: c.line),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
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
    this.subtitle,
    this.value,
    this.badge,
    this.chevron = true,
    this.external = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final String? badge;
  final bool chevron;
  final bool external;
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
          : Text(sub,
              style: context.text.caption.copyWith(color: value != null ? c.amber : c.textMid)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null) SpecChip(badge!),
          if (external)
            Icon(Icons.open_in_new_rounded, size: 18, color: c.textLo)
          else if (chevron)
            Icon(Icons.chevron_right_rounded, color: c.textLo),
        ],
      ),
      onTap: onTap,
    );
  }
}

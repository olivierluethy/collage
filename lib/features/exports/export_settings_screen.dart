import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/exports.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'export_history_screen.dart';
import 'export_place.dart';

/// Settings → Saving & export: where exported files go, the recent exports,
/// and a short explanation of what "saved", "exported" and "shared" mean in
/// this app.
class ExportSettingsScreen extends ConsumerWidget {
  const ExportSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final count = ref.watch(exportHistoryProvider).valueOrNull?.length ?? 0;

    Widget card(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.card),
              side: BorderSide(color: c.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.sm),
          child: Semantics(header: true, child: Text(text, style: context.text.labelMd.copyWith(color: c.textMid))),
        );

    Widget term(IconData icon, String title, String body) => MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: c.textMid),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.bodyLg),
                      const SizedBox(height: 2),
                      Text(body, style: context.text.caption.copyWith(color: c.textMid)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.t('expSettingsTitle'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Text(l.t('expDestIntro'), style: context.text.bodyMd.copyWith(color: c.textMid)),
          ),
          heading(l.t('expDestTitle')),
          card(const DestinationChooser()),
          heading(l.t('expHistoryTitle')),
          card(
            ListTile(
              minTileHeight: 56,
              leading: Icon(Icons.history_rounded, color: c.textMid),
              title: Text(l.t('expHistoryTitle'), style: context.text.bodyLg),
              subtitle: Text(
                count == 0 ? l.t('expHistoryNone') : l.a('expHistoryCount', {'count': '$count'}),
                style: context.text.caption.copyWith(color: c.textMid),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: c.textLo),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExportHistoryScreen()),
              ),
            ),
          ),
          heading(l.t('expTermsTitle')),
          card(
            Column(
              children: [
                term(Icons.collections_outlined, l.t('expTermProject'), l.t('expTermProjectBody')),
                Divider(height: 1, indent: 56, color: c.line),
                term(Icons.download_rounded, l.t('expTermExport'), l.t('expTermExportBody')),
                Divider(height: 1, indent: 56, color: c.line),
                term(Icons.ios_share_rounded, l.t('expTermShare'), l.t('expTermShareBody')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

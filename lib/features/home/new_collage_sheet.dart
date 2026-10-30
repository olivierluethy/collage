import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/ui.dart';
import '../ai/ai_screen.dart';
import '../flow.dart';

/// The one place every new collage starts: pick photos (the main path), start
/// from a ready-made template, or let AI suggest one. The AI card only shows
/// in builds where AI is configured, so the sheet never offers a dead end.
Future<void> showNewCollageSheet(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onBrowseTemplates,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final l = sheet.l10n;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
                child: Text(l.t('newCollage'), style: sheet.text.titleLg),
              ),
              ActionCard(
                primary: true,
                icon: Icons.photo_library_rounded,
                title: l.t('ncPickPhotos'),
                subtitle: l.t('ncPickPhotosHint'),
                onTap: () => Navigator.pop(sheet, 'photos'),
              ),
              const SizedBox(height: Space.sm),
              ActionCard(
                icon: Icons.dashboard_customize_rounded,
                title: l.t('ncTemplate'),
                subtitle: l.t('ncTemplateHint'),
                onTap: () => Navigator.pop(sheet, 'template'),
              ),
              if (Config.hasAi) ...[
                const SizedBox(height: Space.sm),
                ActionCard(
                  icon: Icons.auto_awesome_rounded,
                  title: l.t('ncAi'),
                  subtitle: l.t('ncAiHint'),
                  onTap: () => Navigator.pop(sheet, 'ai'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'photos':
      await startNewCollage(context, ref);
    case 'template':
      onBrowseTemplates();
    case 'ai':
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiScreen()));
  }
}

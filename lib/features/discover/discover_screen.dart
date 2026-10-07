import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/moments_service.dart';
import '../../services/permission_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../flow.dart';

/// Proactively suggests collages from photo place + date: cards like
/// "{place} — {date}: create this day's collage". Tapping pre-loads exactly
/// those photos into a new, editable collage.
class DiscoverTab extends ConsumerStatefulWidget {
  const DiscoverTab({super.key});

  @override
  ConsumerState<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends ConsumerState<DiscoverTab> {
  bool? _access;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = await ref.read(permissionServiceProvider).current();
    if (mounted) setState(() => _access = a.usable);
  }

  Future<void> _grant() async {
    final ok = await ensureGalleryAccess(context, ref);
    if (!mounted) return;
    setState(() => _access = ok);
    if (ok) ref.invalidate(momentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_access == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_access == false) {
      return EmptyState(
        icon: Icons.explore_outlined,
        title: context.l10n.t('discoverTitle'),
        message: context.l10n.t('discoverMessage'),
        action: PrimaryButton(
          label: context.l10n.t('turnOnPhotos'),
          icon: Icons.photo_library_rounded,
          expand: false,
          onPressed: _grant,
        ),
      );
    }

    final moments = ref.watch(momentsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(momentsProvider),
      child: moments.when(
        loading: () => ListView(
          children: [
            const SizedBox(height: 120),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: Space.lg),
            Center(child: Text(context.l10n.t('findingMoments'))),
          ],
        ),
        error: (e, _) => ListView(children: [
          const SizedBox(height: 120),
          Center(child: Text('$e', style: context.text.bodyMd)),
        ]),
        data: (list) {
          if (list.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyState(
                icon: Icons.auto_awesome_outlined,
                title: context.l10n.t('noMomentsTitle'),
                message: context.l10n.t('noMomentsMessage'),
              ),
            ]);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(Space.lg),
            itemCount: list.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Text(context.l10n.t('tapMomentHint'), style: context.text.bodyMd),
                );
              }
              return _MomentCard(moment: list[i - 1]);
            },
          );
        },
      ),
    );
  }
}

class _MomentCard extends ConsumerWidget {
  const _MomentCard({required this.moment});
  final Moment moment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: GestureDetector(
        onTap: () => openPhotosAsCollage(context, ref, moment.assetIds, title: moment.title),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: context.colors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 110,
                child: Row(
                  children: [
                    for (final id in moment.assetIds.take(4))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(1),
                          child: PhotoImage(assetId: id, fit: BoxFit.cover),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, color: context.colors.amber, size: 20),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(moment.title, style: context.text.titleMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(context.l10n.a('momentSubtitle', {
                            'subtitle': moment.subtitle,
                            'count': '${moment.assetIds.length}',
                          }), style: context.text.caption),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: context.colors.textMid),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

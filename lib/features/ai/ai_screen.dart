import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:uuid/uuid.dart';

import '../../config.dart';
import '../../data/layout_templates.dart';
import '../../l10n/app_localizations.dart';
import '../../models/collage_project.dart';
import '../../services/ai_collage_service.dart';
import '../../state/providers.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/photo_image.dart';
import '../../widgets/ui.dart';
import '../editor/editor_screen.dart';
import '../flow.dart';
import '../picker/photo_picker_screen.dart';

/// AI auto-collage: pick a bunch of photos and get ready-made collages grouped
/// by scene/destination — no manual sorting. Groups by photo location/date on
/// device, and (if an AI key is supplied) refines titles and ordering with
/// Claude vision. Degrades gracefully without a key.
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _SuggestedCollage {
  _SuggestedCollage(this.title, this.assetIds);
  final String title;
  final List<String> assetIds;
}

class _AiScreenState extends ConsumerState<AiScreen> {
  bool _busy = false;
  String _status = '';
  List<_SuggestedCollage> _results = [];

  Future<void> _run() async {
    final l = context.l10n;
    if (!await ensureGalleryAccess(context, ref)) return;
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const PhotoPickerScreen(maxImages: 12)),
    );
    if (picked == null || picked.isEmpty) return;

    setState(() {
      _busy = true;
      _status = l.t('aiStatusLooking');
      _results = [];
    });

    // Group offline by place + day first (works without any key).
    final offline =
        await _clusterByPlaceAndDay(picked, (n) => l.a('aiCollageName', {'n': '$n'}));
    var groups = offline;

    // Refine with AI when a key is present.
    final ai = ref.read(aiServiceProvider);
    if (ai.available) {
      try {
        setState(() => _status = l.t('aiStatusGrouping'));
        final inputs = await _buildInputs(picked);
        final aiGroups = await ai.suggest(inputs);
        if (aiGroups.isNotEmpty) {
          groups = aiGroups.map((g) => _SuggestedCollage(g.title, g.assetIds)).toList();
        }
      } on AiUnavailable {
        // fall through to offline groups
      } catch (_) {
        // AI failed (network/key) — keep the offline grouping.
      }
    }

    setState(() {
      _busy = false;
      _results = groups;
      _status = '';
    });
  }

  Future<List<AiImageInput>> _buildInputs(List<String> ids) => AiCollageService.buildInputs(ids);

  Future<List<_SuggestedCollage>> _clusterByPlaceAndDay(
      List<String> ids, String Function(int n) name) async {
    final buckets = <String, List<String>>{};
    for (final id in ids) {
      final asset = await AssetEntity.fromId(id);
      var key = 'trip';
      if (asset != null) {
        final lat = asset.latitude;
        final lng = asset.longitude;
        final d = asset.createDateTime;
        final place = (lat != null && lng != null && (lat != 0 || lng != 0))
            ? '${(lat * 5).round()}_${(lng * 5).round()}'
            : 'here';
        key = '${d.year}-${d.month}-$place';
      }
      buckets.putIfAbsent(key, () => []).add(id);
    }
    var i = 1;
    return buckets.entries.map((e) => _SuggestedCollage(name(i++), e.value)).toList();
  }

  void _openGroup(_SuggestedCollage g) {
    final pool = g.assetIds.take(9).toList();
    final layout = LayoutTemplates.forCount(pool.length.clamp(1, 9)).first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final project = CollageProject(
      id: const Uuid().v4(),
      title: g.title,
      createdAt: now,
      updatedAt: now,
      ratioLabel: CanvasRatio.square.label,
      layout: layout,
      fills: {},
      elements: [],
      border: BorderSettings(),
      background: BackgroundSettings(),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(project: project, pool: pool)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(context.l10n.t('aiTitle')),
      ),
      body: _busy
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: Space.lg),
                  Text(_status, style: context.text.bodyMd),
                ],
              ),
            )
          : _results.isEmpty
              ? EmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: context.l10n.t('aiHeroTitle'),
                  message: Config.hasAi
                      ? context.l10n.t('aiHeroMessageKey')
                      : context.l10n.t('aiHeroMessageNoKey'),
                  action: PrimaryButton(
                    label: context.l10n.t('choosePhotos'),
                    icon: Icons.auto_awesome_rounded,
                    expand: false,
                    onPressed: _run,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(Space.lg),
                  children: [
                    Text(context.l10n.t('aiTapSuggestion'), style: context.text.bodyMd),
                    const SizedBox(height: Space.md),
                    for (final g in _results) _SuggestionCard(group: g, onTap: () => _openGroup(g)),
                    const SizedBox(height: Space.lg),
                    OutlinedButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(context.l10n.t('tryOtherPhotos')),
                    ),
                  ],
                ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.group, required this.onTap});
  final _SuggestedCollage group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: GestureDetector(
        onTap: onTap,
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
                height: 96,
                child: Row(
                  children: [
                    for (final id in group.assetIds.take(4))
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
                    Expanded(child: Text(group.title, style: context.text.titleMd)),
                    SpecChip('${group.assetIds.length} photos'),
                    const SizedBox(width: Space.sm),
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
